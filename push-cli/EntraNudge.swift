// PUSH — Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import Darwin

struct EntraNudgeCommand {
    let args: [String]
    static let label = "com.push.entra-registration"
    static let plist = "/Library/LaunchDaemons/com.push.entra-registration.plist"
    private var stateFile: String { managedBase + (args.contains("--test") && args.first != "scheduled" ? "/entra-test-state.json" : "/entra-state.json") }
    private func load() throws -> EntraNudgeState {
        guard FileManager.default.fileExists(atPath:stateFile) else { return .init() }
        return try JSONDecoder().decode(EntraNudgeState.self,from:Data(contentsOf:URL(fileURLWithPath:stateFile)))
    }
    private func save(_ state: EntraNudgeState) throws {
        try FileManager.default.createDirectory(atPath:managedBase,withIntermediateDirectories:true)
        try JSONEncoder().encode(state).write(to:URL(fileURLWithPath:stateFile),options:.atomic)
    }
    static func valid(_ config: CLIEntraConfig) -> Bool {
        EntraPolicy.selfServiceURL(policyID:config.policyID) != nil && (0...23).contains(config.startHour) && (1...24).contains(config.endHour) && config.startHour < config.endHour && config.message.count <= 2000 && config.selfServicePath.hasPrefix("/Applications/") && config.selfServicePath.hasSuffix(".app") && config.companyPortalPath.hasPrefix("/Applications/") && config.companyPortalPath.hasSuffix(".app") && config.jamfBinaryPath.hasPrefix("/") && config.jamfBinaryPath.hasSuffix("/jamf")
    }
    func run() {
        let action = args.first ?? "status"
        if action == "preview" {
            var options = ["entraRegistration"]
            if let value = argValue("--stage",in:args) { options += ["--entra-stage",value] }
            PopupCommand(args:options).run(); return
        }
        if action == "install-daemon" { _ = Self.installSchedule(); return }
        if action == "uninstall-daemon" { Self.uninstallSchedule(); return }
        guard ["status","check","notify","scheduled"].contains(action) else { cliError("Usage: push-cli entra status|check|notify|preview|install-daemon|uninstall-daemon [--stage 1...4] [--dry-run] [--force] [--test]"); return }
        guard let config = try? loadConfig() else { cliError("Cannot load Entra nudge policy."); return }
        if action == "status" { report(config:config); return }
        guard config.entra.enabled else { if action != "scheduled" { cliPrint("Entra registration reminders are disabled.") }; return }
        if args.contains("--dry-run") || config.debug.dryRun { cliPrint("Dry run: no registration detection, popup, Self Service launch, inventory sync, or state changes."); return }
        guard getuid() == 0 else { cliError("Use sudo for Entra checks and notification actions."); return }
        let audit: RuntimeHealthScope? = args.contains("--test") ? nil : RuntimeHealthScope(module:"entra",scheduled:action == "scheduled" && args.contains("--from-daemon"))
        defer { audit?.finish() }
        guard Self.valid(config.entra) else { cliError("Invalid Entra policy ID, app paths, message length, or working hours."); return }
        guard let user = consoleUser(), !user.name.hasPrefix("_"), user.uid > 0 else { cliPrint("No eligible console user; Entra reminders are waiting for login."); return }
        RuntimeHealthScope.user(user.uid)
        let test = args.contains("--test") && action != "scheduled"
        let forced = args.contains("--force") && action == "notify"
        try? FileManager.default.createDirectory(atPath:managedBase,withIntermediateDirectories:true)
        let lock = open(managedBase + "/entra.lock",O_CREAT|O_RDWR|O_NOFOLLOW,0o600)
        guard lock >= 0 else { cliError("Cannot prepare Entra state lock."); return }
        defer { close(lock) }
        guard flock(lock,LOCK_EX|LOCK_NB) == 0 else { cliPrint("An Entra check is already running."); return }
        defer { flock(lock,LOCK_UN) }
        do {
            var state = try load()
            let key = String(user.uid)
            var record = state.users[key] ?? .init()
            if !record.userName.isEmpty && record.userName != user.name { record = .init() }
            record.userName = user.name
            let now = Date()
            let day = EntraPolicy.dayKey(now:now,test:test)
            if record.dayKey != day { record.dayKey = day; record.promptsToday = 0 }
            let evidence = detect(user:user,config:config.entra,test:test)
            record.status = evidence.status; record.reason = evidence.reason; record.checkedAt = now
            if evidence.status == .localRegistered {
                let transitioned = record.lastRegistered != true
                record.lastRegistered = true; record.awaitingRegistration = false
                record.laterCount = 0; record.promptsToday = 0; record.lastPromptAt = nil
                if transitioned && config.entra.reconOnRegistration { record.needsRecon = true }
                record.nextReason = "No reminder needed; local registration evidence is present. Cloud compliance is not assessed."
                state.users[key] = record; try save(state)
                if action != "check", !test, record.needsRecon, config.entra.reconOnRegistration, (record.nextReconAt ?? .distantPast) <= now {
                    do {
                        guard let live = try? loadConfig(), live.entra.enabled, !live.debug.dryRun, live.entra.reconOnRegistration, live.entra == config.entra, trustedEntraBinary(config.entra.jamfBinaryPath) else { throw CLIError.invalidValue("Untrusted Jamf binary path") }
                        _ = try discoveryOutput(config.entra.jamfBinaryPath,["recon"],timeout:120)
                        record.needsRecon = false; record.lastReconAt = Date(); record.nextReconAt = nil
                    } catch { record.nextReconAt = Date().addingTimeInterval(3600); record.nextReason = "Local registration detected; inventory sync failed and will retry later." }
                }
                state.users[key] = record; try save(state); cliPrint(record.nextReason); return
            }
            if evidence.status == .needsRegistration { record.lastRegistered = false }
            record.nextReason = evidence.reason
            if action == "check" || evidence.status != .needsRegistration {
                state.users[key] = record; try save(state); cliPrint(evidence.status.title + ": " + evidence.reason); return
            }
            var skip: String?
            if !forced && !test && !EntraPolicy.withinHours(now:now,start:config.entra.startHour,end:config.entra.endHour,weekdaysOnly:config.entra.weekdaysOnly) { skip = "Outside Entra working hours" }
            if !forced, skip == nil { skip = EntraPolicy.dueReason(record,now:now,test:test) }
            if skip == nil && !forced && config.entra.skipMeetings && AutoCheckCommand(args:[]).isUserInMeeting() { skip = "Meeting or screen sharing detected" }
            if skip == nil {
                if let os = try? loadStateForAction() {
                    if os.installStarted { skip = "macOS installation is awaiting reboot verification" }
                } else { skip = "macOS installation state is unreadable" }
            }
            if skip == nil && installationIsActive() != false { skip = "An installer is active or installation activity cannot be verified" }
            if skip == nil {
                for name in ["push-ui","jamfHelper"] {
                    let (_, result) = runDirect("/usr/bin/pgrep",["-x",name])
                    if result != 1 { skip = "Another notification is open, or its activity cannot be verified"; break }
                }
            }
            if let skip { record.nextReason = skip; state.users[key] = record; try save(state); cliPrint(skip); return }
            guard FileManager.default.isExecutableFile(atPath:resolveUIBinary()) else {
                record.nextReason = "PUSH popup app is missing"; state.users[key] = record; try save(state); cliError(record.nextReason); return
            }
            guard let fresh = try? loadConfig(), fresh.entra.enabled, !fresh.debug.dryRun, fresh.entra == config.entra else {
                record.nextReason = "Policy changed during the check; no reminder was shown"; state.users[key] = record; try save(state); return
            }
            let stage = EntraPolicy.stage(laterCount:record.laterCount,test:test)
            var notice = EntraNotice.preview(stage:stage.number)
            notice.laterCount = min(100000,record.laterCount)
            if !config.entra.message.isEmpty { notice.message = config.entra.message }
            let payload = try JSONEncoder().encode(notice).base64EncodedString()
            record.promptsToday += 1; record.lastPromptAt = now
            if record.firstPromptAt == nil { record.firstPromptAt = now }
            record.nextReason = "Prompt attempt recorded before display"
            state.users[key] = record; try save(state)
            let command = shellArgument(resolveUIBinary()) + " --state entraRegistration --config " + shellArgument(resolvedConfigPath ?? "") + " --entra-payload " + shellArgument(payload) + (test ? " --manual-test" : "")
            let response = runUIBlocking(command,timeoutMinutes:15)
            guard let current = consoleUser(), current.uid == user.uid, current.name == user.name else {
                record.nextReason = "Active user changed; no registration action was started"; state.users[key] = record; try save(state); return
            }
            EntraPolicy.recordResponse(response,state:&record)
            switch response {
            case 0:
                if test { record.nextReason = "Test mode: Register Now recorded in isolated test state; Self Service was not opened"; break }
                guard let live = try? loadConfig(), live.entra.enabled, !live.debug.dryRun, live.entra == config.entra else {
                    record.nextReason = "Policy changed while the window was open; Self Service was not opened"; break
                }
                // A click opens the managed workflow; it is never recorded as registration completion.
                guard validEntraApp(config.entra.selfServicePath,bundleID:"com.jamfsoftware.selfservice.mac"), let url = EntraPolicy.selfServiceURL(policyID:config.entra.policyID) else {
                    record.nextReason = "Self Service is unavailable; registration has not been completed"; break
                }
                let (_, result) = runDirect("/bin/launchctl",["asuser",String(user.uid),"/usr/bin/sudo","-n","-u",user.name,"--","/usr/bin/open","-a",config.entra.selfServicePath,url.absoluteString])
                if result == 0 { record.openedCount += 1; record.awaitingRegistration = true; record.nextReason = "Self Service opened; waiting for fresh registration evidence on the next check" }
                else { record.nextReason = "Self Service could not be opened; registration is still pending" }
            case 1: record.nextReason = "User selected Later; waiting for the stage reminder gap"
            case 2: record.nextReason = "Window closed; not counted as an explicit Later click"
            case 6: record.nextReason = "User selected Contact IT; registration is still pending"
            case 100: record.nextReason = "Prompt timed out; not counted as an explicit Later click"
            default: record.nextReason = "Popup failed or returned an unexpected response; no registration action was started"
            }
            state.users[key] = record; try save(state); cliPrint(record.nextReason)
        } catch { cliError("Entra state could not be read or saved; no further action started.") }
    }
    private func detect(user: (name:String,uid:Int), config: CLIEntraConfig, test: Bool) -> EntraEvidence {
        if !test {
            do {
                let output = try discoveryOutput("/usr/bin/profiles",["status","-type","enrollment"],timeout:15)
                guard output.range(of:#"(?im)^\s*MDM enrollment:\s*Yes\b"#,options:.regularExpression) != nil else {
                    if output.range(of:#"(?im)^\s*MDM enrollment:\s*No\b"#,options:.regularExpression) != nil { return .init(status:.notApplicable,reason:"This Mac is not MDM enrolled; production Entra nudges are inactive.") }
                    return .init(status:.verificationUnavailable,reason:"MDM enrollment output was not recognized.")
                }
            } catch { return .init(status:.verificationUnavailable,reason:"MDM enrollment could not be checked.") }
        }
        guard trustedEntraBinary(config.jamfBinaryPath) else { return .init(status:.setupMissing,reason:"A trusted Jamf management binary is required for this Jamf registration workflow.") }
        guard validEntraApp(config.companyPortalPath,bundleID:"com.microsoft.CompanyPortalMac") else { return .init(status:.setupMissing,reason:"Microsoft Company Portal is missing or its app identity cannot be verified.") }
        guard validEntraApp(config.selfServicePath,bundleID:"com.jamfsoftware.selfservice.mac") else { return .init(status:.setupMissing,reason:"Jamf Self Service is missing or its app identity cannot be verified.") }
        guard let home = FileManager.default.homeDirectory(forUser:user.name) else { return .init(status:.verificationUnavailable,reason:"The console user's home directory could not be resolved.") }
        let path = home.appendingPathComponent("Library/Preferences/com.jamf.management.jamfAAD.plist")
        var info = stat()
        if lstat(path.path,&info) != 0 {
            if errno == ENOENT { return EntraPolicy.jamfAAD(data:nil,exists:false) }
            return .init(status:.verificationUnavailable,reason:"The current user's registration preference metadata could not be read.")
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_size <= 1_048_576 else {
            return .init(status:.verificationUnavailable,reason:"Jamf registration preference is not a bounded regular file.")
        }
        return EntraPolicy.jamfAAD(data:try? Data(contentsOf:path),exists:true)
    }

    private func report(config: CLIConfig) {
        if args.contains("--ea") && !config.entra.enabled { print("<result>disabled</result>"); return }
        guard let user = consoleUser() else {
            if args.contains("--ea") { print("<result>No console user</result>") }
            else { cliPrint("No console user; no per-user registration claim is available.") }
            return
        }
        do {
            let saved = try load().users[String(user.uid)]
            let record = saved?.userName == user.name ? saved : nil
            if args.contains("--ea") { print("<result>\(record?.status.rawValue ?? "notChecked")</result>"); return }
            if args.contains("--json") {
                let value: [String:Any] = ["enabled":config.entra.enabled,"userUID":user.uid,"registrationStatus":record?.status.rawValue ?? "notChecked","compliance":"notAssessed","laterCount":record?.laterCount ?? 0,"closedCount":record?.closedCount ?? 0,"timedOutCount":record?.timedOutCount ?? 0,"reason":record?.nextReason ?? "Not checked","checkedAt":record?.checkedAt.map { ISO8601DateFormatter().string(from:$0) } ?? ""]
                print(String(decoding:try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self)); return
            }
            cliSection("Entra registration reminders")
            cliInfo("Mode:",args.contains("--test") ? "Isolated test state" : "Production state")
            cliInfo("Enabled:",String(config.entra.enabled)); cliInfo("Self Service policy:",config.entra.policyID)
            cliInfo("User:",user.name); cliInfo("Local status:",record?.status.title ?? "Not checked")
            cliInfo("Cloud compliance:","Not assessed")
            cliInfo("Reason:",record?.nextReason ?? "No result saved")
            cliInfo("Checked:",record?.checkedAt.map { ISO8601DateFormatter().string(from:$0) } ?? "Never")
            cliInfo("Stage:",String(EntraPolicy.stage(laterCount:record?.laterCount ?? 0).number))
            cliInfo("Later / close / timeout:","\(record?.laterCount ?? 0) / \(record?.closedCount ?? 0) / \(record?.timedOutCount ?? 0)")
            cliInfo("Self Service opens:",String(record?.openedCount ?? 0))
            cliInfo("Registration monitor:",FileManager.default.fileExists(atPath:Self.plist) ? "Installed — checks every 5 minutes" : "Not installed")
        } catch {
            if args.contains("--ea") { print("<result>unreadableState</result>") } else { cliError("Saved Entra state is unreadable.") }
        }
    }
    @discardableResult static func installSchedule() -> Bool {
        guard getuid() == 0, let config = try? loadConfig(), config.entra.enabled, valid(config.entra), FileManager.default.isExecutableFile(atPath:managedBase + "/push-cli") else { cliError("Enable and validate Entra policy before installing its monitor with sudo."); return false }
        let object: [String:Any] = ["Label":label,"ProgramArguments":[managedBase + "/push-cli","entra","scheduled","--from-daemon"],"RunAtLoad":true,"StartInterval":300,"ProcessType":"Background","StandardOutPath":managedBase + "/logs/entra-monitor.log","StandardErrorPath":managedBase + "/logs/entra-monitor.log"]
        do {
            try FileManager.default.createDirectory(atPath:managedBase + "/logs",withIntermediateDirectories:true)
            let data = try PropertyListSerialization.data(fromPropertyList:object,format:.xml,options:0)
            try data.write(to:URL(fileURLWithPath:plist),options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:plist)
            _ = runDirect("/bin/launchctl",["bootout","system/" + label])
            let (_, code) = runDirect("/bin/launchctl",["bootstrap","system",plist])
            guard code == 0 else { cliError("Entra monitor could not be loaded."); return false }
            RuntimeHealthScope.monitorIntent("entra",desired:"enabled",reason:"Administrator enabled registration monitoring")
            cliSuccess("Entra monitor enabled. It checks every 5 minutes; stage gaps and daily caps govern user prompts."); return true
        } catch { cliError("Entra monitor could not be installed."); return false }
    }
    static func uninstallSchedule() {
        guard getuid() == 0 else { cliError("Use sudo to pause the Entra monitor."); return }
        _ = runDirect("/bin/launchctl",["bootout","system/" + label])
        do { if FileManager.default.fileExists(atPath:plist) { try FileManager.default.removeItem(atPath:plist) }; RuntimeHealthScope.monitorIntent("entra",desired:"paused",reason:"Administrator paused registration monitoring"); cliPrint("Entra registration monitor paused.") }
        catch { cliError("Entra monitor definition could not be removed.") }
    }
}

func trustedEntraBinary(_ path: String) -> Bool {
    guard path.hasPrefix("/"), path.hasSuffix("/jamf"), URL(fileURLWithPath:path).standardizedFileURL.path == path else { return false }
    func protectedChain(_ start: URL, allowLinks: Bool) -> Bool {
        var url = start
        while url.path != "/" {
            var info = stat()
            guard lstat(url.path,&info) == 0, info.st_uid == 0 else { return false }
            if info.st_mode & S_IFMT == S_IFLNK {
                guard allowLinks else { return false }
            } else if info.st_mode & 0o022 != 0 { return false }
            url.deleteLastPathComponent()
        }
        return true
    }
    let original = URL(fileURLWithPath:path), canonical = URL(fileURLWithPath:path).resolvingSymlinksInPath()
    return protectedChain(original,allowLinks:true) && protectedChain(canonical,allowLinks:false) && FileManager.default.isExecutableFile(atPath:canonical.path)
}
func validEntraApp(_ path: String, bundleID: String) -> Bool {
    guard path.hasPrefix("/Applications/"), URL(fileURLWithPath:path).standardizedFileURL.path == path,
          Bundle(path:path)?.bundleIdentifier == bundleID else { return false }
    return runDirect("/usr/bin/codesign",["--verify","--strict",path]).1 == 0
}
