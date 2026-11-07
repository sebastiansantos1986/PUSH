// JamfCheckIn — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import AppKit
import SwiftUI

@MainActor
final class UpdateWindowController {
    static let shared = UpdateWindowController()
    private var window: NSWindow?

    func show(update: OSUpdateInfo) {
        close()  // start fresh so content matches the current update

        let hosting = NSHostingController(
            rootView: UpdateDetailView(update: update) { [weak self] in self?.close() }
        )
        hosting.sizingOptions = [.preferredContentSize]  // window sizes to the SwiftUI content

        let w = NSWindow(contentViewController: hosting)
        w.styleMask = [.titled, .closable]
        w.title = update.title
        w.isReleasedWhenClosed = false
        w.center()                       // open in the middle of the screen, away from the popover
        window = w

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
    }
}
