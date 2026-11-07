// PUSH — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import Darwin

enum NotificationHistory {
    static func record(state:String,outcome:String,reason:String,code:Int32?=nil,attempt:String=UUID().uuidString,mode:String?=nil,uid:Int?=nil,retry:Date?=nil,configuredTarget:String?=nil) {
        guard getuid()==0 else{return}
        var base=stat()
        guard lstat(managedBase,&base)==0,base.st_uid==0,base.st_mode&S_IFMT==S_IFDIR,base.st_mode&0o022==0 else{return}
        let lock=open(managedBase+"/notification-history.lock",O_CREAT|O_RDWR|O_NOFOLLOW,0o600)
        guard lock>=0 else{return};defer{close(lock)}
        guard flock(lock,LOCK_EX|LOCK_NB)==0 else{return};defer{flock(lock,LOCK_UN)}
        let path=URL(fileURLWithPath:managedBase+"/notification-history.json")
        var history=NotificationHistoryDocument()
        if FileManager.default.fileExists(atPath:path.path) {
            guard let bytes=try? Data(contentsOf:path),bytes.count<=1_048_576,let decoded=try? JSONDecoder().decode(NotificationHistoryDocument.self,from:bytes) else{return}
            history=decoded
        }
        let source=mode ?? RuntimeHealthScope.currentSource
        let cleaned=RuntimeHealthScope.clean(reason)
        if ["delayed","failed"].contains(outcome),let last=history.events.last,last.state==state,last.outcome==outcome,last.reason==cleaned,last.mode==source,Date().timeIntervalSince(last.date)<900 {return}
        let rawTarget=["appUpdates","entraRegistration"].contains(state) ? nil:(configuredTarget ?? (try? loadConfig())?.update.targetVersion)
        let target=rawTarget.flatMap{numericOSVersion($0) != nil ? $0:nil}
        history.events.append(.init(attempt:attempt,date:Date(),state:String(state.prefix(50)),mode:source,outcome:outcome,reason:cleaned,code:code,userUID:uid,target:target,retryAt:retry))
        history.events=NotificationHistoryPolicy.retaining(history.events)
        if let bytes=try? JSONEncoder().encode(history) {do{try bytes.write(to:path,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:path.path)}catch{}}
    }
}
final class NotificationAttempt {
    let id=UUID().uuidString,state:String,mode:String,uid:Int?
    var visible=false
    let target:String?
    init(command:String,uid:Int?) {
        state=NotificationHistoryPolicy.state(in:command);target=(try? loadConfig())?.update.targetVersion;mode=command.contains("--manual-test") ? "preview":RuntimeHealthScope.currentSource;self.uid=uid
        NotificationHistory.record(state:state,outcome:"requested",reason:"Prompt requested; delivery is not yet confirmed",attempt:id,mode:mode,uid:uid,configuredTarget:target)
    }
    func displayed() {
        guard !visible else{return};visible=true
        NotificationHistory.record(state:state,outcome:"displayed",reason:"Window reported visible in the desktop session",attempt:id,mode:mode,uid:uid,configuredTarget:target)
    }
    func finish(_ code:Int32)->Int32 {
        let result=NotificationHistoryPolicy.result(code,visible:visible,state:state)
        NotificationHistory.record(state:state,outcome:result.0,reason:result.1,code:code,attempt:id,mode:mode,uid:uid,retry:["failed","delayed"].contains(result.0) ? Date().addingTimeInterval(300):nil,configuredTarget:target)
        return RuntimeHealthScope.uiResult(code)
    }
}
