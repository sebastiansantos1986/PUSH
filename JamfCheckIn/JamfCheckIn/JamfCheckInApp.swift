// JamfCheckIn — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit
import Darwin

@main
struct JamfCheckInApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var monitor = JamfMonitor()
    @StateObject private var pushStatus=StatusMenuStore()
    @StateObject private var loginItem = LoginItem()

    init() {
        // Both older SMAppService registrations and a deployed agent may exist.
        // Keep one menu process without modifying the user's login registrations.
        let own=NSRunningApplication.current
        if let id=Bundle.main.bundleIdentifier,NSRunningApplication.runningApplications(withBundleIdentifier:id).contains(where:{$0.processIdentifier != own.processIdentifier && ($0.launchDate ?? .distantPast)<(own.launchDate ?? .distantFuture)}) {exit(0)}
    }
    var body: some Scene {
        MenuBarExtra {
            ContentView(monitor: monitor, loginItem: loginItem, settings: settings, pushStatus: pushStatus)
        } label: {
            Image(nsImage: monitor.menuBarImage)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings)
        }
    }
}
