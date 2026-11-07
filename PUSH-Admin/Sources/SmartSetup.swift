// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import Foundation

struct SmartPolicySetupCard: View {
    @EnvironmentObject var store: AdminStore
    var body: some View {
        AdminCard {
            Label("Set up once", systemImage: "sparkles").font(.headline)
            Text("Choose which releases to follow. PUSH discovers eligible updates on each scheduled check; you do not need to edit version numbers.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Stay on current major") { store.document.followReleases(allowMajorUpgrades: false) }
                Button("Allow major upgrades") { store.document.followReleases(allowMajorUpgrades: true) }
            }
            Text("These buttons change the draft only. Your deadline override and other settings are retained. Apply the policy, then enable five-minute monitoring in Deployment.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Deadline priority: explicit YAML update.deadline → automatic deadline from first detection. A generated deadline is stored separately and does not overwrite your override.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct InstalledDiscoveryHealth: Decodable {
    var lastDiscoveryDate: Date?
    var lastDiscoveryError: String?
    var lastRecoveryMessage: String?
    var installStarted: Bool?
    var installCompleted: Bool?
}

struct InstalledHealthCard: View {
    @EnvironmentObject var store: AdminStore
    private var health: InstalledDiscoveryHealth? {
        guard let data = FileManager.default.contents(atPath: "/Library/Management/PUSH/state.json") else { return nil }
        return try? JSONDecoder().decode(InstalledDiscoveryHealth.self, from: data)
    }
    private var config: UIConfig { UIConfig.load(from: "/Library/Management/PUSH/config.yaml") }
    var body: some View {
        let snapshot = health
        AdminCard {
            HStack {
                Label("Installed policy health", systemImage: "heart.text.square").font(.headline)
                Spacer()
                Button("Refresh") { store.objectWillChange.send() }
            }
            if store.pushInstalled {
                LabeledContent("Saved target", value: config.update.targetVersion.isEmpty ? "Automatic / not discovered yet" : config.update.targetVersion)
                LabeledContent("Effective deadline", value: config.deadlineDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not set")
                LabeledContent("Last discovery", value: snapshot?.lastDiscoveryDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "No result recorded")
                LabeledContent("Installation", value: snapshot?.installStarted == true ? "Pending — next check verifies installation state" : (snapshot?.installCompleted == true ? "Completed" : "Idle"))
                if let issue = snapshot?.lastDiscoveryError, !issue.isEmpty { Text(issue).font(.callout).foregroundStyle(.orange) }
                if let recovery = snapshot?.lastRecoveryMessage { Text(recovery).font(.caption).foregroundStyle(.secondary) }
                Text("Shows saved results from PUSH. Refresh reads local files; it does not run an update check.").font(.caption).foregroundStyle(.secondary)
            } else { Text("Install the PUSH engine to see its saved discovery and installation status.").foregroundStyle(.secondary) }
        }
    }
}
