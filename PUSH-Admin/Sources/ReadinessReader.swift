// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import Darwin

/// Passive snapshot only. No CLI checks, Keychain access, prompts, or service mutations.
struct ReadinessReader {
    var base = "/Library/Management/PUSH"
    var daemonFolder = "/Library/LaunchDaemons"
    var uid = Int(getuid())
    var user = NSUserName()
    var now = Date()
    var query: (String) -> LaunchdObservation = ReadinessReader.inspectService
    static func inspectService(_ label: String) -> LaunchdObservation {
        guard ["com.push.autoupdate","com.push.entra-registration"].contains(label) else { return .init(loaded:nil,detail:"Unknown service") }
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("push-readiness-"+UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            defer { try? FileManager.default.removeItem(at:folder) }
            let file=folder.appendingPathComponent("service.txt")
            FileManager.default.createFile(atPath:file.path,contents:nil,attributes:[.posixPermissions:0o600])
            let handle=try FileHandle(forWritingTo:file);defer {try? handle.close()}
            let process=Process();process.executableURL=URL(fileURLWithPath:"/bin/launchctl");process.arguments=["print","system/"+label];process.standardOutput=handle;process.standardError=handle
            try process.run()
            let deadline=Date().addingTimeInterval(5)
            while process.isRunning && Date() < deadline {Thread.sleep(forTimeInterval:0.05)}
            if process.isRunning {process.terminate();kill(process.processIdentifier,SIGKILL);process.waitUntilExit();return .init(loaded:nil,detail:"Service inspection timed out")}
            let input=try FileHandle(forReadingFrom:file);defer{try? input.close()}
            let text=String(data:try input.read(upToCount:131072) ?? Data(),encoding:.utf8) ?? ""
            return .parse(exit:process.terminationStatus,text:text)
        } catch {return .init(loaded:nil,detail:"Service status is unavailable to this account")}
    }
    private func data(_ path: String) throws -> Data? {
        do {
            let input=try FileHandle(forReadingFrom:URL(fileURLWithPath:path));defer{try? input.close()}
            let value=try input.read(upToCount:2_097_153) ?? Data()
            guard value.count <= 2_097_152 else {throw CocoaError(.fileReadTooLarge)}
            return value
        } catch {
            let ns=error as NSError
            let underlying=ns.userInfo[NSUnderlyingErrorKey] as? NSError
            if (ns.domain == NSCocoaErrorDomain && [NSFileReadNoSuchFileError,NSFileNoSuchFileError].contains(ns.code)) || (ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT)) || (underlying?.domain == NSPOSIXErrorDomain && underlying?.code == Int(ENOENT)) {return nil}
            throw error
        }
    }
    private func read<T:Decodable>(_ name: String, as type:T.Type, issue:inout String?) -> T? {
        do {guard let bytes=try data(base+"/"+name) else{return nil};return try JSONDecoder().decode(type,from:bytes)}
        catch {issue="Saved \(name) is unreadable or invalid. No new check was run.";return nil}
    }
    func load() -> ReadinessSnapshot {
        var configIssue:String?,osIssue:String?,appsIssue:String?,entraIssue:String?
        var policy:InstalledPolicySummary?
        do {
            if let bytes=try data(base+"/config.yaml"),let text=String(data:bytes,encoding:.utf8),!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                guard ConfigDocument.load(text,name:"Installed policy").formatIssues.isEmpty else {throw CocoaError(.fileReadCorruptFile)}
                let known=["auto","apps","entra","update","debug","schedule"]
                var seen=Set<String>()
                for line in text.components(separatedBy:.newlines) where line.first?.isWhitespace == false && !line.hasPrefix("#") && !line.isEmpty {
                    let section=String(line.split(separator:":",maxSplits:1).first ?? "")
                    if known.contains(section) {
                        let suffix=String(line.dropFirst(section.count+1)).trimmingCharacters(in:.whitespaces)
                        guard (suffix.isEmpty || suffix.hasPrefix("#")),seen.insert(section).inserted else {throw CocoaError(.fileReadCorruptFile)}
                    }
                }
                guard !text.trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("{") else {throw CocoaError(.fileReadCorruptFile)}
                policy=InstalledPolicySummary(DashboardConfig.parse(yaml:text))
            } else if let bytes=try data(base+"/config.json") {policy=InstalledPolicySummary(try JSONDecoder().decode(DashboardConfig.self,from:bytes))}
            else {configIssue="No readable installed configuration was found. Review Deployment."}
        } catch {configIssue="The installed configuration could not be interpreted safely. Review it before enabling monitoring."}
        let os=read("state.json",as:DashboardOSState.self,issue:&osIssue)
        let apps=read("apps-state.json",as:DashboardAppState.self,issue:&appsIssue)
        let registration=read("entra-state.json",as:EntraNudgeState.self,issue:&entraIssue)
        let entra=registration?.users[String(uid)].flatMap{$0.userName == user ? $0:nil}
        var scheduled:[String:ObservedHealth]=[:],manual:[String:ObservedHealth]=[:]
        for module in ["macos","apps","entra"] {
            for source in ["scheduled","manual"] {
                var ignored:String?
                if let health=read("health/\(module)-\(source).json",as:ObservedHealth.self,issue:&ignored),health.module == module,health.source == source,module != "entra" || health.userUID == uid {
                    if source == "scheduled" {scheduled[module]=health}else{manual[module]=health}
                }
            }
        }
        func monitor(_ name:String,_ label:String,_ expected:Bool,_ fallback:Double,_ health:ObservedHealth?) -> MonitorReadiness {
            let path=daemonFolder+"/"+label+".plist"
            var definition:Bool?;var interval=fallback
            do {
                if let bytes=try data(path) {definition=true;if let dict=(try? PropertyListSerialization.propertyList(from:bytes,format:nil)) as? [String:Any],let number=dict["StartInterval"] as? Double,number>0 {interval=number}}
                else {definition=false}
            } catch {definition=nil}
            var ignored:String?
            let intent=read("health/intent-"+name+".json",as:ObservedIntent.self,issue:&ignored)
            return .evaluate(definition:definition,observed:query(label),intent:intent,health:health,interval:interval,now:now,expected:expected,dryRun:policy?.dryRun ?? false)
        }
        // The same launchd job runs app checks before macOS checks. Use the older
        // available module heartbeat so one healthy module cannot hide another.
        let availableHealth=[policy?.macEnabled == true ? scheduled["macos"]:nil,policy?.appsEnabled == true ? scheduled["apps"]:nil].compactMap{$0}.min{$0.updatedAt < $1.updatedAt}
        let expectedHealth = (policy?.macEnabled == true && scheduled["macos"] == nil) || (policy?.appsEnabled == true && scheduled["apps"] == nil) ? nil : availableHealth
        let main=monitor("main","com.push.autoupdate",policy?.macEnabled == true || policy?.appsEnabled == true,300,expectedHealth)
        let reg=monitor("entra","com.push.entra-registration",policy?.entraEnabled == true,300,scheduled["entra"])
        let version=Bundle(path:base+"/push-ui.app")?.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "Unknown"
        let osVersion=ProcessInfo.processInfo.operatingSystemVersion
        var snapshot = ReadinessSnapshot(capturedAt:now,engineVersion:version,engineInstalled:FileManager.default.isExecutableFile(atPath:base+"/push-cli"),policy:policy,configIssue:configIssue,os:os,osIssue:osIssue,apps:apps,appsIssue:appsIssue,entra:entra,entraIssue:entraIssue,mainMonitor:main,entraMonitor:reg,scheduled:scheduled,manual:manual,providerPresent:FileManager.default.fileExists(atPath:policy?.providerPath ?? ""),runningOS:"\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)")
        var preparationIssue:String?
        snapshot.preparation=read("preparation.json",as:DashboardPreparationState.self,issue:&preparationIssue)
        return snapshot
    }
}
