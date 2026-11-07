// JamfCheckIn — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import UserNotifications

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifyStale(lastCheckIn: Date?) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = "Jamf check-in is stale"
            if let last = lastCheckIn {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .full
                content.body = "This Mac last checked in \(formatter.localizedString(for: last, relativeTo: Date()))."
            } else {
                content.body = "No recent Jamf check-in was found for this Mac."
            }
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil
            )
            center.add(request)
        }
    }
}
