// JamfCheckIn — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import AppKit

enum MenuBarIcon {
    /// Builds the menu-bar image from the app's StatusIcon asset, adding a red "X"
    /// badge when the Mac is not compliant. Non-template so the artwork keeps color.
    static func make(badge: Bool) -> NSImage {
        let target = NSSize(width: badge ? 21 : 18, height: 18)
        let image = NSImage(size: target)
        image.lockFocus()

        if let icon = NSImage(named: "StatusIcon") {
            let side: CGFloat = 18
            icon.draw(in: NSRect(x: 0, y: (target.height - side) / 2, width: side, height: side))
        }

        if badge {
            let badgeConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white, .systemRed]))
            if let x = NSImage(systemSymbolName: "xmark.circle.fill",
                               accessibilityDescription: "Not compliant")?
                .withSymbolConfiguration(badgeConfig) {
                let xs = x.size
                x.draw(in: NSRect(x: target.width - xs.width, y: 0,
                                  width: xs.width, height: xs.height))
            }
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
