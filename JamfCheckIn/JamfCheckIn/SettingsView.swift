// JamfCheckIn — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Check-in") {
                Stepper("Mark stale after \(settings.staleHours) hours",
                        value: $settings.staleHours, in: 1...168)
                Stepper("Notify after \(settings.alertHours) hours",
                        value: $settings.alertHours, in: 1...336)
            }

            Section("Refresh") {
                Stepper("Refresh every \(settings.refreshSeconds) seconds",
                        value: $settings.refreshSeconds, in: 15...3600, step: 15)
            }

            Section("Help") {
                TextField("Helpdesk URL or email", text: $settings.helpdeskURL)
                    .textFieldStyle(.roundedBorder)
                Text("Used by the “Get help” button. A plain address becomes a mailto link.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Self Service app name", text: $settings.selfServiceApp)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 380)
    }
}
