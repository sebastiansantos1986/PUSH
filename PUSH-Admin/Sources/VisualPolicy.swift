// PUSH — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

struct NotificationHistoryEvent:Codable,Identifiable {
    var id=UUID().uuidString
    var attempt:String
    var date:Date
    var state:String
    var mode:String
    var outcome:String
    var reason:String
    var code:Int32?
    var userUID:Int?
    var target:String?
    var retryAt:Date?
}
struct NotificationHistoryDocument:Codable {var events:[NotificationHistoryEvent]=[]}
enum NotificationHistoryPolicy {
    static func state(in command:String)->String {
        guard let range=command.range(of:#"--state\s+[\"']?([A-Za-z]+)"#,options:.regularExpression) else{return "unknown"}
        return String(command[range]).replacingOccurrences(of:"--state",with:"").trimmingCharacters(in:CharacterSet.whitespaces.union(CharacterSet(charactersIn:"\"'")))
    }
    static func result(_ code:Int32,visible:Bool,state:String="")->(String,String) {
        if !visible {return (code == 101 ? "delayed":"failed",code == 101 ? "No desktop session available":"Window did not report visible; no user choice was recorded")}
        switch code {
        case 0:
            if state=="preflightPower" {return ("completed","AC power detected; no installation choice inferred")}
            if ["rebootNudge","rebootForce","rebooting"].contains(state) {return ("completed","Restart result returned; button versus countdown is not distinguished")}
            if !["toast","softNudge","hardBlock","entraRegistration","appUpdates","updateRecovery"].contains(state) {return ("completed","Primary result returned; no user choice inferred")}
            let title=state=="updateRecovery" ? "Update now selected":state=="entraRegistration" ? "Register Now selected":(state=="appUpdates" ? "Update Closed Apps selected":"Install selected")
            return ("response",title)
        case 1:return ("response","Later selected")
        case 2:return ("response","Closed or dismissed")
        case 3:return ("response","Reminder schedule confirmed")
        case 4:return ("timeout","Power wait timed out")
        case 5:return ("timeout","Toast auto-dismissed")
        case 6:return ("response","Contact IT selected")
        case 7:return ("completed","Recovery countdown reached; this is not a user button choice")
        case 100:return ("timeout","Window appeared; no response before controller timeout")
        default:return ("failed","Prompt process failed; no user choice was recorded")
        }
    }
    static func retaining(_ events:[NotificationHistoryEvent],limit:Int=600)->[NotificationHistoryEvent] {Array(events.suffix(max(0,limit)))}
}
struct WallpaperDisplayRecord:Codable {
    var priorURL:String?
    var managedURL:String
    var scaling:Int?
    var clipping:Bool?
}
struct WallpaperUserDocument:Codable {var displays:[String:WallpaperDisplayRecord]=[:]}
struct WallpaperResult:Codable {
    var action:String
    var changed:Int
    var verified:Int
    var displays:Int
    var reason:String
}
enum WallpaperPolicy {
    static let managedDirectory="/Library/Management/PUSH/assets/wallpapers"
    static let defaultImage=managedDirectory+"/PUSH-NonCompliant.png"
    static func action(enabled:Bool,running:String,target:String)->String? {
        guard enabled,let current=version(running),let required=version(target) else{return nil}
        return current.lexicographicallyPrecedes(required) ? "enforce":"restore"
    }
    private static func version(_ text:String)->[Int]? {
        let pieces=text.split(separator:".",omittingEmptySubsequences:false)
        guard (1...3).contains(pieces.count),pieces.allSatisfy({!$0.isEmpty && $0.allSatisfy{$0.isASCII && $0.isNumber}}) else{return nil}
        let numbers=pieces.compactMap{Int($0)};guard numbers.count==pieces.count else{return nil}
        return numbers+Array(repeating:0,count:3-numbers.count)
    }
    static func shouldRestore(current:String,record:WallpaperDisplayRecord)->Bool {current == record.managedURL && record.priorURL != nil && record.priorURL != record.managedURL}
    static func assetName(digest:String,role:String)->String? {
        guard ["noncompliant","compliant"].contains(role),digest.count==64,digest.allSatisfy({$0.isHexDigit && !$0.isUppercase}) else{return nil}
        return role+"-"+digest+".png"
    }
}
