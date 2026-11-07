// Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
func saveUserPasswordToLoginKeychain(account: String, password: String) -> Bool { false }

func supportContactURL(email: String, website: String) -> URL? {
    let address = email.trimmingCharacters(in:.whitespacesAndNewlines)
    if address.contains("@"), !address.contains("\n"), !address.contains("\r") {
        var components = URLComponents(); components.scheme = "mailto"; components.path = address
        components.queryItems = [URLQueryItem(name:"subject",value:"PUSH update support")]
        return components.url
    }
    if let url = URL(string:website), url.scheme == "https", url.host?.isEmpty == false { return url }
    return nil
}

func validReminderDate(_ chosen: Date, deadline: Date, now: Date = Date()) -> Bool {
    chosen > now && chosen <= deadline
}
func popupBackgroundOpacity(_ percent: Int, reduceTransparency: Bool = false) -> Double {
    reduceTransparency ? 1 : Double(min(100, max(55, percent))) / 100
}
func previewButtonTitle(state: String, code: Int32) -> String {
    switch code {
    case 7:return "Automatic recovery retry due"
    case 0: return state == "updateRecovery" ? "Update now" : state == "entraRegistration" ? "Register Now" : state == "appUpdates" ? "Update Closed Apps" : ["rebootNudge", "rebootForce", "rebooting"].contains(state) ? "Restart Now" : (state == "preflightPower" ? "Power detected" : "Install Now")
    case 1: return "Later"
    case 2: return state == "compliant" ? "Done" : (state == "error" ? "Dismiss" : "Close / Skip")
    case 3: return "Schedule confirmed"
    case 4: return "Power wait timed out"
    case 5: return "Toast auto-dismissed"
    case 6: return "Contact IT"
    default: return "Response \(code)"
    }
}

func reminderPickerRange(now: Date, deadline: Date) -> ClosedRange<Date> {
    now...max(now, deadline)
}

/// A test-only sample window; the saved enforcement deadline is never modified.
func reminderTestDeadline(configured: Date?, manualTest: Bool, now: Date = Date()) -> Date {
    guard let configured else { return now.addingTimeInterval(7 * 86400) }
    return manualTest && configured <= now ? now.addingTimeInterval(7 * 86400) : configured
}
