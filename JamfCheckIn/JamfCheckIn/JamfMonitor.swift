// JamfCheckIn — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import Combine
import AppKit

struct OSUpdateInfo: Sendable {
    var label: String
    var title: String
    var version: String?
    var size: String?
    var requiresRestart: Bool
    var recommended: Bool
}

enum OSUpdateResult: Sendable {
    case none
    case unknown
    case update(OSUpdateInfo)
}

@MainActor
final class JamfMonitor: ObservableObject {
    enum Reachability { case unknown, checking, reachable, unreachable }

    @Published private(set) var lastCheckIn: Date?
    @Published private(set) var statusMessage = "Checking…"
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var deviceInfo = DeviceInfo()
    @Published private(set) var reachability: Reachability = .unknown
    @Published private(set) var isWorking = false
    @Published private(set) var actionMessage: String?
    @Published private(set) var osUpdateAvailable: Bool?   // nil = not checked yet
    @Published private(set) var osUpdate: OSUpdateInfo?

    let logPath = "/var/log/jamf.log"

    private let settings = AppSettings.shared
    private var alertedStale = false
    private var timer: Timer?
    private var osTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private var staleThreshold: TimeInterval { TimeInterval(settings.staleHours) * 3600 }
    private var alertThreshold: TimeInterval { TimeInterval(settings.alertHours) * 3600 }

    init() {
        Notifier.requestAuthorization()
        refresh()
        scheduleTimer()
        checkOSUpdates()
        osTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkOSUpdates() }
        }
        settings.$refreshSeconds
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleTimer() }
            .store(in: &cancellables)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(15, settings.refreshSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Base SF Symbol for the menu bar, reflecting check-in freshness.
    var menuBarSymbol: String {
        guard let last = lastCheckIn else { return "questionmark.circle" }
        return Date().timeIntervalSince(last) <= staleThreshold
            ? "checkmark.shield.fill"
            : "exclamationmark.shield.fill"
    }

    /// Overall compliance: a known-Off security setting or an available macOS
    /// update makes the Mac non-compliant. "Unknown" values are not counted.
    var isCompliant: Bool {
        if osUpdateAvailable == true { return false }
        let i = deviceInfo
        return ![i.fileVault, i.gatekeeper, i.firewall, i.sip].contains("Off")
    }

    /// Rendered menu bar image; gains a red X badge when not compliant.
    var menuBarImage: NSImage {
        MenuBarIcon.make(badge: !isCompliant)
    }

    func refresh() {
        lastRefreshed = Date()
        let path = logPath
        Task.detached(priority: .utility) {
            let content = Self.readLog(path)
            let parsed = Self.parsed(from: content)
            let info = SystemInfo.gather(logContent: content ?? "")
            await MainActor.run {
                self.lastCheckIn = parsed.date
                self.statusMessage = parsed.message
                self.deviceInfo = info
                self.evaluateAlert()
            }
            await self.checkReachability(info.jssURL)
        }
    }

    func checkOSUpdates() {
        Task.detached(priority: .utility) {
            let result = Self.osUpdateStatus()
            await MainActor.run {
                switch result {
                case .none:
                    self.osUpdateAvailable = false
                    self.osUpdate = nil
                case .unknown:
                    self.osUpdateAvailable = nil
                    self.osUpdate = nil
                case .update(let info):
                    self.osUpdateAvailable = true
                    self.osUpdate = info
                }
            }
        }
    }

    private func evaluateAlert() {
        guard let last = lastCheckIn else { return }
        if Date().timeIntervalSince(last) > alertThreshold {
            if !alertedStale {
                Notifier.notifyStale(lastCheckIn: last)
                alertedStale = true
            }
        } else {
            alertedStale = false
        }
    }

    func checkReachability(_ urlString: String?) async {
        guard let urlString, let url = URL(string: urlString) else {
            reachability = .unknown
            return
        }
        reachability = .checking
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 6
        do {
            _ = try await URLSession.shared.data(for: request)
            reachability = .reachable
        } catch {
            reachability = .unreachable
        }
    }

    func checkInNow() { runAdminAction("/usr/local/bin/jamf policy", label: "Checking in…") }
    func updateInventory() { runAdminAction("/usr/local/bin/jamf recon", label: "Updating inventory…") }

    private func runAdminAction(_ command: String, label: String) {
        guard !isWorking else { return }
        isWorking = true
        actionMessage = label
        Task.detached(priority: .userInitiated) {
            let result = Shell.runAdmin(command)
            await MainActor.run {
                self.isWorking = false
                self.actionMessage = result.status == 0
                    ? "Done."
                    : "Command failed (exit \(result.status))."
                self.refresh()
            }
        }
    }

    // MARK: - Non-isolated helpers (run off the main actor)

    nonisolated static func readLog(_ path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated static func parsed(from content: String?) -> (date: Date?, message: String) {
        guard let content else {
            return (nil, "No Jamf log at /var/log/jamf.log. This Mac may not be managed by Jamf.")
        }
        if let date = lastCheckInDate(in: content) {
            return (date, "Last recurring check-in found.")
        }
        return (nil, "No recurring check-in entries found in the log yet.")
    }

    nonisolated static func lastCheckInDate(in content: String) -> Date? {
        let lines = content.split(whereSeparator: \.isNewline)
        for line in lines.reversed() where line.contains("recurring check-in") {
            if let date = syslogDate(from: String(line)) { return date }
        }
        for line in lines.reversed() {
            if let date = syslogDate(from: String(line)) { return date }
        }
        return nil
    }

    /// Inspects `softwareupdate -l` and returns the macOS update (if any).
    nonisolated static func osUpdateStatus() -> OSUpdateResult {
        let output = Shell.run("/usr/sbin/softwareupdate", ["-l"]).output
        if output.isEmpty { return .unknown }
        if output.lowercased().contains("no new software available") { return .none }
        if let info = parseOSUpdate(output) { return .update(info) }
        return .none
    }

    nonisolated static func parseOSUpdate(_ output: String) -> OSUpdateInfo? {
        let lines = output.split(separator: "\n").map(String.init)
        func field(_ key: String, in s: String) -> String? {
            guard let r = s.range(of: "\(key):") else { return nil }
            let value = s[r.upperBound...].prefix(while: { $0 != "," })
                .trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        var i = 0
        while i < lines.count {
            if let r = lines[i].range(of: "Label:") {
                let label = lines[i][r.upperBound...].trimmingCharacters(in: .whitespaces)
                let detail = (i + 1 < lines.count) ? lines[i + 1] : ""
                if label.lowercased().contains("macos") || detail.lowercased().contains("title: macos") {
                    let action = (field("Action", in: detail) ?? "").lowercased()
                    return OSUpdateInfo(
                        label: label,
                        title: field("Title", in: detail) ?? label,
                        version: field("Version", in: detail),
                        size: formatUpdateSize(field("Size", in: detail)),
                        requiresRestart: action.contains("restart"),
                        recommended: (field("Recommended", in: detail) ?? "").uppercased() == "YES"
                    )
                }
            }
            i += 1
        }
        return nil
    }

    nonisolated static func formatUpdateSize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.replacingOccurrences(of: "KiB", with: "")
            .trimmingCharacters(in: .whitespaces)
        if let kib = Double(trimmed) {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter.string(fromByteCount: Int64(kib * 1024))
        }
        return raw
    }

    nonisolated static func syslogDate(from line: String) -> Date? {
        let normalized = line.replacingOccurrences(
            of: " +", with: " ", options: .regularExpression
        )
        let parts = normalized.split(separator: " ")
        guard parts.count >= 4 else { return nil }

        let stamp = "\(parts[1]) \(parts[2]) \(parts[3])"

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d HH:mm:ss"
        guard let partial = formatter.date(from: stamp) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)

        var comps = calendar.dateComponents(
            [.month, .day, .hour, .minute, .second], from: partial
        )
        comps.year = currentYear
        guard var candidate = calendar.date(from: comps) else { return nil }

        if candidate.timeIntervalSince(now) > 86_400 {
            comps.year = currentYear - 1
            candidate = calendar.date(from: comps) ?? candidate
        }
        return candidate
    }
}
