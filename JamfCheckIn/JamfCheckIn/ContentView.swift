// JamfCheckIn — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var monitor: JamfMonitor
    @ObservedObject var loginItem: LoginItem
    @ObservedObject var settings: AppSettings

    @ObservedObject var pushStatus: StatusMenuStore

    @State private var toast: String?

    // MARK: - Formatters

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static let uptimeFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.day, .hour, .minute]
        f.maximumUnitCount = 2
        f.unitsStyle = .abbreviated
        return f
    }()

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                heroCard
                actionButtons
                if PushCLI.isInstalled && pushStatus.snapshot.menuEnabled {PUSHStatusCard(store:pushStatus)}
                complianceCard
                deviceCard
                identityCard
                utilityButtons
                footer
            }
            .padding(16)
        }
        .frame(width: 340, height: 600)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.title3).foregroundStyle(.tint)
            Text("Jamf Check-In").font(.headline)
            Spacer()
            settingsButton
            Button { monitor.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Refresh now")
        }
    }

    @ViewBuilder
    private var settingsButton: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        } else {
            Button { openSettingsLegacy() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).help("Settings")
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        card {
            HStack(spacing: 6) {
                Image(systemName: statusIcon)
                Text(statusLabel).fontWeight(.semibold)
                Spacer()
            }
            .font(.subheadline)
            .foregroundStyle(statusColor)

            if let last = monitor.lastCheckIn {
                Text(Self.relativeFormatter.localizedString(for: last, relativeTo: Date()))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Last check-in · \(Self.absoluteFormatter.string(from: last))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(monitor.statusMessage)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let inventory = monitor.deviceInfo.lastInventory {
                Label(
                    "Inventory \(Self.relativeFormatter.localizedString(for: inventory, relativeTo: Date()))",
                    systemImage: "list.bullet.clipboard"
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Check-in / inventory actions

    private var actionButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { monitor.checkInNow() } label: {
                    Label("Check in", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                Button { monitor.updateInventory() } label: {
                    Label("Inventory", systemImage: "list.bullet.clipboard")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered).controlSize(.large)
            .disabled(monitor.isWorking)

            if monitor.isWorking {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(monitor.actionMessage ?? "Working…")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            } else if let message = monitor.actionMessage {
                HStack {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Compliance

    private var complianceCard: some View {
        let info = monitor.deviceInfo
        return card {
            sectionLabel("SECURITY")
            complianceRow("FileVault", info.fileVault)
            complianceRow("Gatekeeper", info.gatekeeper)
            complianceRow("Firewall", info.firewall)
            complianceRow("SIP", info.sip)
        }
    }

    // MARK: - Device

    private var deviceCard: some View {
        let info = monitor.deviceInfo
        return card {
            sectionLabel("THIS MAC")
            infoRow(icon: "apple.logo", label: "macOS", value: info.osVersion)
            if info.diskTotalBytes > 0 {
                diskRow(used: info.diskUsedBytes, total: info.diskTotalBytes)
            }
            infoRow(icon: "battery.100", label: "Battery", value: batteryText(info))
            if let detail = batteryDetailText(info) {
                infoRow(icon: "bolt.fill", label: "Health", value: detail)
            }
            if let boot = info.bootTime {
                infoRow(icon: "clock.arrow.circlepath", label: "Last reboot", value: rebootText(boot))
            }
            updatesRow
        }
    }

    @ViewBuilder
    private var updatesRow: some View {
        if monitor.osUpdateAvailable == true, monitor.osUpdate != nil {
            Button {
                if let update = monitor.osUpdate {
                    UpdateWindowController.shared.show(update: update)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 16)
                    Text("macOS updates").font(.subheadline)
                    Spacer(minLength: 8)
                    Text(updatesText).font(.subheadline).fontWeight(.medium).foregroundStyle(.red)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            infoRow(icon: "arrow.down.circle", label: "macOS updates",
                    value: updatesText, valueColor: updatesColor)
        }
    }

    // MARK: - Identity

    private var identityCard: some View {
        let info = monitor.deviceInfo
        return card {
            sectionLabel("IDENTITY")
            infoRow(icon: "desktopcomputer", label: "Name", value: info.computerName)
            infoRow(icon: "number", label: "Serial", value: info.serialNumber)
            infoRow(icon: "cpu", label: "Model", value: info.model)
            infoRow(icon: "person.fill", label: "User", value: info.currentUser)
            infoRow(icon: "wifi", label: "IP", value: info.localIP)
            infoRow(icon: "checkmark.seal.fill", label: "Enrollment", value: info.enrollment)
            serverRow(info)
        }
    }

    private func serverRow(_ info: DeviceInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 16)
                Text("Server").font(.subheadline)
                Spacer(minLength: 8)
                Circle().fill(reachColor).frame(width: 7, height: 7)
                Text(reachText).font(.subheadline).fontWeight(.medium)
            }
            if let url = info.jssURL {
                Text(url)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .padding(.leading, 26)
            }
        }
    }

    // MARK: - Utility buttons

    private var utilityButtons: some View {
        VStack(spacing: 8) {
            Button { copyDiagnostics() } label: {
                Label("Copy diagnostics", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: 8) {
                Button { openSelfService() } label: {
                    Label("Self Service", systemImage: "bag").frame(maxWidth: .infinity)
                }
                Button { openHelp() } label: {
                    Label("Get help", systemImage: "questionmark.circle").frame(maxWidth: .infinity)
                }
                .disabled(helpTargetEmpty)
            }
            if let toast {
                HStack {
                    Text(toast).font(.caption).foregroundStyle(.green)
                    Spacer()
                }
            }
        }
        .buttonStyle(.bordered).controlSize(.large)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Launch at login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.set($0) }
            ))
            .toggleStyle(.switch).font(.subheadline).disabled(loginItem.managedByDeployment)
            if loginItem.managedByDeployment {Text("Login startup is configured by your deployment.").font(.caption2).foregroundStyle(.secondary)}

            HStack {
                if let refreshed = monitor.lastRefreshed {
                    Text("Updated \(Self.absoluteFormatter.string(from: refreshed))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
                .buttonStyle(.borderless).controlSize(.small)
            }
        }
    }

    // MARK: - Reusable pieces

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2).fontWeight(.semibold)
            .foregroundStyle(.secondary).tracking(0.6)
    }

    private func infoRow(icon: String, label: String, value: String,
                         valueColor: Color = .primary) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 16)
            Text(label).font(.subheadline)
            Spacer(minLength: 8)
            Text(value).font(.subheadline).fontWeight(.medium)
                .foregroundStyle(valueColor).multilineTextAlignment(.trailing)
        }
    }

    private func complianceRow(_ label: String, _ status: String) -> some View {
        let icon: String
        let color: Color
        switch status {
        case "On": icon = "checkmark.circle.fill"; color = .green
        case "Off": icon = "xmark.circle.fill"; color = .red
        default: icon = "minus.circle.fill"; color = .gray
        }
        return HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 16)
            Text(label).font(.subheadline)
            Spacer(minLength: 8)
            Text(status).font(.subheadline).fontWeight(.medium)
                .foregroundStyle(status == "On" || status == "Off" ? color : .secondary)
        }
    }

    private func diskRow(used: Int64, total: Int64) -> some View {
        let fraction = total > 0 ? Double(used) / Double(total) : 0
        let color: Color = fraction > 0.9 ? .red : (fraction > 0.75 ? .orange : .accentColor)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 16)
                Text("Disk").font(.subheadline)
                Spacer(minLength: 8)
                Text("\(bytes(used)) of \(bytes(total))")
                    .font(.subheadline).fontWeight(.medium)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule().fill(color).frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 6).padding(.leading, 26)
        }
    }

    // MARK: - Actions (non-privileged)

    private func openSettingsLegacy() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func copyDiagnostics() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(diagnosticsText(), forType: .string)
        toast = "Copied to clipboard"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = nil }
    }

    private func openSelfService() {
        let name = settings.selfServiceApp.isEmpty ? "Self Service" : settings.selfServiceApp
        Shell.run("/usr/bin/open", ["-a", name])
    }

    private func openHelp() {
        let raw = settings.helpdeskURL.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        var urlString = raw
        if raw.contains("@"), !raw.hasPrefix("mailto:") {
            urlString = "mailto:\(raw)"
        } else if !raw.hasPrefix("http"), !raw.hasPrefix("mailto:") {
            urlString = "https://\(raw)"
        }
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }

    private func diagnosticsText() -> String {
        let i = monitor.deviceInfo
        var lines: [String] = []
        lines.append("Computer: \(i.computerName)")
        lines.append("Serial: \(i.serialNumber)")
        lines.append("Model: \(i.model)")
        lines.append("User: \(i.currentUser)")
        lines.append("macOS: \(i.osVersion)")
        lines.append("IP: \(i.localIP)")
        if let last = monitor.lastCheckIn {
            lines.append("Last check-in: \(Self.absoluteFormatter.string(from: last))")
        }
        if let inv = i.lastInventory {
            lines.append("Last inventory: \(Self.absoluteFormatter.string(from: inv))")
        }
        if let url = i.jssURL { lines.append("Jamf server: \(url)") }
        lines.append("FileVault \(i.fileVault) · Gatekeeper \(i.gatekeeper) · Firewall \(i.firewall) · SIP \(i.sip)")
        lines.append("Enrollment: \(i.enrollment)")
        lines.append("Disk: \(bytes(i.diskUsedBytes)) of \(bytes(i.diskTotalBytes)) used")
        return lines.joined(separator: "\n")
    }

    // MARK: - Computed helpers

    private var helpTargetEmpty: Bool {
        settings.helpdeskURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var updatesText: String {
        switch monitor.osUpdateAvailable {
        case .some(true): return "Update available"
        case .some(false): return "Up to date"
        case .none: return "Checking…"
        }
    }

    private var updatesColor: Color {
        switch monitor.osUpdateAvailable {
        case .some(true): return .red
        case .some(false): return .green
        case .none: return .secondary
        }
    }

    private enum CheckInStatus { case fresh, stale, unknown }

    private var status: CheckInStatus {
        guard let last = monitor.lastCheckIn else { return .unknown }
        return Date().timeIntervalSince(last) <= TimeInterval(settings.staleHours) * 3600 ? .fresh : .stale
    }

    private var statusColor: Color {
        switch status {
        case .fresh: return .green
        case .stale: return .orange
        case .unknown: return .gray
        }
    }

    private var statusLabel: String {
        switch status {
        case .fresh: return "Up to date"
        case .stale: return "Check-in is stale"
        case .unknown: return "No check-in data"
        }
    }

    private var statusIcon: String {
        switch status {
        case .fresh: return "checkmark.circle.fill"
        case .stale: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private func bytes(_ value: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB]
        f.countStyle = .file
        return f.string(fromByteCount: value)
    }

    private func batteryText(_ info: DeviceInfo) -> String {
        guard info.hasBattery else { return "No battery" }
        var parts: [String] = []
        if let p = info.batteryPercent { parts.append("\(p)%") }
        if let h = info.batteryHealth { parts.append(h) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func batteryDetailText(_ info: DeviceInfo) -> String? {
        guard info.hasBattery else { return nil }
        var parts: [String] = []
        if let m = info.batteryMaxCapacityPercent { parts.append("\(m)% max") }
        if let c = info.batteryCycleCount { parts.append("\(c) cycles") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func rebootText(_ boot: Date) -> String {
        if let up = Self.uptimeFormatter.string(from: boot, to: Date()) {
            return "up \(up)"
        }
        return Self.absoluteFormatter.string(from: boot)
    }

    private var reachColor: Color {
        switch monitor.reachability {
        case .reachable: return .green
        case .unreachable: return .red
        case .checking, .unknown: return .gray
        }
    }

    private var reachText: String {
        switch monitor.reachability {
        case .reachable: return "Reachable"
        case .unreachable: return "Unreachable"
        case .checking: return "Checking…"
        case .unknown: return "Unknown"
        }
    }
}
