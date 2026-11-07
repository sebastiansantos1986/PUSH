// PUSH — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

enum UserRequests {
    static func result(_ request:UserUpdateRequest,_ message:String) {
        guard getuid()==0 else{return}
        let value=UserRequestResult(requestID:request.id,userUID:request.userUID,target:request.target,date:Date(),message:message)
        if let bytes=try? JSONEncoder().encode(value) {let path=managedBase+"/user-request-result.json";try? bytes.write(to:URL(fileURLWithPath:path),options:.atomic);try? FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:path)}
        NotificationHistory.record(state:"menuRequest",outcome:"completed",reason:message,uid:request.userUID,configuredTarget:request.target)
    }
    static func take(config:CLIConfig)->UserUpdateRequest? {
        guard let user=consoleUser() else{return nil}
        do {
            guard let request=try UserRequestChannel.consume(uid:user.uid) else{return nil}
            guard UUID(uuidString:request.id) != nil,RetryPolicy.version(request.target) != nil,request.userUID==user.uid else {
                NotificationHistory.record(state:"menuRequest",outcome:"failed",reason:"User request identity/target was invalid; no request content was executed",uid:user.uid);return nil
            }
            guard config.update.allowUserUpdateRequests,!config.debug.dryRun,UserUpdateRequest.valid(request,owner:user.uid,target:config.update.targetVersion,now:Date()) else {result(request,"Request was disabled, stale, or for a different target; no update started.");return nil}
            return request
        } catch {NotificationHistory.record(state:"menuRequest",outcome:"failed",reason:"A user request failed ownership, type, size or decoding checks; no action was started",uid:user.uid);return nil}
    }
}
