// PUSH — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit
import Foundation
import Darwin

// The UI target compiles the same configuration model as the CLI, without its
// command implementations. Loading it reads a local file only.
enum CLIError:Error {case configNotFound}
struct StatusSnapshot {
    var target="",running="",deadline:Date?,nextReminder:Date?
    var policyAvailable=false,enabled=false,dryRun=true,menuEnabled=true,requestsEnabled=false,pending=false
    var monitor:Bool?
    var recovery:InstallRecoveryRecord?
    var preparation:String?
    var progress:Double?
    var automaticRecoveryActive=false
    var issue:String?
    var lastCheckIssue:String?
    var helpURL:URL?
    var compliant:Bool {guard let a=RetryPolicy.version(running),let b=RetryPolicy.version(target) else{return false};return !a.lexicographicallyPrecedes(b)}
    var canRequest:Bool {UserUpdateRequest.allowed(policyAvailable:policyAvailable,enabled:enabled,dryRun:dryRun,requestsEnabled:requestsEnabled,pending:pending,monitor:monitor,target:target,running:running)}
    var title:String {
        if let issue {return issue}
        if !policyAvailable {return "Policy unavailable"}
        if pending {return "Installation pending verification"}
        if compliant {return "Your Mac meets the target"}
        if dryRun {return "PUSH is in dry-run mode"}
        if !enabled {return "macOS monitoring is disabled"}
        if monitor==false {return "Background monitor is stopped"}
        if monitor==nil {return "Background monitor state unknown"}
        if recovery?.phase=="failed" || recovery?.phase=="retrying" {return "Update needs attention"}
        return target.isEmpty ? "Waiting for a target":"macOS update required"
    }
    static func bytes(_ path:String,_ limit:Int=131072)->Data? {
        guard let file=try? FileHandle(forReadingFrom:URL(fileURLWithPath:path)) else{return nil};defer{try? file.close()}
        guard let data=try? file.read(upToCount:limit+1),data.count<=limit else{return nil};return data
    }
    static func monitorLoaded()->Bool? {
        let process=Process(),pipe=Pipe();process.executableURL=URL(fileURLWithPath:"/bin/launchctl");process.arguments=["print","system/com.push.autoupdate"];process.standardInput=FileHandle.nullDevice;process.standardOutput=pipe;process.standardError=pipe
        do{try process.run()}catch{return nil}
        let end=Date().addingTimeInterval(3)
        while process.isRunning && Date()<end {Thread.sleep(forTimeInterval:0.03)}
        if process.isRunning {process.terminate();kill(process.processIdentifier,SIGKILL);process.waitUntilExit();return nil}
        let output=String(decoding:pipe.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self)
        if process.terminationStatus==0{return true}
        return output.lowercased().contains("could not find service") ? false:nil
    }
    static func load()->Self {
        var snapshot=Self();let base="/Library/Management/PUSH"
        let os=ProcessInfo.processInfo.operatingSystemVersion;snapshot.running="\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        guard let cfg=try? CLIConfig.load(from:base+"/config.yaml") else {snapshot.issue="Installed policy could not be read";return snapshot}
        snapshot.policyAvailable=true;snapshot.enabled=cfg.auto.enabled;snapshot.dryRun=cfg.debug.dryRun;snapshot.menuEnabled=cfg.ui.menuBarEnabled;snapshot.requestsEnabled=cfg.update.allowUserUpdateRequests;snapshot.target=cfg.update.targetVersion;snapshot.deadline=ISO8601DateFormatter().date(from:cfg.effectiveDeadline)
        if !cfg.effectiveDeadline.isEmpty && snapshot.deadline==nil {snapshot.issue="Installed deadline is invalid";snapshot.requestsEnabled=false}
        if let data=bytes(base+"/state.json") {
            if let state=try? JSONDecoder().decode(CLIDeferralState.self,from:data){snapshot.pending=state.installStarted;snapshot.nextReminder=state.nextToastDate}
            else {snapshot.issue="Saved installation state needs IT review";snapshot.requestsEnabled=false}
        } else if FileManager.default.fileExists(atPath:base+"/state.json") {snapshot.issue="Saved installation state is unreadable";snapshot.requestsEnabled=false}
        if let data=bytes(base+"/install-recovery.json") {
            if let record=try? JSONDecoder().decode(InstallRecoveryRecord.self,from:data) {if RetryPolicy.same(record.target,snapshot.target){snapshot.recovery=record}}
            else {snapshot.issue="Saved recovery state needs IT review";snapshot.requestsEnabled=false}
        } else if FileManager.default.fileExists(atPath:base+"/install-recovery.json") {snapshot.issue="Saved recovery state is unreadable";snapshot.requestsEnabled=false}
        if let data=bytes(base+"/preparation.json"),let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],let phase=object["phase"] as? String {snapshot.preparation="Saved preparation: "+phase}
        for path in ["/private/var/run/com.push/install-progress","/private/var/run/com.push/download-progress"] {
            if let data=bytes(path,4096),let first=String(data:data,encoding:.utf8)?.split(separator:"\n").first,let number=Double(first),number.isFinite,(0...1).contains(number),let attributes=try? FileManager.default.attributesOfItem(atPath:path),let modified=attributes[.modificationDate] as? Date,Date().timeIntervalSince(modified)<120 {snapshot.progress=number;break}
        }
        let summaries=["scheduled","manual"].compactMap {source->(Date,String)? in
            guard let data=bytes(base+"/health/macos-"+source+".json"),let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],let stamp=object["updatedAt"] as? Double,let error=object["error"] as? String else{return nil}
            let time=Date(timeIntervalSinceReferenceDate:stamp)
            guard Date().timeIntervalSince(time)>=0,Date().timeIntervalSince(time)<3600 else{return nil}
            return (time,String(error.prefix(600)))
        }
        snapshot.lastCheckIssue=summaries.max{$0.0<$1.0}?.1
        snapshot.monitor=monitorLoaded()
        if let record=snapshot.recovery {
            snapshot.automaticRecoveryActive=snapshot.issue==nil && snapshot.enabled && snapshot.monitor==true && RetryPolicy.automaticAllowed(record,enabled:cfg.update.deadlineRecoveryEnabled,pastDeadline:cfg.isPastDeadline,dryRun:cfg.debug.dryRun,automaticInstall:cfg.update.autoInstallAfterDeadline || cfg.update.silentInstallAfterDeadline,limit:cfg.update.maxAutomaticRetriesPerDay,now:Date()) && RetryPolicy.noticeFresh(record,now:Date())
        }
        if let url=URL(string:cfg.ui.helpURL),url.scheme=="https" {snapshot.helpURL=url}
        else if !cfg.ui.itContactEmail.isEmpty {var parts=URLComponents();parts.scheme="mailto";parts.path=cfg.ui.itContactEmail;parts.queryItems=[.init(name:"subject",value:"PUSH update assistance")];snapshot.helpURL=parts.url}
        return snapshot
    }
}
@MainActor final class StatusMenuStore:ObservableObject {
    @Published var snapshot=StatusSnapshot()
    @Published var message="Reading local PUSH status…"
    private var refreshing=false
    private var timer:Timer?
    init(){refresh();timer=Timer.scheduledTimer(withTimeInterval:30,repeats:true){[weak self]_ in Task{@MainActor in self?.refresh()}}}
    func refresh() {
        guard !refreshing else{return};refreshing=true
        Task {
            let result=await Task.detached(priority:.utility){StatusSnapshot.load()}.value
            snapshot=result;refreshing=false
            if !result.menuEnabled {NSApplication.shared.terminate(nil);return}
            if let bytes=StatusSnapshot.bytes("/Library/Management/PUSH/user-request-result.json"),let ack=try? JSONDecoder().decode(UserRequestResult.self,from:bytes),ack.userUID==Int(getuid()),ack.requestID==UserDefaults.standard.string(forKey:"pendingRequestID"),Date().timeIntervalSince(ack.date)<900 {message=ack.message}
            else if let queued=UserDefaults.standard.object(forKey:"pendingRequestAt") as? Date,Date().timeIntervalSince(queued)<900,!result.compliant {message="Request queued for the next worker check. An active prompt or workflow can delay handling; use the current PUSH notice for an immediate response."}
            else {message="Local saved status. Actions are rechecked by the background worker; no password is collected here."}
        }
    }
    func submit(_ action:UserUpdateAction) {
        guard snapshot.canRequest else {message="The live policy or background worker is not ready for this request.";return}
        if action == .remindOneHour,snapshot.deadline.map({$0<=Date()})==true {message="The deadline has passed; scheduling cannot postpone enforcement.";return}
        do {
            let request=UserUpdateRequest(userUID:Int(getuid()),target:snapshot.target,action:action,issuedAt:Date())
            try UserRequestChannel.write(request)
            UserDefaults.standard.set(request.id,forKey:"pendingRequestID")
            UserDefaults.standard.set(Date(),forKey:"pendingRequestAt")
            message="Request queued. PUSH will revalidate it on the next background check (normally every five minutes; active work or a prompt can delay handling). This is not confirmation that installation started."
        }catch{message="The request could not be queued. Contact IT; no installation was started."}
    }
}
struct PushStatusApp:App {
    @StateObject private var store=StatusMenuStore()
    var body:some Scene {
        MenuBarExtra {
            StatusMenuView().environmentObject(store)
        } label:{Image(systemName:store.snapshot.compliant ? "checkmark.circle":"arrow.down.circle")}
        .menuBarExtraStyle(.window)
    }
}
struct StatusMenuView:View {
    @EnvironmentObject var store:StatusMenuStore
    @State private var confirm=false
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack{Label("PUSH",systemImage:"arrow.down.circle.fill").font(.headline);Spacer();Button{store.refresh()}label:{Image(systemName:"arrow.clockwise")}.buttonStyle(.plain)}
            Text(store.snapshot.title).font(.title3.bold())
            LabeledContent("Running macOS",value:store.snapshot.running)
            LabeledContent("Required",value:store.snapshot.target.isEmpty ? "Not selected":store.snapshot.target)
            if !store.snapshot.compliant,!store.snapshot.pending,let next=store.snapshot.nextReminder {LabeledContent("Next toast",value:next>Date() ? next.formatted(date:.abbreviated,time:.shortened):"Due at next eligible check")}
            if let deadline=store.snapshot.deadline {LabeledContent("Deadline",value:deadline.formatted(date:.abbreviated,time:.shortened))}
            if let progress=store.snapshot.progress {ProgressView(value:progress);Text("Saved progress: \(Int(progress*100))%").font(.caption).foregroundStyle(.secondary)}
            if let preparation=store.snapshot.preparation {Text(preparation).font(.caption).foregroundStyle(.secondary)}
            if let failure=store.snapshot.recovery {
                Text(failure.phase=="awaitingVerification" ? "A new attempt is awaiting verification. Previous issue: "+failure.reason:failure.reason).font(.callout).foregroundStyle(.orange)
                if store.snapshot.automaticRecoveryActive,let retry=failure.retryAt,abs(retry.timeIntervalSinceNow)<604800 {
                    TimelineView(.periodic(from:.now,by:1)){context in
                        let remaining=Int(ceil(min(86400,max(0,retry.timeIntervalSince(context.date)))))
                        Text(remaining>0 ? String(format:"Next eligible retry: %02d:%02d",remaining/60,remaining%60):"Retry time reached; worker will recheck safety").font(.caption.monospaced())
                    }
                }
            }
            if store.snapshot.recovery == nil,let issue=store.snapshot.lastCheckIssue {Text("Last saved check issue: "+issue).font(.caption).foregroundStyle(.orange)}
            Text(store.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Divider()
            Button("Request update now…"){confirm=true}.buttonStyle(.borderedProminent).disabled(!store.snapshot.canRequest)
            Button("Remind me in one hour"){store.submit(.remindOneHour)}.disabled(!store.snapshot.canRequest || store.snapshot.deadline.map{$0<=Date()}==true)
            Button("Show current PUSH notice"){if let app=NSRunningApplication.runningApplications(withBundleIdentifier:"com.push.push-ui").first{app.activate(options:.activateIgnoringOtherApps)}else{store.message="There is no active PUSH notice. The background worker will recheck eligibility."}}
            Button("Open Software Update"){if let url=URL(string:"x-apple.systempreferences:com.apple.Software-Update-Settings.extension"){NSWorkspace.shared.open(url)}}
            if let help=store.snapshot.helpURL {Button("Contact IT"){NSWorkspace.shared.open(help)}}
            Text("Quitting this menu does not pause managed updates.").font(.caption2).foregroundStyle(.secondary)
            Button("Quit status menu"){NSApplication.shared.terminate(nil)}.font(.caption)
        }.padding(20).frame(width:390)
        .confirmationDialog("Request the configured macOS update?",isPresented:$confirm,titleVisibility:.visible){Button("Request update"){store.submit(.install)};Button("Cancel",role:.cancel){}}message:{Text("PUSH will recheck the target, authorization and safety conditions on its next cycle. Save your work: an accepted update can download macOS, close apps and restart this Mac.")}
    }
}
