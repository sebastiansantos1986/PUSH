// PUSH — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import Darwin

enum InstallRecoveryStore {
    static let path=managedBase+"/install-recovery.json"
    static func load()throws->InstallRecoveryRecord? {
        guard FileManager.default.fileExists(atPath:path) else{return nil}
        let data=try Data(contentsOf:URL(fileURLWithPath:path));guard data.count<=131072 else {throw CLIError.invalidValue("Recovery record is oversized")}
        return try JSONDecoder().decode(InstallRecoveryRecord.self,from:data)
    }
    @discardableResult static func update(expectedID:String?=nil,_ body:(inout InstallRecoveryRecord?)->Void)->Bool {
        guard getuid()==0 else{return false}
        var info=stat();guard lstat(managedBase,&info)==0,info.st_uid==0,info.st_mode&S_IFMT==S_IFDIR,info.st_mode&0o022==0 else{return false}
        let lock=open(managedBase+"/install-recovery.lock",O_CREAT|O_RDWR|O_NOFOLLOW,0o600)
        guard lock>=0 else{return false};defer{close(lock)}
        guard flock(lock,LOCK_EX|LOCK_NB)==0 else{return false};defer{flock(lock,LOCK_UN)}
        do {
            var record=try load();if let expectedID,record?.id != expectedID {return false};body(&record)
            if let record {
                try JSONEncoder().encode(record).write(to:URL(fileURLWithPath:path),options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:path)
            } else {try? FileManager.default.removeItem(atPath:path)}
            return true
        }catch{return false}
    }
    static func failure(config:CLIConfig,message:String) {
        guard config.isPastDeadline,config.update.deadlineRecoveryEnabled,!config.debug.dryRun else{return}
        let safe=String(RuntimeHealthScope.clean(message).prefix(600))
        _=update{record in
            let prior=record.flatMap{RetryPolicy.same($0.target,config.update.targetVersion) ? $0:nil}
            record=InstallRecoveryRecord(target:config.update.targetVersion,reason:safe,kind:.classify(safe),failedAt:Date(),automaticAttempts:prior?.automaticAttempts ?? [])
        }
        RuntimeHealthScope.note(safe,error:true)
        NotificationHistory.record(state:"updateRecovery",outcome:"failed",reason:safe)
    }
    static func staged(target:String) {_=update{record in if record.map({RetryPolicy.same($0.target,target)}) == true {record?.phase="awaitingVerification";record?.retryAt=nil}}}
    static func resolve(running:String) {_=update{record in
        if let target=record?.target,let current=RetryPolicy.version(running),let required=RetryPolicy.version(target),!current.lexicographicallyPrecedes(required) {record=nil}
    }}
}
enum RecoveryDecision {case none,wait,retry(automatic:Bool,id:String)}
struct DeadlineRecoveryController {
    let config:CLIConfig
    func review()->RecoveryDecision {
        guard config.update.deadlineRecoveryEnabled,config.isPastDeadline,!config.debug.dryRun else{return .none}
        let loaded:InstallRecoveryRecord?
        do {loaded=try InstallRecoveryStore.load()}catch{cliError("Saved recovery state is unreadable. IT must review it before retrying.");return .wait}
        guard var record=loaded,RetryPolicy.same(record.target,config.update.targetVersion),["failed","retrying"].contains(record.phase) else{return .none}
        if record.phase=="retrying" {
            record.phase="failed";record.retryAt=nil;record.noticeShownAt=nil
            let repaired=record
            guard InstallRecoveryStore.update(expectedID:repaired.id,{stored in if stored?.id==repaired.id {stored=repaired}}) else{return .wait}
        }
        let now=Date(),automatic=RetryPolicy.automaticAllowed(record,enabled:config.update.deadlineRecoveryEnabled,pastDeadline:config.isPastDeadline,dryRun:config.debug.dryRun,automaticInstall:config.update.autoInstallAfterDeadline || config.update.silentInstallAfterDeadline,limit:config.update.maxAutomaticRetriesPerDay,now:now)
        if automatic,RetryPolicy.canRetryNow(record,automatic:true,now:now) {return .retry(automatic:true,id:record.id)}
        if automatic,RetryPolicy.noticeFresh(record,now:now),let retry=record.retryAt,retry>now {cliPrint("Saved recovery countdown is pending; closing the window does not restart it.");return .wait}
        if !automatic,let last=record.lastNoticeAt,now.timeIntervalSince(last)<3600 {cliPrint("Recovery requires IT, an explicit retry, or a later retry budget. No repeated countdown started.");return .wait}
        guard userIsLoggedIn() else{return .wait}
        let binary=resolveUIBinary(),bundle=binary.components(separatedBy:"/Contents/MacOS/").first ?? ""
        guard let version=Bundle(path:bundle)?.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String,versionGTE(version,"1.9.0") else {
            cliError("Deadline recovery needs the matching 1.9.0 or later popup app. No automatic retry was started.");return .wait
        }
        if automatic {record.retryAt=RetryPolicy.nextTime(record,countdownMinutes:config.update.retryCountdownMinutes,backoffMinutes:config.update.retryBackoffMinutes,now:now)}else{record.retryAt=nil}
        let id=record.id,proposed=record.retryAt
        guard InstallRecoveryStore.update(expectedID:id,{stored in if stored?.id==id {stored?.retryAt=proposed;stored?.noticeShownAt=nil}}) else{return .wait}
        let note=RecoveryNotice(target:record.target,reason:record.reason,retryAt:record.retryAt,automatic:automatic,explanation:automatic ? "Choose Update now, or PUSH will recheck and retry when this countdown ends. Closing this window does not postpone the retry. Authorization and safety checks still apply.":"This condition needs IT attention, an explicit retry after the issue is fixed, or a renewed retry budget. No automatic countdown can bypass it.")
        guard let bytes=try? JSONEncoder().encode(note),let cfgPath=resolvedConfigPath else{return .wait}
        shell("pkill -x push-ui 2>/dev/null || true")
        let timeout=automatic ? min(241,max(2,Int(ceil((note.retryAt?.timeIntervalSinceNow ?? 600)/60))+1)):15
        let response=runUIBlocking(shellArgument(resolveUIBinary())+" --state updateRecovery --config "+shellArgument(cfgPath)+" --recovery-payload "+shellArgument(bytes.base64EncodedString()),timeoutMinutes:timeout,onDisplayed:{
            _=InstallRecoveryStore.update(expectedID:id){stored in if stored?.id==id {stored?.noticeShownAt=Date();stored?.lastNoticeAt=Date()}}
        })
        if response==0 {return .retry(automatic:false,id:id)}
        if automatic,let fresh=try? InstallRecoveryStore.load(),fresh.id==id,RetryPolicy.canRetryNow(fresh,automatic:true,now:Date()) {return .retry(automatic:true,id:id)}
        return .wait
    }
}
