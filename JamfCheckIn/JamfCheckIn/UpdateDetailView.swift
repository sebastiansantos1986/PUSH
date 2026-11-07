// JamfCheckIn — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit

struct UpdateDetailView: View {
    let update: OSUpdateInfo
    let onClose: () -> Void

    @State private var details: ReleaseDetails?
    @State private var loading = true

    @StateObject private var pushStatus=StatusMenuStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3).foregroundStyle(.tint)
                Text(update.title).font(.headline)
                Spacer()
            }

            HStack(spacing: 8) {
                if let v = update.version { chip(v, "number") }
                if let s = update.size { chip(s, "internaldrive") }
                if update.requiresRestart { chip("Restart", "restart") }
                if update.recommended { chip("Recommended", "checkmark.seal") }
            }

            Divider()

            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading details from Apple…")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                if let date = details?.postingDate {
                    Label("Released \(date)", systemImage: "calendar")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let summary = details?.summary {
                    ScrollView {
                        Text(summary)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 180)
                } else {
                    Text("Apple's full list of fixes and security content is on their website — open the release notes below.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if PushCLI.isInstalled && pushStatus.snapshot.menuEnabled {PUSHStatusCard(store:pushStatus)}

            Divider()

            HStack {
                Button {
                    NSWorkspace.shared.open(details?.notesURL ?? ReleaseNotes.securityIndex)
                } label: {
                    Label("Release notes", systemImage: "safari")
                }
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.softwareupdate") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Software Update", systemImage: "gearshape")
                }
                Spacer()
                Button("Close") { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            details = await ReleaseNotes.fetch(version: update.version)
            loading = false
        }
    }

    private func chip(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption).fontWeight(.medium)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}
