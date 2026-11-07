// JamfCheckIn — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

struct ReleaseDetails: Sendable {
    var postingDate: String?      // from Apple's gdmf (structured, reliable)
    var notesURL: URL             // specific security page if found, else the index
    var summary: String?          // best-effort scraped text (may be nil)
}

enum ReleaseNotes {
    /// Apple's "security releases" index — always a valid destination.
    static let securityIndex = URL(string: "https://support.apple.com/en-us/100100")!

    static func fetch(version: String?) async -> ReleaseDetails {
        var details = ReleaseDetails(postingDate: nil, notesURL: securityIndex, summary: nil)
        guard let version, !version.isEmpty else { return details }

        if let date = await postingDate(for: version) {
            details.postingDate = date
        }
        if let page = await securityPage(for: version) {
            details.notesURL = page.url
            details.summary = page.summary
        }
        return details
    }

    /// Structured: Apple's product-version feed gives the posting date for a version.
    private static func postingDate(for version: String) async -> String? {
        guard let url = URL(string: "https://gdmf.apple.com/v2/pmv"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assetSets = json["AssetSets"] as? [String: Any],
              let macOS = assetSets["macOS"] as? [[String: Any]]
        else { return nil }

        for entry in macOS where (entry["ProductVersion"] as? String) == version {
            return entry["PostingDate"] as? String
        }
        return nil
    }

    /// Best-effort: find the version's security page on the index, then scrape a snippet.
    private static func securityPage(for version: String) async -> (url: URL, summary: String?)? {
        guard let (data, _) = try? await URLSession.shared.data(from: securityIndex) else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        guard let href = matchingHref(in: html, version: version) else { return nil }
        let pageURL = URL(string: "https://support.apple.com\(href)") ?? securityIndex

        var summary: String?
        if let (pageData, _) = try? await URLSession.shared.data(from: pageURL) {
            summary = extractSummary(String(decoding: pageData, as: UTF8.self))
        }
        return (pageURL, summary)
    }

    private static func matchingHref(in html: String, version: String) -> String? {
        let pattern = #"<a[^>]+href="(/[a-z-]+/\d+)"[^>]*>([^<]*macOS[^<]*)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return nil }
        let ns = html as NSString
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let text = ns.substring(with: match.range(at: 2))
            if text.contains(version) {
                return ns.substring(with: match.range(at: 1))
            }
        }
        return nil
    }

    private static func extractSummary(_ html: String) -> String? {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 60 else { return nil }
        if let r = text.range(of: "security content") {
            text = String(text[r.lowerBound...])
        }
        return String(text.prefix(700))
    }
}
