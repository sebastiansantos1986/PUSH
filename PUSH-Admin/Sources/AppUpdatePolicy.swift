// Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

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
