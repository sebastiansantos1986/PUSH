// Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

// MARK: - Entra registration nudge policy
// Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
// Local evidence guides reminders; it is never an access-control or cloud compliance verdict.
enum EntraRegistrationStatus: String, Codable {
    case localRegistered, needsRegistration, verificationUnavailable, setupMissing, notApplicable
    var title: String {
        switch self {
        case .localRegistered: return "Registration detected locally"
        case .needsRegistration: return "Registration needed"
        case .verificationUnavailable: return "Unable to verify registration"
        case .setupMissing: return "IT setup required"
        case .notApplicable: return "Not applicable"
        }
    }
}
struct EntraEvidence {
    let status: EntraRegistrationStatus
    let reason: String
}
struct EntraUserState: Codable {
    var userName = ""
    var status: EntraRegistrationStatus = .verificationUnavailable
    var reason = "Not checked"
    var checkedAt: Date?
    var lastRegistered: Bool?
    var laterCount = 0
    var closedCount = 0
    var timedOutCount = 0
    var registerClicks = 0
    var openedCount = 0
    var promptsToday = 0
    var dayKey = ""
    var lastPromptAt: Date?
    var firstPromptAt: Date?
    var needsRecon = false
    var nextReconAt: Date?
    var lastReconAt: Date?
    var awaitingRegistration = false
    var nextReason = "Not checked"
}
struct EntraNudgeState: Codable { var users: [String:EntraUserState] = [:] }
struct EntraStage {
    let number: Int, cap: Int
    let gap: TimeInterval
}
enum EntraPolicy {
    static func stage(laterCount: Int, test: Bool = false) -> EntraStage {
        let number = laterCount < 4 ? 1 : (laterCount < 8 ? 2 : (laterCount < 12 ? 3 : 4))
        let caps = [2,3,4,6], gaps: [Double] = [14400,10800,7200,5400]
        return EntraStage(number:number,cap:caps[number-1],gap:gaps[number-1] / (test ? 60 : 1))
    }
    static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, number.doubleValue == 0 || number.doubleValue == 1 else { return nil }
        return number.boolValue
    }
    static func jamfAAD(data: Data?, exists: Bool) -> EntraEvidence {
        if !exists { return .init(status:.needsRegistration,reason:"No current-user Jamf registration preference has been created.") }
        guard let data, data.count <= 1_048_576,
              let dictionary = (try? PropertyListSerialization.propertyList(from:data,format:nil)) as? [String:Any],
              let registered = bool(dictionary["have_an_Azure_id"]) else {
            return .init(status:.verificationUnavailable,reason:"Current-user Jamf registration preference is unreadable or has an unrecognized value.")
        }
        return registered ? .init(status:.localRegistered,reason:"The current user's Jamf registration preference reports an Azure ID. Cloud compliance is not assessed.") : .init(status:.needsRegistration,reason:"The current user's Jamf registration preference reports registration is incomplete.")
    }
    static func dayKey(now: Date, test: Bool = false, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year,.month,.day,.hour],from:now)
        return String(format:"%04d%02d%02d",parts.year ?? 0,parts.month ?? 0,parts.day ?? 0) + (test ? String(format:"%02d",parts.hour ?? 0) : "")
    }
    static func withinHours(now: Date, start: Int, end: Int, weekdaysOnly: Bool, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.weekday,.hour],from:now)
        if weekdaysOnly && [1,7].contains(parts.weekday ?? 0) { return false }
        return (parts.hour ?? -1) >= start && (parts.hour ?? 25) < end
    }
    static func dueReason(_ state: EntraUserState, now: Date, test: Bool = false) -> String? {
        let stage = stage(laterCount:state.laterCount,test:test)
        if state.promptsToday >= stage.cap { return "Daily prompt limit reached" }
        if let last = state.lastPromptAt, now.timeIntervalSince(last) < stage.gap { return "Waiting for the minimum reminder gap" }
        return nil
    }
    static func selfServiceURL(policyID: String) -> URL? {
        guard !policyID.isEmpty, policyID.count <= 10, policyID.allSatisfy({ $0.isASCII && $0.isNumber }), let id = Int(policyID), id > 0 else { return nil }
        var url = URLComponents(); url.scheme = "jamfselfservice"; url.host = "content"
        url.queryItems = [.init(name:"entity",value:"policy"),.init(name:"id",value:String(id)),.init(name:"action",value:"view")]
        return url.url
    }
    static func recordResponse(_ code: Int32, state: inout EntraUserState) {
        switch code {
        case 0: state.registerClicks += 1
        case 1: state.laterCount += 1
        case 2: state.closedCount += 1
        case 100: state.timedOutCount += 1
        default: break
        }
    }
}
struct EntraNotice: Codable {
    var stage: Int
    var laterCount: Int
    var message: String
    static func preview(stage: Int = 1) -> EntraNotice {
        let clamped = min(4,max(1,stage))
        let count = [0,4,8,12][clamped-1]
        let messages = [
            "Your organization asks you to register this Mac with Microsoft Entra. Choose Register Now to open the registration policy in Self Service.",
            "Registration is still pending. Please save your work and complete the registration steps in Self Service when you're ready.",
            "Registration remains incomplete after several reminders. Open Self Service to finish, or contact IT if you need help.",
            "Action is required to complete this Mac's registration. Please finish the steps in Self Service or ask IT for assistance."
        ]
        return .init(stage:clamped,laterCount:count,message:messages[clamped-1])
    }
    var heading: String { ["Register your Mac","Registration reminder","Registration still pending","Registration action required"][min(4,max(1,stage))-1] }
    static func decode(_ encoded: String) -> EntraNotice? {
        guard encoded.utf8.count <= 8192, let data = Data(base64Encoded:encoded), let notice = try? JSONDecoder().decode(Self.self,from:data), (1...4).contains(notice.stage), (0...100000).contains(notice.laterCount), notice.message.count <= 2000 else { return nil }
        return notice
    }
}
