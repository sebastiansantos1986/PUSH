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

// LaunchServices does not return the application's button exit code. Use an
// attempt-bound receipt; a successful open(1) exit is never installation consent.
struct PopupResultReceipt:Codable {
    let version:Int
    let session:String
    let code:Int32
    static func decode(_ data:Data,session:String)->Int32? {
        guard data.count<=4096,let value=try? JSONDecoder().decode(Self.self,from:data),value.version==1,value.session==session,([0,1,2,3,4,5,6,7,99] as [Int32]).contains(value.code) else{return nil}
        return value.code
    }
}
enum PopupLaunchProtocol {
    static func openCommand(command:String,binary:String,ready:String,result:String,output:String?=nil)->String? {
        let quote:(String)->String={"'"+$0.replacingOccurrences(of:"'",with:"'\\''")+"'"}
        let prefixes=[quote(binary),"\""+binary+"\"",binary]
        guard let prefix=prefixes.first(where:{command==$0 || command.hasPrefix($0+" ")}),let split=binary.range(of:"/Contents/MacOS/"),binary[..<split.lowerBound].hasSuffix(".app") else{return nil}
        let app=String(binary[..<split.lowerBound])
        let arguments=String(command.dropFirst(prefix.count))
        let logs=output.map{" --stdout "+quote($0)+" --stderr "+quote($0)} ?? ""
        return "exec /usr/bin/open -n"+logs+" "+quote(app)+" --args"+arguments+" --ready-file "+quote(ready)+" --result-file "+quote(result)
    }
}

// Launcher completion and popup completion are independent. LaunchServices may
// return before a window exists; only an acknowledged, valid receipt is a choice.
enum PopupSessionDecision:Equatable {case wait,finish(Int32)}
enum PopupSessionPolicy {
    static func decision(visible:Bool,receipt:Int32?,launcherFailure:Bool,startupExpired:Bool,responseExpired:Bool)->PopupSessionDecision {
        if let receipt {return .finish(visible ? receipt:103)}
        if launcherFailure {return .finish(99)}
        if !visible && startupExpired {return .finish(103)}
        if responseExpired {return .finish(100)}
        return .wait
    }
}

/// Display copy is separate from installer/progress data. Templates never execute.
enum DownloadWording {
    static let header="Download in Progress"
    static let title="Downloading {macOS}"
    static let message="You can keep working while your update downloads."
    static let footer="Keep your Mac connected to power and the internet. Do not shut down or close the lid."
    static func label(name:String,version:String)->String {
        let clean=name.trimmingCharacters(in:.whitespacesAndNewlines)
        let os=clean.isEmpty ? "macOS":clean
        let target=version.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !target.isEmpty else{return os}
        var words=os.split(whereSeparator:{$0.isWhitespace}).map(String.init)
        if let last=words.last,last.range(of:#"^[0-9]+(?:\.[0-9]+){0,2}$"#,options:.regularExpression) != nil,
           last.split(separator:".").first==target.split(separator:".").first {
            words.removeLast();return (words+[target]).joined(separator:" ")
        }
        return os+" "+target
    }
    static func render(_ template:String,name:String,version:String,fallback:String="")->String {
        let source=template.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? fallback:template
        let tokens=["macOS":label(name:name,version:version),"version":version,"osName":name.isEmpty ? "macOS":name]
        // One pass prevents token-like text inside an admin name from being expanded again.
        guard let regex=try? NSRegularExpression(pattern:#"\{(macOS|version|osName)\}"#) else{return source}
        var result=source
        for match in regex.matches(in:source,range:NSRange(source.startIndex...,in:source)).reversed() {
            guard let range=Range(match.range,in:result),let keyRange=Range(match.range(at:1),in:source),let value=tokens[String(source[keyRange])] else{continue}
            result.replaceSubrange(range,with:value)
        }
        return result
    }
}
