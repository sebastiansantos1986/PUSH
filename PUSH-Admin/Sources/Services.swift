// PUSH Admin — Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import AppKit
import Combine
import Darwin
import UniformTypeIdentifiers

struct CatalogRelease: Identifiable, Equatable {
    let version: String, name: String, build: String, date: String
    var id: String { version + "-" + build }
    static func parse(_ data: Data) throws -> [CatalogRelease] {
        let json = try JSONSerialization.jsonObject(with:data)
        let objects: [[String:Any]]
        if let array = json as? [[String:Any]] { objects = array }
        else if let dict = json as? [String:Any], let array = (dict["installers"] ?? dict["Installers"] ?? dict["items"]) as? [[String:Any]] { objects = array }
        else { throw AdminError.message("Mist returned an unrecognized catalog format. Update mist-cli and try again.") }
        var releases: [CatalogRelease] = []
        for item in objects {
            let dict = Dictionary(item.map { ($0.key.lowercased(),$0.value) },uniquingKeysWith: {a,_ in a})
            func text(_ key: String) -> String { dict[key].map { String(describing:$0) } ?? "" }
            let version = text("version"), name = text("name")
            guard versionParts(version) != nil else { continue }
            let betaFlags = [text("beta"),text("isbeta")].map { $0.lowercased() }
            guard !name.lowercased().contains("beta"), !name.lowercased().contains("developer preview"), !betaFlags.contains(where:{ ["true","1","yes"].contains($0) }) else { continue }
            if let compatible = dict["compatible"], ["false","no","0"].contains(String(describing:compatible).lowercased()) { continue }
            releases.append(.init(version:version,name:name.isEmpty ? "macOS" : name,build:text("build"),date:text("date")))
        }
        return Array(Set(releases.map(\.id))).compactMap { id in releases.first { $0.id == id } }.sorted {
            let lhs = versionParts($0.version)!, rhs = versionParts($1.version)!
            return lhs == rhs ? $0.build.localizedStandardCompare($1.build) == .orderedDescending : lhs.lexicographicallyPrecedes(rhs) == false
        }
    }
}
enum AdminError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// Only used for mist list/export. Runs on a background worker, with a timeout,
/// fixed argument arrays, bounded output, and no installation capability.
func readMistCatalog(at binary: String) throws -> [CatalogRelease] {
    let fm = FileManager.default
    let directory = fm.temporaryDirectory.appendingPathComponent("push-admin-catalog-" + UUID().uuidString)
    try fm.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer { try? fm.removeItem(at:directory) }
    let export = directory.appendingPathComponent("catalog.json"), log = directory.appendingPathComponent("output.txt")
    guard fm.createFile(atPath:log.path,contents:nil,attributes:[.posixPermissions:0o600]), let output = FileHandle(forWritingAtPath:log.path) else { throw AdminError.message("Could not prepare the catalog check.") }
    defer { try? output.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath:binary)
    process.arguments = ["list","installer","--compatible","--export",export.path]
    process.standardInput = FileHandle.nullDevice; process.standardOutput = output; process.standardError = output
    try process.run()
    let deadline = Date().addingTimeInterval(180)
    while process.isRunning {
        if Date() >= deadline { process.terminate(); kill(process.processIdentifier, SIGKILL); process.waitUntilExit(); throw AdminError.message("The catalog check timed out. Check your connection, then refresh.") }
        if let size = (try? fm.attributesOfItem(atPath:log.path)[.size]) as? NSNumber, size.intValue > 8_388_608 { process.terminate(); kill(process.processIdentifier, SIGKILL); process.waitUntilExit(); throw AdminError.message("Mist produced too much output. Update mist-cli and try again.") }
        Thread.sleep(forTimeInterval:0.1)
    }
    process.waitUntilExit()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
        throw AdminError.message("Mist could not list the catalog (exit \(process.terminationStatus)). Check network access and your installed mist-cli version.")
    }
    let data = try Data(contentsOf:export)
    guard data.count < 16_777_216 else { throw AdminError.message("The catalog export is unexpectedly large.") }
    let releases = try CatalogRelease.parse(data)
    guard !releases.isEmpty else { throw AdminError.message("No stable compatible installers were found. Your current macOS may be newer than the public catalog.") }
    return releases
}
func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of:"'",with:"'\\''") + "'" }
func appleScriptQuote(_ value: String) -> String { "\"" + value.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"").replacingOccurrences(of:"\n",with:"\\n") + "\"" }

@MainActor
final class AdminStore: ObservableObject {
    @Published var readiness: ReadinessSnapshot?
    @Published var isRefreshingReadiness = false
    func refreshReadiness() async {
        guard !isRefreshingReadiness else { return }
        isRefreshingReadiness = true
        let snapshot = await Task.detached(priority: .utility) { ReadinessReader().load() }.value
        readiness = snapshot
        isRefreshingReadiness = false
    }

    @Published var document = ConfigDocument.fresh { didSet { saveDraft() } }
    @Published var groupID = "identity"
    @Published var releases: [CatalogRelease] = []
    @Published var isRefreshing = false
    @Published var catalogMessage = "Waiting to check the macOS catalog."
    @Published var lastChecked: Date?
    @Published var catalogIsCached = false
    @Published var notice = ""
    @Published var busy = false
    @Published var buttonChecks: [PopupButtonCheck] = []
    func recordButtonCheck(state:String, action:String, code:Int32?, automatic:Bool) {
        buttonChecks.insert(PopupButtonCheck(state:state,action:action,exitCode:code,automatic:automatic),at:0)
        if buttonChecks.count > 100 { buttonChecks.removeLast(buttonChecks.count-100) }
    }
    @Published var importedLiveConfig = false
    @Published var inspectionComplete = false
    @Published var expandedYAML = false
    let livePath = "/Library/Management/PUSH/config.yaml"
    let installedUI = "/Library/Management/PUSH/push-ui.app"
    var mistPath: String? { ["/usr/local/bin/mist","/opt/homebrew/bin/mist"].first { FileManager.default.isExecutableFile(atPath:$0) } }
    var pushInstalled: Bool { FileManager.default.isExecutableFile(atPath:"/Library/Management/PUSH/push-cli") }
    var pushVersion: String { Bundle(path:installedUI)?.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "Not installed" }
    var schedulePresent: Bool { FileManager.default.fileExists(atPath:"/Library/LaunchDaemons/com.push.autoupdate.plist") }
    var runningOS: String { ProcessInfo.processInfo.operatingSystemVersionString }
    var draftURL: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("PUSH Admin/draft.json")
    }
    private func saveDraft() {
        do {
            try FileManager.default.createDirectory(at:draftURL.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try JSONEncoder().encode(document).write(to:draftURL,options:.atomic)
            try persistPreviewLogo()
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:draftURL.path)
        } catch { notice = "Your draft could not be saved automatically. Export it before closing the app." }
    }
    func newDraft() {
        let alert = NSAlert(); alert.messageText = "Start a new configuration draft?"
        alert.informativeText = "Export the current draft first if you want to keep a separate copy. Installed PUSH settings will not change."
        alert.addButton(withTitle:"New Draft"); alert.addButton(withTitle:"Cancel")
        if alert.runModal() == .alertFirstButtonReturn { document = .fresh; importedLiveConfig = false; notice = "Started a new dry-run draft." }
    }
    var cacheURL: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("PUSH Admin/catalog-cache.json")
    }
    func startup() async {
        guard !inspectionComplete else { return }; inspectionComplete = true
        if let attributes = try? FileManager.default.attributesOfItem(atPath:draftURL.path),
           (attributes[.size] as? NSNumber)?.intValue ?? 0 < 6_291_456,
           let data = try? Data(contentsOf:draftURL), let restored = try? JSONDecoder().decode(ConfigDocument.self,from:data) {
            document = restored
        }
        if let data = try? Data(contentsOf:cacheURL), let cache = try? JSONSerialization.jsonObject(with:data) as? [String:Any], let time = cache["checkedAt"] as? Double,
           let records = cache["releases"], let recordsData = try? JSONSerialization.data(withJSONObject:records), let saved = try? CatalogRelease.parse(recordsData) {
            releases = saved; lastChecked = Date(timeIntervalSince1970:time); catalogIsCached = true
        }
        // The initial document is a safe draft. Existing live settings are imported
        // only when an administrator chooses Import installed config.
        await refreshCatalog()
    }
    func refreshCatalog() async {
        guard !isRefreshing else { return }
        guard let binary = mistPath else { catalogMessage = "mist-cli is not installed. Install it from its official releases, then refresh."; return }
        isRefreshing = true; catalogMessage = "Checking Apple’s installer catalog through Mist…"
        defer { isRefreshing = false }
        do {
            let result = try await Task.detached(priority:.utility) { try readMistCatalog(at:binary) }.value
            releases = result; lastChecked = Date(); catalogIsCached = false
            catalogMessage = "Stable installers compatible with this Mac. No download was started."
            let items = result.map { ["version":$0.version,"name":$0.name,"build":$0.build,"date":$0.date] }
            let data = try JSONSerialization.data(withJSONObject:["checkedAt":lastChecked!.timeIntervalSince1970,"releases":items])
            try FileManager.default.createDirectory(at:cacheURL.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try data.write(to:cacheURL,options:.atomic)
        } catch { catalogMessage = error.localizedDescription; catalogIsCached = !releases.isEmpty }
    }
    func selectRelease(_ release: CatalogRelease) {
        document.edits["update.targetVersion"] = release.version
        document.edits["update.macOSName"] = release.name
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        document.edits["update.releaseType"] = (versionParts(release.version)?.first ?? major) > major ? "major" : "minor"
        notice = "Selected macOS \(release.version) for this draft. The installed policy is unchanged."
    }
    func importDocument(_ url: URL) {
        do {
            let values = try url.resourceValues(forKeys:[.fileSizeKey]); guard (values.fileSize ?? 0) < 2_097_152 else { throw AdminError.message("Choose a YAML file smaller than 2 MB.") }
            let text = try String(contentsOf:url,encoding:.utf8)
            document = ConfigDocument.load(text,name:url.lastPathComponent)
            importedLiveConfig = url.path == livePath
            notice = document.omittedCredentials > 0 ? "Imported settings. \(document.omittedCredentials) plaintext credential fields were omitted. The original file was not changed." : "Imported settings into a draft. The original file was not changed."
        } catch { notice = "Import failed: " + error.localizedDescription }
    }
    func chooseImport() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension:"yaml")!,UTType(filenameExtension:"yml")!]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { importDocument(url) }
    }
    func exportDocument() {
        guard document.problems.isEmpty else { notice = "Resolve the validation issues before exporting."; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "config.yaml"; panel.allowedContentTypes = [UTType(filenameExtension:"yaml")!]
        let attachedLogo = document.logoImageData != nil && document.value("ui.logoPath") == deployedPopupLogoPath
        if attachedLogo { panel.message = "This exports your YAML and popup-logo.png together. Deploy the image to " + deployedPopupLogoPath }
        if panel.runModal() == .OK, let url = panel.url {
            do {
                if attachedLogo, let data = document.logoImageData {
                    let image = url.deletingLastPathComponent().appendingPathComponent("popup-logo.png")
                    if FileManager.default.fileExists(atPath:image.path), (try? Data(contentsOf:image)) != data {
                        let replace = NSAlert(); replace.messageText = "Replace popup-logo.png in this folder?"
                        replace.informativeText = "The YAML will reference this image on managed Macs."
                        replace.addButton(withTitle:"Replace Image"); replace.addButton(withTitle:"Cancel")
                        guard replace.runModal() == .alertFirstButtonReturn else { return }
                    }
                    try data.write(to:image,options:.atomic)
                }
                try document.yaml.write(to:url,atomically:true,encoding:.utf8)
                notice = attachedLogo ? "Saved YAML and popup-logo.png. Deploy the PNG to " + deployedPopupLogoPath : "Saved \(url.lastPathComponent). No settings were applied to this Mac."
            } catch { notice = "Save failed: " + error.localizedDescription }
        }
    }

    func confirmApply() {
        guard pushInstalled, document.problems.isEmpty else { notice = "Install PUSH and resolve configuration issues before applying."; return }
        let alert = NSAlert(); alert.messageText = "Apply this configuration to this Mac?"
        alert.informativeText = "The current config will be backed up. Future scheduled PUSH checks will use this policy. This does not start a check or an upgrade.\n\nDry run: \(document.value("debug.dryRun") ?? "true")\nAutomatic deadline install: \(document.value("update.autoInstallAfterDeadline") ?? "false")\nSilent deadline install: \(document.value("update.silentInstallAfterDeadline") ?? "false")\nDeadline override: \(document.value("update.deadline").flatMap { $0.isEmpty ? nil : $0 } ?? "Automatic from first detection")\nEntra reminders: \(document.value("entra.enabled") ?? "false")\nSelf Service policy: \(document.value("entra.policyID") ?? "876")\nApp management: \(document.value("apps.enabled") ?? "false")\nApproved apps: \(document.value("apps.approved") ?? "None")\nQuiet closed-app updates: \(document.value("apps.autoUpdateClosed") ?? "false")\nPlaintext credentials are excluded from this draft. A selected custom logo will also be installed and its previous image backed up."
        alert.addButton(withTitle:"Apply Configuration"); alert.addButton(withTitle:"Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("push-admin-apply-"+UUID().uuidString)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            defer { try? FileManager.default.removeItem(at:directory) }
            let staged = directory.appendingPathComponent("config.yaml")
            try document.yaml.write(to:staged,atomically:true,encoding:.utf8)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:staged.path)
            var imageInstall = ""
            if let data = document.logoImageData, document.value("ui.logoPath") == deployedPopupLogoPath {
                let stagedImage = directory.appendingPathComponent("popup-logo.png")
                try data.write(to:stagedImage,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:stagedImage.path)
                imageInstall = """
                /bin/mkdir -p "$base/assets"
                [ ! -L "$base/assets" ] && [ "$(/usr/bin/stat -f %u "$base/assets")" = 0 ] || exit 1
                /bin/chmod 755 "$base/assets"
                if [ -e "$base/assets/popup-logo.png" ]; then /bin/cp -p "$base/assets/popup-logo.png" "$base/config-backups/popup-logo-$(/bin/date -u +%Y%m%dT%H%M%SZ)-$$.png"; fi
                imagefile=$(/usr/bin/mktemp "$base/assets/.popup-logo.XXXXXX")
                /usr/bin/install -m 644 -o root -g wheel \(shellQuote(stagedImage.path)) "$imagefile"
                /bin/mv -f "$imagefile" "$base/assets/popup-logo.png"
                """
            }
            let command = """
            set -eu
            base=/Library/Management/PUSH
            [ -d "$base" ] && [ ! -L "$base" ] && [ "$(/usr/bin/stat -f %u "$base")" = 0 ] || exit 1
            [ -f \(shellQuote(staged.path)) ] && [ ! -L \(shellQuote(staged.path)) ] || exit 1
            /bin/mkdir -p "$base/config-backups"
            [ ! -L "$base/config-backups" ] && [ "$(/usr/bin/stat -f %u "$base/config-backups")" = 0 ] || exit 1
            /bin/chmod 700 "$base/config-backups"
            if [ -e "$base/config.yaml" ]; then /bin/cp -p "$base/config.yaml" "$base/config-backups/config-$(/bin/date -u +%Y%m%dT%H%M%SZ)-$$.yaml"; fi
            \(imageInstall)
            newfile=$(/usr/bin/mktemp "$base/.admin-config.XXXXXX")
            trap '/bin/rm -f "$newfile"' EXIT
            /usr/bin/install -m 644 -o root -g wheel \(shellQuote(staged.path)) "$newfile"
            /bin/mv -f "$newfile" "$base/config.yaml"
            """
            try authorize(command)
            notice = "Applied configuration. The previous YAML is in PUSH/config-backups. Scheduling was not changed."
        } catch { notice = "Configuration was not applied: " + error.localizedDescription }
    }
    func changeSchedule(enable: Bool) {
        guard pushInstalled else { notice = "Install PUSH first."; return }
        guard let version = versionParts(pushVersion), version.lexicographicallyPrecedes([1,5,0]) == false else { notice = "Scheduling from this companion requires PUSH 1.5.0 or later."; return }
        let installed: ConfigDocument
        do {
            installed = enable ? ConfigDocument.load(try String(contentsOfFile:livePath,encoding:.utf8),name:"installed") : ConfigDocument.fresh
            guard !enable || installed.problems.isEmpty else { notice = "Resolve the installed configuration issues before enabling checks."; return }
            guard !enable || installed.value("auto.enabled") == "true" || installed.value("apps.enabled") == "true" || installed.value("entra.enabled") == "true" else { notice = "Apply a policy with macOS, app, or Entra monitoring enabled first."; return }
        } catch { notice = error.localizedDescription; return }
        let dry = installed.value("debug.dryRun") == "true"
        let alert = NSAlert(); alert.messageText = enable ? "Enable PUSH monitoring?" : "Pause PUSH scheduling?"
        alert.informativeText = enable ? "This uses the INSTALLED configuration, not the draft. The first check runs immediately.\n\nMode: \(dry ? "Dry run — no update actions" : "LIVE — users can be prompted and macOS can be installed")\nAutomatic deadline install: \(installed.value("update.autoInstallAfterDeadline") ?? "false")\nSilent deadline install: \(installed.value("update.silentInstallAfterDeadline") ?? "false")\nEntra reminders: \(installed.value("entra.enabled") ?? "false") (5-minute checks, stage-limited prompts)\nApp management: \(installed.value("apps.enabled") ?? "false")\nQuiet closed-app updates: \(installed.value("apps.autoUpdateClosed") ?? "false")\nDeadline override: \(installed.value("update.deadline").flatMap { $0.isEmpty ? nil : $0 } ?? "Automatic from first detection")" : "The PUSH daemon will be stopped and removed. Its configuration is preserved."
        alert.addButton(withTitle:enable ? "Enable Schedule" : "Pause Schedule"); alert.addButton(withTitle:"Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try authorize("/Library/Management/PUSH/push-cli " + (enable ? "install-daemon --interval 1h" : "uninstall-daemon"))
            objectWillChange.send(); notice = enable ? (dry ? "Dry-run monitoring enabled." : "Live monitoring enabled using the installed policy.") : "Automatic scheduling paused."
        } catch { notice = error.localizedDescription }
    }
    private func authorize(_ command: String) throws {
        var error: NSDictionary?
        guard let script = NSAppleScript(source:"do shell script " + appleScriptQuote(command) + " with administrator privileges") else { throw AdminError.message("Could not prepare administrator authorization.") }
        _ = script.executeAndReturnError(&error)
        if let error { throw AdminError.message(error[NSAppleScript.errorMessage] as? String ?? "Administrator action was canceled or failed.") }
    }
}
