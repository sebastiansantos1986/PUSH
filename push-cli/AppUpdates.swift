// PUSH — Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import Darwin

struct ManagedAppRecord: Codable {
    var installed = ""
    var target = ""
    var firstSeen: Date?
    var deadline: Date?
    var retryAfter: Date?
    var checked: Date?
    var result = "Not checked"
}
struct ManagedAppsState: Codable {
    var apps: [String:ManagedAppRecord] = [:]
    var nextToast: Date = .distantPast
}
private enum AppUpdateError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
struct AppInventory {
    let version: String
    let running: Bool
}

func approvedAppInventory(_ app: ApprovedApp) throws -> AppInventory? {
    let url = URL(fileURLWithPath:"/Applications/" + app.filename)
    guard FileManager.default.fileExists(atPath:url.path) else { return nil }
    let info = try url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
    guard info.isDirectory == true, info.isSymbolicLink != true else { throw AppUpdateError.message("Unsupported app location or link.") }
    if FileManager.default.fileExists(atPath:url.appendingPathComponent("Contents/_MASReceipt/receipt").path) {
        throw AppUpdateError.message("App Store copy — leave updates to its existing management channel.")
    }
    let plist = try PropertyListSerialization.propertyList(from:Data(contentsOf:url.appendingPathComponent("Contents/Info.plist")),format:nil) as? [String:Any]
    guard plist?["CFBundleIdentifier"] as? String == app.bundleID,
          let version = plist?["CFBundleShortVersionString"] as? String, AppUpdatePolicy.version(version) != nil else {
        throw AppUpdateError.message("Unexpected bundle identity or version.")
    }
    if app.id == "firefox" {
        guard let channel = try? String(contentsOf:url.appendingPathComponent("Contents/Resources/defaults/pref/channel-prefs.js"),encoding:.utf8), AppUpdatePolicy.firefoxReleaseChannel(channel) else {
            throw AppUpdateError.message("Only the verified Firefox release channel is supported; ESR/custom channels are excluded.")
        }
    }
    let (_, valid) = runDirect("/usr/bin/codesign",["--verify","--strict",url.path])
    let (signature, status) = runDirect("/usr/bin/codesign",["-dv","--verbose=4",url.path])
    guard valid == 0, status == 0, signature.components(separatedBy:"\n").contains("TeamIdentifier=" + app.teamID) else {
        throw AppUpdateError.message("Installed publisher verification failed.")
    }
    let (_, running) = runDirect("/usr/bin/pgrep",["-x",app.process])
    guard running == 0 || running == 1 else { throw AppUpdateError.message("Cannot determine whether the app is running.") }
    return AppInventory(version:version,running:running == 0)
}

/// Executing an update provider as root requires an administrator-owned, non-writable chain.
func trustedAppProvider(_ path: String) -> Bool {
    guard path.hasPrefix("/"), path.hasSuffix("/Installomator.sh") else { return false }
    var url = URL(fileURLWithPath:path)
    while url.path != "/" {
        var info = stat()
        guard lstat(url.path,&info) == 0, (info.st_mode & S_IFMT) != S_IFLNK,
              info.st_uid == 0, info.st_mode & 0o022 == 0 else { return false }
        url.deleteLastPathComponent()
    }
    return FileManager.default.isReadableFile(atPath:path)
}

private final class AppFeedResult {
    let lock = NSLock()
    var value: Result<Data,Error>?
}
func readAppVersionFeed(_ app: ApprovedApp) throws -> String {
    let response = AppFeedResult(), done = DispatchSemaphore(value:0)
    let session = URLSession(configuration:.ephemeral)
    defer { session.invalidateAndCancel() }
    var request = URLRequest(url:URL(string:app.feed)!,timeoutInterval:20)
    request.setValue("PUSH-App-Discovery/1.4",forHTTPHeaderField:"User-Agent")
    let task = session.downloadTask(with:request) { url, reply, error in
        defer { if let url { try? FileManager.default.removeItem(at:url) }; done.signal() }
        let result: Result<Data,Error> = Result {
            if let error { throw error }
            guard let url, let http = reply as? HTTPURLResponse, http.statusCode == 200,
                  http.url?.scheme == "https", let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize,
                  size <= 1_048_576 else { throw AppUpdateError.message("Invalid or oversized vendor version response.") }
            return try Data(contentsOf:url)
        }
        response.lock.lock(); response.value = result; response.lock.unlock()
    }
    task.resume()
    guard done.wait(timeout:.now()+22) == .success else { task.cancel(); throw AppUpdateError.message("Vendor version check timed out.") }
    response.lock.lock(); let result = response.value; response.lock.unlock()
    guard let result else { throw AppUpdateError.message("No vendor version response.") }
    return try AppUpdatePolicy.latest(appID:app.id,data:result.get())
}

struct AppUpdatesCommand {
    let args: [String]
    private var file: String { managedBase + "/apps-state.json" }
    private func load() throws -> ManagedAppsState {
        guard FileManager.default.fileExists(atPath:file) else { return .init() }
        return try JSONDecoder().decode(ManagedAppsState.self,from:Data(contentsOf:URL(fileURLWithPath:file)))
    }
    private func save(_ state: ManagedAppsState) throws {
        try JSONEncoder().encode(state).write(to:URL(fileURLWithPath:file),options:.atomic)
    }
    func run() {
        let action = args.first ?? "status"
        if action == "preview" { PopupCommand(args:["appUpdates"]).run(); return }
        guard ["status","check","notify","update","scheduled"].contains(action) else {
            cliError("Usage: push-cli apps status|check|notify|preview|update <chrome|firefox|vscode|all> [--dry-run] [--force]"); return
        }
        guard let config = try? loadConfig() else { cliError("Cannot load app update policy."); return }
        if action == "status" {
            cliSection("Approved application updates")
            cliInfo("Enabled:",String(config.apps.enabled))
            cliInfo("Approved:",config.apps.approved.isEmpty ? "None" : config.apps.approved)
            cliInfo("Closed-app updates:",String(config.apps.autoUpdateClosed))
            cliInfo("Installomator:",trustedAppProvider(config.apps.installomatorPath) ? "Ready" : "Missing or not administrator-owned")
            do {
                let state = try load()
                for app in ApprovedApp.catalog where AppUpdatePolicy.ids(config.apps.approved).contains(app.id) {
                    let record = state.apps[app.id]
                    cliInfo(app.name + ":",record.map { "\($0.installed) → \($0.target): \($0.result)" } ?? "Not checked")
                }
            } catch { cliError("App state is unreadable; restore its backup before updating.") }
            return
        }
        if action == "scheduled" && !config.apps.enabled { return }
        if args.contains("--dry-run") || config.debug.dryRun {
            cliPrint("Dry run: would evaluate approved app updates. No vendor query, popup, download, or installation."); return
        }
        guard getuid() == 0 else { cliError("Use sudo for app discovery and update actions."); return }
        let audit = RuntimeHealthScope(module:"apps",scheduled:action == "scheduled" && args.contains("--from-daemon"))
        defer { audit.finish() }
        let selected = AppUpdatePolicy.ids(config.apps.approved)
        guard !selected.isEmpty, selected.allSatisfy({ id in ApprovedApp.catalog.contains { $0.id == id } }) else {
            cliPrint("Choose approved apps in PUSH Admin before checking or updating."); return
        }
        guard (1...365).contains(config.apps.graceDays), selected.allSatisfy({ id in
            let value = config.apps.deadlineOverride(for:id)
            return value.isEmpty || ISO8601DateFormatter().date(from:value) != nil
        }) else { cliError("App grace days or deadline override is invalid."); return }
        guard action == "check" || config.apps.enabled else { cliPrint("App management is paused. Enable apps.enabled before update or notification actions."); return }
        if action == "update" {
            guard let target = args.dropFirst().first, target == "all" || selected.contains(target) else {
                cliError("Specify an approved app ID or all. Unapproved apps cannot be updated."); return
            }
        }
        guard installationIsActive() == false else { cliPrint("An installer is active; app work will retry later."); return }
        guard let osState = try? loadStateForAction(), !osState.installStarted else { cliPrint("macOS installation is pending or state is unreadable; app work deferred."); return }
        try? FileManager.default.createDirectory(atPath:managedBase,withIntermediateDirectories:true)
        let lock = open(managedBase + "/apps.lock",O_CREAT|O_RDWR|O_NOFOLLOW,0o600)
        guard lock >= 0 else { cliError("Cannot prepare app update lock."); return }
        defer { close(lock) }
        guard flock(lock,LOCK_EX|LOCK_NB) == 0 else { cliPrint("Another app check is running."); return }
        defer { flock(lock,LOCK_UN) }
        do {
            var state = try load()
            var pending: [ApprovedApp] = []
            for app in ApprovedApp.catalog where selected.contains(app.id) {
                var record = state.apps[app.id] ?? .init()
                record.checked = Date()
                do {
                    guard let installed = try approvedAppInventory(app) else {
                        record.result = "Not installed — skipped"; record.installed = ""; state.apps[app.id] = record; cliInfo(app.name + ":",record.result); continue
                    }
                    record.installed = installed.version
                    let latest = try readAppVersionFeed(app)
                    if !AppUpdatePolicy.same(record.target,latest) { record.firstSeen = Date() }
                    record.target = latest
                    record.deadline = AppUpdatePolicy.deadline(override:config.apps.deadlineOverride(for:app.id),firstSeen:record.firstSeen ?? Date(),days:config.apps.graceDays)
                    if AppUpdatePolicy.newer(latest,than:installed.version) {
                        record.result = installed.running ? "Update available — close app when ready" : "Update available — app is closed"
                        pending.append(app)
                    } else { record.result = "Up to date or newer than stable" }
                } catch { record.result = "Skipped: " + error.localizedDescription }
                state.apps[app.id] = record
                cliInfo(app.name + ":",record.result)
            }
            try save(state)
            if action == "check" { cliPrint("App check complete. No Installomator command, popup, or app download was run."); return }
            let withinHours = AutoCheckCommand(args:[]).isWithinAlertWindow(config:config)
            let force = args.contains("--force") || action != "scheduled"
            guard force || withinHours else { cliPrint("App discovery saved; waiting for working hours."); return }
            if !force && config.schedule.skipDuringMeetings && AutoCheckCommand(args:[]).isUserInMeeting() { RuntimeHealthScope.note("Meeting or screen sharing detected; app reminders are waiting"); return }
            if action == "update" {
                let target = args.dropFirst().first!
                update(pending.filter { target == "all" || $0.id == target }, config:config, state:&state)
            } else if action == "scheduled" && config.apps.autoUpdateClosed {
                update(pending,config:config,state:&state,automatically:true)
            }
            if action == "notify" || (action == "scheduled" && config.apps.notifyHourly && AppUpdatePolicy.toastDue(state.nextToast)) {
                let remaining = pending.filter { app in
                    guard let record = state.apps[app.id] else { return false }
                    return AppUpdatePolicy.newer(record.target,than:record.installed) && !record.result.hasPrefix("Updated")
                }
                if !remaining.isEmpty && userIsLoggedIn() {
                    let notices = remaining.compactMap { app -> AppUpdateNotice? in
                        guard let record = state.apps[app.id] else { return nil }
                        return .init(id:app.id,name:app.name,installed:record.installed,target:record.target,deadline:record.deadline.map { ISO8601DateFormatter().string(from:$0) } ?? "")
                    }
                    let payload = try JSONEncoder().encode(notices).base64EncodedString()
                    state.nextToast = Date().addingTimeInterval(3600)
                    try save(state)
                    let command = shellArgument(resolveUIBinary()) + " --state appUpdates --config " + shellArgument(resolvedConfigPath ?? "") + " --apps-payload " + shellArgument(payload)
                    let response = runUIBlocking(command)
                    if response == 0 { update(remaining,config:config,state:&state) }
                    else { cliPrint(response == 1 ? "App updates deferred; next toast in one hour." : "App notification closed without starting an update.") }
                }
            }
            let unresolved = state.apps.values.filter { AppUpdatePolicy.newer($0.target,than:$0.installed) && !$0.installed.isEmpty }
            if unresolved.isEmpty { RuntimeHealthScope.note("Approved app checks finished; no pending updates in saved results") }
            else if action == "scheduled", config.apps.notifyHourly, state.nextToast > Date() { RuntimeHealthScope.note("Waiting for the next hourly app reminder") }
            else if action == "scheduled", !config.apps.notifyHourly { RuntimeHealthScope.note("Hourly app reminders are disabled; pending updates require an explicit request or closed-app update policy") }
            try save(state)
        } catch { cliError("App state could not be read or saved: " + error.localizedDescription) }
    }
    private func update(_ apps: [ApprovedApp], config: CLIConfig, state: inout ManagedAppsState, automatically: Bool = false) {
        guard !apps.isEmpty else { cliPrint("No approved installed apps need an update."); return }
        guard installationIsActive() == false, let os = try? loadStateForAction(), !os.installStarted else { cliPrint("Installation activity changed; app updates deferred."); return }
        guard trustedAppProvider(config.apps.installomatorPath) else { cliError("Install a stable, administrator-owned Installomator release first. Nothing was updated."); return }
        let lock = open(managedBase + "/install.lock",O_CREAT|O_RDWR|O_NOFOLLOW,0o600)
        guard lock >= 0 else { cliError("Cannot prepare installation lock."); return }
        defer { close(lock) }
        guard flock(lock,LOCK_EX|LOCK_NB) == 0 else { cliPrint("Another installation owns the update lock."); return }
        defer { flock(lock,LOCK_UN) }
        guard let lockedState = try? loadStateForAction(), !lockedState.installStarted else { cliPrint("macOS staging changed; app updates deferred."); return }
        for app in apps {
            do {
                guard let installed = try approvedAppInventory(app), var record = state.apps[app.id], AppUpdatePolicy.newer(record.target,than:installed.version) else { continue }
                guard !installed.running else { record.result = "Deferred — app is open; save work and close it"; state.apps[app.id] = record; continue }
                guard let live = try? loadConfig(), !live.debug.dryRun,
                      AppUpdatePolicy.shouldInstall(id:app.id,approved:live.apps.approved,enabled:live.apps.enabled,installed:installed.version,target:record.target,running:installed.running),
                      !automatically || (live.apps.autoUpdateClosed && (record.retryAfter ?? .distantPast) <= Date()) else {
                    record.result = "Deferred — live policy changed or retry delay is active"; state.apps[app.id] = record; continue
                }
                // Recheck the provider chain immediately before root execution; no arbitrary labels or variables.
                guard trustedAppProvider(live.apps.installomatorPath) else { throw AppUpdateError.message("Update provider trust changed.") }
                RuntimeHealthScope.phase("updating","Updating approved closed app: " + app.name)
                _ = try discoveryOutput("/bin/zsh",["--no-rcs",live.apps.installomatorPath]+AppUpdatePolicy.installArguments(app),timeout:1800)
                guard let after = try approvedAppInventory(app), !AppUpdatePolicy.newer(record.target,than:after.version), !AppUpdatePolicy.newer(installed.version,than:after.version) else {
                    throw AppUpdateError.message("Installed version could not be verified after the update.")
                }
                record.installed = after.version; record.retryAfter = nil; record.result = "Updated and publisher verified"
                state.apps[app.id] = record
                cliSuccess(app.name + " updated to " + after.version)
            } catch {
                state.apps[app.id]?.retryAfter = Date().addingTimeInterval(3600)
                state.apps[app.id]?.result = "Update failed or incomplete: " + error.localizedDescription
                cliError(app.name + ": " + error.localizedDescription)
            }
            try? save(state)
        }
    }
}
