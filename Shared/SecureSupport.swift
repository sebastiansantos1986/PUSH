// PUSH - Proactive Update Scheduling Helper
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

import Foundation
import Security
import OpenDirectory

/// No shell, credential arguments, temporary password files, or output logging.
/// The callback receives output only; callers must redact secrets before logging.
func runDirect(_ executable: String, _ arguments: [String], input: String? = nil,
               onOutput: ((String) -> Void)? = nil) -> (String, Int32) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let output = Pipe(), stdin = Pipe()
    process.standardOutput = output
    process.standardError = output
    process.standardInput = stdin
    do {
        try process.run()
        // Installer passwords are small. Reject oversized input before calling this helper.
        if let input { try stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8)) }
        try stdin.fileHandleForWriting.close()
        var result = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            result.append(chunk)
            // Bound retained output while always draining the child to avoid deadlock.
            if result.count > 1_048_576 { result.removeFirst(result.count - 1_048_576) }
            onOutput?(String(decoding: chunk, as: UTF8.self))
        }
        process.waitUntilExit()
        return (String(decoding: result, as: UTF8.self), process.terminationStatus)
    } catch {
        try? stdin.fileHandleForWriting.close()
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        return ("", -1)
    }
}

func verifyLocalPassword(account: String, password: String) -> Bool {
    guard !account.isEmpty, !password.isEmpty else { return false }
    do {
        let node = try ODNode(session: ODSession.default(), type: UInt32(kODNodeTypeLocalNodes))
        let record = try node.record(withRecordType: kODRecordTypeUsers, name: account, attributes: nil)
        try record.verifyPassword(password)
        return true
    } catch { return false }
}

/// Security.framework keeps secret bytes out of process arguments and shell history.
/// Login entries are accessed by push-ui itself, preserving its keychain ACL.
// End-user password collection is disabled for this managed deployment.
let allowsUserPasswordPrompts = false

enum PushKeychain {
    static func query(service: String, account: String, system: Bool) -> [String: Any]? {
        // kSecUseAuthenticationUI alone does not suppress legacy file-keychain UI.
        // Disable legacy Keychain interaction process-wide before opening or querying.
        // Fail closed if the OS cannot apply the noninteractive policy.
        guard SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else { return nil }
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                               kSecAttrService as String: service, kSecAttrAccount as String: account]
        if system {
            var keychain: SecKeychain?
            guard SecKeychainOpen("/Library/Keychains/System.keychain", &keychain) == errSecSuccess,
                  let keychain else { return nil }
            q[kSecMatchSearchList as String] = [keychain]
        }
        return q
    }
    static func read(service: String, account: String, system: Bool = false) -> String? {
        guard var q = query(service: service, account: account, system: system) else { return nil }
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data, !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func exists(service: String, account: String, system: Bool = false) -> Bool {
        guard let q = query(service: service, account: account, system: system) else { return false }
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }
    static func save(service: String, account: String, password: String, system: Bool = false) -> Bool {
        guard !account.isEmpty, !password.isEmpty,
              var q = query(service: service, account: account, system: system) else { return false }
        var access: SecAccess?
        guard SecAccessCreate("PUSH credential" as CFString, nil, &access) == errSecSuccess,
              let access else { return false }
        let attributes: [String: Any] = [kSecValueData as String: Data(password.utf8), kSecAttrAccess as String: access]
        let status = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        if system, let keychains = q.removeValue(forKey: kSecMatchSearchList as String) as? [SecKeychain],
           let keychain = keychains.first { q[kSecUseKeychain as String] = keychain }
        q[kSecValueData as String] = Data(password.utf8)
        q[kSecAttrAccess as String] = access
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
    static func delete(service: String, account: String, system: Bool = false) -> Bool {
        guard let q = query(service: service, account: account, system: system) else { return false }
        let status = SecItemDelete(q as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

func numericOSVersion(_ text: String) -> [Int]? {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
    var values = parts.compactMap { Int($0) }
    guard values.count == parts.count else { return nil }
    while values.count < 3 { values.append(0) }
    return values
}
func sameOSVersion(_ lhs: String, _ rhs: String) -> Bool {
    guard let a = numericOSVersion(lhs), let b = numericOSVersion(rhs) else { return false }
    return a == b
}
func nativeUpdateLabel(version: String, output: String, restartOnly: Bool = false) -> String? {
    guard numericOSVersion(version) != nil else { return nil }
    var label: String?
    for line in output.components(separatedBy: .newlines) {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("* Label:") { label = String(t.dropFirst(8)).trimmingCharacters(in: .whitespaces) }
        else if let label, let range = t.range(of: "Version: ") {
            let v = String(t[range.upperBound...].prefix(while: { $0 != "," })).trimmingCharacters(in: .whitespaces)
            if sameOSVersion(v, version) && (!restartOnly || t.lowercased().contains("action: restart")) { return label }
        }
    }
    return nil
}

func shellArgument(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// Edits one scalar in the existing YAML without serializing unrelated settings.
/// Handles nested sections and removes continuation lines of a replaced scalar.
func updatingYAMLString(_ source: String, section: [String], field: String, value: String) -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
    let encoded = String(data:try! encoder.encode(value),encoding:.utf8)!
    return updatingYAMLScalar(source,section:section,field:field,encoded:encoded)
}

/// The encoded value must be a validated YAML scalar, never untrusted YAML syntax.
func updatingYAMLScalar(_ source: String, section: [String], field: String, encoded: String) -> String {
    var lines = source.components(separatedBy: "\n")
    var start = 0, end = lines.count, indent = -2
    for name in section {
        let match = (start..<end).first { index in
            let line = lines[index]
            let leading = line.prefix { $0 == " " }.count
            return leading == indent + 2 && line.trimmingCharacters(in:.whitespaces).components(separatedBy:"#")[0].trimmingCharacters(in:.whitespaces) == name + ":"
        }
        if let match {
            // Keep header comments on their own line so PUSH's block-YAML readers
            // and the companion can read the section after it is edited.
            if let hash = lines[match].firstIndex(of:"#") {
                let comment = String(lines[match][hash...])
                lines[match] = String(repeating:" ",count:indent+2) + name + ":"
                lines.insert(String(repeating:" ",count:indent+2) + comment,at:match+1)
                end += 1
            }
            indent += 2
            start = match + 1
            end = (start..<end).first { index in
                let text = lines[index].trimmingCharacters(in: .whitespaces)
                return !text.isEmpty && !text.hasPrefix("#") && lines[index].prefix { $0 == " " }.count <= indent
            } ?? end
        } else {
            let insertion = String(repeating: " ", count: indent + 2) + name + ":"
            lines.insert(insertion, at: end)
            start = end + 1
            end = start
            indent += 2
        }
    }
    let replacement = String(repeating: " ", count: indent + 2) + field + ": " + encoded
    var index = start
    var updated = false
    while index < end {
        let line = lines[index]
        if line.prefix(while: { $0 == " " }).count == indent + 2 && line.trimmingCharacters(in: .whitespaces).hasPrefix(field + ":") {
            var stop = index + 1
            while stop < end && lines[stop].prefix(while: { $0 == " " }).count > indent + 2 { stop += 1 }
            lines.replaceSubrange(index..<stop, with: updated ? [] : [replacement])
            end -= stop - index - (updated ? 0 : 1)
            if !updated { index += 1 }
            updated = true
        } else { index += 1 }
    }
    if !updated { lines.insert(replacement, at: end) }
    return lines.joined(separator: "\n")
}

/// Pure response mapping used only after a UI process has actually finished.
func popupResultMessage(state: String, exitCode: Int32) -> String {
    if exitCode < 0 { return "Popup crashed (signal \(-exitCode)); no user choice was recorded" }
    switch exitCode {
    case 0:
        if state == "entraRegistration" { return "User chose Register Now" }
        if state == "appUpdates" { return "User chose Update Closed Apps" }
        if ["rebootNudge", "rebootForce", "rebooting"].contains(state) { return "Restart requested" }
        if state == "preflightPower" { return "AC power detected" }
        return "User chose Install"
    case 1: return "User chose Later"
    case 2: return "User dismissed"
    case 3: return state == "toast" ? "Toast auto-dismissed" : "User scheduled a reminder"
    case 4: return "Power check timed out"
    case 5: return state == "toast" ? "Toast auto-dismissed" : "Popup failed (unexpected timeout response for \(state))"
    case 6: return state == "entraRegistration" ? "User chose Contact IT" : "Support contact opened"
    case 7: return state == "updateRecovery" ? "Recovery countdown elapsed; no user choice was recorded" : "Popup failed (unexpected automatic-retry response)"
    case 100: return "Popup timed out without a user response"
    case 101: return "No logged-in user is available for the popup"
    case 103: return "Popup could not display a window. No user choice was recorded. See push-cli log show for launch diagnostics."
    default: return "Popup failed (exit \(exitCode))"
    }
}
func toastRequestedInstall(exitCode: Int32) -> Bool { exitCode == 0 }

func supportContactURL(email: String, website: String) -> URL? {
    let address = email.trimmingCharacters(in:.whitespacesAndNewlines)
    if address.contains("@"), !address.contains("\n"), !address.contains("\r") {
        var components = URLComponents(); components.scheme = "mailto"; components.path = address
        components.queryItems = [URLQueryItem(name:"subject",value:"PUSH update support")]
        return components.url
    }
    if let url = URL(string:website), url.scheme == "https", url.host?.isEmpty == false { return url }
    return nil
}

func validReminderDate(_ chosen: Date, deadline: Date, now: Date = Date()) -> Bool {
    chosen > now && chosen <= deadline
}
func popupBackgroundOpacity(_ percent: Int, reduceTransparency: Bool = false) -> Double {
    reduceTransparency ? 1 : Double(min(100, max(55, percent))) / 100
}
func previewButtonTitle(state: String, code: Int32) -> String {
    switch code {
    case 0: return state == "entraRegistration" ? "Register Now" : state == "appUpdates" ? "Update Closed Apps" : ["rebootNudge", "rebootForce", "rebooting"].contains(state) ? "Restart Now" : (state == "preflightPower" ? "Power detected" : "Install Now")
    case 1: return "Later"
    case 2: return state == "compliant" ? "Done" : (state == "error" ? "Dismiss" : "Close / Skip")
    case 3: return "Schedule confirmed"
    case 4: return "Power wait timed out"
    case 5: return "Toast auto-dismissed"
    case 6: return "Contact IT"
    default: return "Response \(code)"
    }
}

/// A signal is never a button response, even when its number matches an exit code.
func popupProcessResult(status: Int32, reason: Process.TerminationReason) -> Int32 {
    if reason == .uncaughtSignal { return -abs(status) }
    // Shell/sudo may encode a child signal as 128 + signal.
    if (129...159).contains(status) { return -(status - 128) }
    return status
}

/// Exit codes are choices only after the UI reports a visible window.
func popupWindowResult(status: Int32, reason: Process.TerminationReason, visible: Bool) -> Int32 {
    visible ? popupProcessResult(status:status,reason:reason) : 103
}

func reminderPickerRange(now: Date, deadline: Date) -> ClosedRange<Date> {
    now...max(now, deadline)
}

/// A test-only sample window; the saved enforcement deadline is never modified.
func reminderTestDeadline(configured: Date?, manualTest: Bool, now: Date = Date()) -> Date {
    guard let configured else { return now.addingTimeInterval(7 * 86400) }
    return manualTest && configured <= now ? now.addingTimeInterval(7 * 86400) : configured
}

// MARK: - Approved application updates
// Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
struct ApprovedApp: Identifiable {
    let id: String, name: String, bundleID: String, filename: String, process: String
    let label: String, teamID: String, feed: String
    static let catalog: [ApprovedApp] = [
        .init(id:"chrome", name:"Google Chrome", bundleID:"com.google.Chrome", filename:"Google Chrome.app", process:"Google Chrome", label:"googlechromepkg", teamID:"EQHXZ8M8AV", feed:"https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/stable/versions/all/releases?filter=fraction%3E0.01,endtime=none&order_by=version%20desc"),
        .init(id:"firefox", name:"Firefox", bundleID:"org.mozilla.firefox", filename:"Firefox.app", process:"firefox", label:"firefoxpkg_intl", teamID:"43AQ936H96", feed:"https://product-details.mozilla.org/1.0/firefox_versions.json"),
        .init(id:"vscode", name:"Visual Studio Code", bundleID:"com.microsoft.VSCode", filename:"Visual Studio Code.app", process:"Code", label:"visualstudiocode", teamID:"UBF8T346G9", feed:"https://update.code.visualstudio.com/api/releases/stable")
    ]
}
enum AppUpdatePolicy {
    static func ids(_ text: String) -> [String] {
        Array(Set(text.split(separator:",").map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }
    static func version(_ text: String) -> [Int]? {
        let pieces = text.split(separator:".", omittingEmptySubsequences:false)
        guard (1...6).contains(pieces.count), pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        let values = pieces.compactMap { Int($0) }
        return values.count == pieces.count ? values : nil
    }
    static func newer(_ candidate: String, than installed: String) -> Bool {
        guard let a = version(candidate), let b = version(installed) else { return false }
        for i in 0..<max(a.count,b.count) {
            let left = i < a.count ? a[i] : 0, right = i < b.count ? b[i] : 0
            if left != right { return left > right }
        }
        return false
    }
    static func latest(appID: String, data: Data) throws -> String {
        let json = try JSONSerialization.jsonObject(with:data)
        let result: String?
        switch appID {
        case "chrome": result = ((json as? [String:Any])?["releases"] as? [[String:Any]])?.first?["version"] as? String
        case "firefox": result = (json as? [String:Any])?["LATEST_FIREFOX_VERSION"] as? String
        case "vscode": result = (json as? [String])?.first
        default: result = nil
        }
        guard let value = result, version(value) != nil else { throw NSError(domain:"PUSH.Apps",code:1,userInfo:[NSLocalizedDescriptionKey:"Unrecognized stable app version feed."]) }
        return value
    }
    static func same(_ a: String, _ b: String) -> Bool {
        version(a) != nil && version(b) != nil && !newer(a,than:b) && !newer(b,than:a)
    }
    static func deadline(override: String, firstSeen: Date, days: Int) -> Date? {
        if !override.isEmpty { return ISO8601DateFormatter().date(from:override) }
        return firstSeen.addingTimeInterval(Double(max(1,min(365,days))) * 86400)
    }
    static func firefoxReleaseChannel(_ source: String) -> Bool {
        let pattern = #"(?m)^\s*(?:pref|user_pref)\(\s*["']app\.update\.channel["']\s*,\s*["']([^"']+)["']\s*\)"#
        guard let regex = try? NSRegularExpression(pattern:pattern) else { return false }
        let channels = regex.matches(in:source,range:NSRange(source.startIndex...,in:source)).compactMap { match -> String? in
            guard let range = Range(match.range(at:1),in:source) else { return nil }
            return String(source[range])
        }
        return channels == ["release"]
    }
    static func shouldInstall(id: String, approved: String, enabled: Bool, installed: String, target: String, running: Bool) -> Bool {
        enabled && ids(approved).contains(id) && ApprovedApp.catalog.contains(where: { $0.id == id }) && !running && newer(target,than:installed)
    }
    static func toastDue(_ next: Date, now: Date = Date()) -> Bool {
        // Allow small catalog-duration differences when the daemon itself polls hourly.
        next.timeIntervalSince(now) <= 60
    }
    static func installArguments(_ app: ApprovedApp) -> [String] {
        // INSTALL=force selects the package path instead of vendor updater tools.
        // PUSH has already required a newer target; blocking processes still cause a safe exit.
        [app.label, "DEBUG=0", "NOTIFY=silent", "BLOCKING_PROCESS_ACTION=silent_fail", "REOPEN=no", "SYSTEMOWNER=1", "IGNORE_APP_STORE_APPS=no", "INSTALL=force"]
    }
}
struct AppUpdateNotice: Codable, Identifiable {
    var id: String
    var name: String
    var installed: String
    var target: String
    var deadline: String
    static let examples: [AppUpdateNotice] = [
        .init(id:"chrome",name:"Google Chrome",installed:"140.0.1.1",target:"140.0.2.1",deadline:"Preview"),
        .init(id:"firefox",name:"Firefox",installed:"143.0",target:"143.0.1",deadline:"Preview"),
        .init(id:"vscode",name:"Visual Studio Code",installed:"1.104.0",target:"1.105.0",deadline:"Preview")
    ]
    static func decodePayload(_ value: String) -> [AppUpdateNotice]? {
        guard value.utf8.count <= 8192, let data = Data(base64Encoded:value),
              let result = try? JSONDecoder().decode([AppUpdateNotice].self,from:data), !result.isEmpty, result.count <= 3,
              result.allSatisfy({ ApprovedApp.catalog.map(\.id).contains($0.id) && $0.name.count <= 80 && AppUpdatePolicy.version($0.installed) != nil && AppUpdatePolicy.version($0.target) != nil && $0.deadline.count <= 80 }) else { return nil }
        return result
    }
}

// MARK: - Entra registration nudge policy
// Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
// Local evidence guides reminders; it is never an access-control or cloud compliance verdict.
enum EntraRegistrationStatus: String, Codable {
    case localRegistered, needsRegistration, verificationUnavailable, setupMissing, notApplicable
    var title: String {
        switch self {
        case .localRegistered: return "Registration detected locally"
        case .needsRegistration: return "Registration needed"
        case .verificationUnavailable: return "Unable to verify registration"
        case .setupMissing: return "IT setup required"
        case .notApplicable: return "Not applicable"
        }
    }
}
struct EntraEvidence {
    let status: EntraRegistrationStatus
    let reason: String
}
struct EntraUserState: Codable {
    var userName = ""
    var status: EntraRegistrationStatus = .verificationUnavailable
    var reason = "Not checked"
    var checkedAt: Date?
    var lastRegistered: Bool?
    var laterCount = 0
    var closedCount = 0
    var timedOutCount = 0
    var registerClicks = 0
    var openedCount = 0
    var promptsToday = 0
    var dayKey = ""
    var lastPromptAt: Date?
    var firstPromptAt: Date?
    var needsRecon = false
    var nextReconAt: Date?
    var lastReconAt: Date?
    var awaitingRegistration = false
    var nextReason = "Not checked"
}
struct EntraNudgeState: Codable { var users: [String:EntraUserState] = [:] }
struct EntraStage {
    let number: Int, cap: Int
    let gap: TimeInterval
}
enum EntraPolicy {
    static func stage(laterCount: Int, test: Bool = false) -> EntraStage {
        let number = laterCount < 4 ? 1 : (laterCount < 8 ? 2 : (laterCount < 12 ? 3 : 4))
        let caps = [2,3,4,6], gaps: [Double] = [14400,10800,7200,5400]
        return EntraStage(number:number,cap:caps[number-1],gap:gaps[number-1] / (test ? 60 : 1))
    }
    static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, number.doubleValue == 0 || number.doubleValue == 1 else { return nil }
        return number.boolValue
    }
    static func jamfAAD(data: Data?, exists: Bool) -> EntraEvidence {
        if !exists { return .init(status:.needsRegistration,reason:"No current-user Jamf registration preference has been created.") }
        guard let data, data.count <= 1_048_576,
              let dictionary = (try? PropertyListSerialization.propertyList(from:data,format:nil)) as? [String:Any],
              let registered = bool(dictionary["have_an_Azure_id"]) else {
            return .init(status:.verificationUnavailable,reason:"Current-user Jamf registration preference is unreadable or has an unrecognized value.")
        }
        return registered ? .init(status:.localRegistered,reason:"The current user's Jamf registration preference reports an Azure ID. Cloud compliance is not assessed.") : .init(status:.needsRegistration,reason:"The current user's Jamf registration preference reports registration is incomplete.")
    }
    static func dayKey(now: Date, test: Bool = false, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year,.month,.day,.hour],from:now)
        return String(format:"%04d%02d%02d",parts.year ?? 0,parts.month ?? 0,parts.day ?? 0) + (test ? String(format:"%02d",parts.hour ?? 0) : "")
    }
    static func withinHours(now: Date, start: Int, end: Int, weekdaysOnly: Bool, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.weekday,.hour],from:now)
        if weekdaysOnly && [1,7].contains(parts.weekday ?? 0) { return false }
        return (parts.hour ?? -1) >= start && (parts.hour ?? 25) < end
    }
    static func dueReason(_ state: EntraUserState, now: Date, test: Bool = false) -> String? {
        let stage = stage(laterCount:state.laterCount,test:test)
        if state.promptsToday >= stage.cap { return "Daily prompt limit reached" }
        if let last = state.lastPromptAt, now.timeIntervalSince(last) < stage.gap { return "Waiting for the minimum reminder gap" }
        return nil
    }
    static func selfServiceURL(policyID: String) -> URL? {
        guard !policyID.isEmpty, policyID.count <= 10, policyID.allSatisfy({ $0.isASCII && $0.isNumber }), let id = Int(policyID), id > 0 else { return nil }
        var url = URLComponents(); url.scheme = "jamfselfservice"; url.host = "content"
        url.queryItems = [.init(name:"entity",value:"policy"),.init(name:"id",value:String(id)),.init(name:"action",value:"view")]
        return url.url
    }
    static func recordResponse(_ code: Int32, state: inout EntraUserState) {
        switch code {
        case 0: state.registerClicks += 1
        case 1: state.laterCount += 1
        case 2: state.closedCount += 1
        case 100: state.timedOutCount += 1
        default: break
        }
    }
}
struct EntraNotice: Codable {
    var stage: Int
    var laterCount: Int
    var message: String
    static func preview(stage: Int = 1) -> EntraNotice {
        let clamped = min(4,max(1,stage))
        let count = [0,4,8,12][clamped-1]
        let messages = [
            "Your organization asks you to register this Mac with Microsoft Entra. Choose Register Now to open the registration policy in Self Service.",
            "Registration is still pending. Please save your work and complete the registration steps in Self Service when you're ready.",
            "Registration remains incomplete after several reminders. Open Self Service to finish, or contact IT if you need help.",
            "Action is required to complete this Mac's registration. Please finish the steps in Self Service or ask IT for assistance."
        ]
        return .init(stage:clamped,laterCount:count,message:messages[clamped-1])
    }
    var heading: String { ["Register your Mac","Registration reminder","Registration still pending","Registration action required"][min(4,max(1,stage))-1] }
    static func decode(_ encoded: String) -> EntraNotice? {
        guard encoded.utf8.count <= 8192, let data = Data(base64Encoded:encoded), let notice = try? JSONDecoder().decode(Self.self,from:data), (1...4).contains(notice.stage), (0...100000).contains(notice.laterCount), notice.message.count <= 2000 else { return nil }
        return notice
    }
}
