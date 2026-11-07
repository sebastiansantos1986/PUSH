// PUSH — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

enum RecoveryFailureKind:String,Codable {
    case power,disk,network,download,installer,authorization,verification,state
    var allowsAutomaticRetry:Bool {![Self.authorization,.verification,.state].contains(self)}
    static func classify(_ message:String)->Self {
        let text=message.lowercased()
        if text.contains("authorization") || text.contains("secure token") || text.contains("credential") {return .authorization}
        if text.contains("gatekeeper") || text.contains("product version") || text.contains("signature") {return .verification}
        if text.contains("state") && text.contains("save") {return .state}
        if text.contains("disk") || text.contains("free space") {return .disk}
        if text.contains("power") || text.contains("battery") {return .power}
        if text.contains("network") || text.contains("apple servers") || text.contains("internet") {return .network}
        if text.contains("download") {return .download}
        return .installer
    }
}
struct InstallRecoveryRecord:Codable {
    var id=UUID().uuidString
    var target:String
    var reason:String
    var kind:RecoveryFailureKind
    var failedAt:Date
    var phase="failed"
    var retryAt:Date?
    var noticeShownAt:Date?
    var automaticAttempts:[Date]=[]
    var lastNoticeAt:Date?
}
struct RecoveryNotice:Codable {
    var target:String
    var reason:String
    var retryAt:Date?
    var automatic:Bool
    var explanation:String
    static func preview(now:Date=Date())->Self {.init(target:"27.2",reason:"The previous download could not complete because the network was unavailable.",retryAt:now.addingTimeInterval(600),automatic:true,explanation:"SIMULATED · No download, installation or restart will run.")}
    func remaining(at date:Date)->Int {Int(ceil(min(86400,max(0,retryAt?.timeIntervalSince(date) ?? 0))))}
    func countdownDue(at date:Date)->Bool {automatic && retryAt.map{$0<=date}==true}
    static func decode(_ text:String)->Self? {
        guard text.count<16384,let bytes=Data(base64Encoded:text),let notice=try? JSONDecoder().decode(Self.self,from:bytes),RetryPolicy.version(notice.target) != nil,notice.reason.count<=600,notice.explanation.count<=1000 else{return nil}
        if notice.automatic && notice.retryAt == nil {return nil}
        if let date=notice.retryAt,(!date.timeIntervalSince1970.isFinite || abs(date.timeIntervalSinceNow)>604800){return nil}
        return notice
    }
}
enum RetryPolicy {
    static func version(_ text:String)->[Int]? {
        let parts=text.split(separator:".",omittingEmptySubsequences:false)
        guard (1...3).contains(parts.count),parts.allSatisfy({!$0.isEmpty && $0.allSatisfy{$0.isASCII && $0.isNumber}}) else{return nil}
        let values=parts.compactMap{Int($0)};guard values.count==parts.count else{return nil}
        return values+Array(repeating:0,count:3-values.count)
    }
    static func same(_ lhs:String,_ rhs:String)->Bool {guard let a=version(lhs),let b=version(rhs) else{return false};return a==b}
    static func attempts(_ record:InstallRecoveryRecord,now:Date)->[Date] {record.automaticAttempts.filter{$0<=now && now.timeIntervalSince($0)<86400}}
    static func automaticAllowed(_ record:InstallRecoveryRecord,enabled:Bool,pastDeadline:Bool,dryRun:Bool,automaticInstall:Bool,limit:Int,now:Date)->Bool {
        enabled && pastDeadline && !dryRun && automaticInstall && record.phase=="failed" && record.kind.allowsAutomaticRetry && attempts(record,now:now).count<min(6,max(0,limit))
    }
    static func nextTime(_ record:InstallRecoveryRecord,countdownMinutes:Int,backoffMinutes:Int,now:Date)->Date {
        let countdown=now.addingTimeInterval(Double(min(60,max(1,countdownMinutes)))*60)
        let spacing=attempts(record,now:now).max()?.addingTimeInterval(Double(max(5,min(240,backoffMinutes)))*60) ?? countdown
        return max(countdown,spacing)
    }
    static func noticeFresh(_ record:InstallRecoveryRecord,now:Date)->Bool {record.noticeShownAt.map{now.timeIntervalSince($0)>=0 && now.timeIntervalSince($0)<86400} ?? false}
    static func canRetryNow(_ record:InstallRecoveryRecord,automatic:Bool,now:Date)->Bool {
        if !automatic {return true}
        return noticeFresh(record,now:now) && record.retryAt.map{$0<=now} == true
    }
}
enum UserUpdateAction:String,Codable {case install,remindOneHour}
struct UserUpdateRequest:Codable {
    var id=UUID().uuidString
    var userUID:Int
    var target:String
    var action:UserUpdateAction
    var issuedAt:Date
    static func allowed(policyAvailable:Bool,enabled:Bool,dryRun:Bool,requestsEnabled:Bool,pending:Bool,monitor:Bool?,target:String,running:String)->Bool {
        guard let required=RetryPolicy.version(target),let current=RetryPolicy.version(running) else{return false}
        return policyAvailable && enabled && !dryRun && requestsEnabled && !pending && monitor==true && current.lexicographicallyPrecedes(required)
    }
    static func valid(_ request:Self,owner:Int,target:String,now:Date)->Bool {
        request.userUID==owner && UUID(uuidString:request.id) != nil && RetryPolicy.same(request.target,target) && now.timeIntervalSince(request.issuedAt)>=(-60) && now.timeIntervalSince(request.issuedAt)<=900
    }
}
struct UserRequestResult:Codable {
    var requestID:String
    var userUID:Int
    var target:String
    var date:Date
    var message:String
}
