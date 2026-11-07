// JamfCheckIn — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var staleHours: Int { didSet { defaults.set(staleHours, forKey: "staleHours") } }
    @Published var alertHours: Int { didSet { defaults.set(alertHours, forKey: "alertHours") } }
    @Published var refreshSeconds: Int { didSet { defaults.set(refreshSeconds, forKey: "refreshSeconds") } }
    @Published var helpdeskURL: String { didSet { defaults.set(helpdeskURL, forKey: "helpdeskURL") } }
    @Published var selfServiceApp: String { didSet { defaults.set(selfServiceApp, forKey: "selfServiceApp") } }

    private let defaults = UserDefaults.standard

    private init() {
        // didSet does not fire during initialization, so these reads won't write back.
        staleHours = defaults.object(forKey: "staleHours") as? Int ?? 24
        alertHours = defaults.object(forKey: "alertHours") as? Int ?? 48
        refreshSeconds = defaults.object(forKey: "refreshSeconds") as? Int ?? 60
        helpdeskURL = defaults.string(forKey: "helpdeskURL") ?? ""
        selfServiceApp = defaults.string(forKey: "selfServiceApp") ?? "Self Service"
    }
}
