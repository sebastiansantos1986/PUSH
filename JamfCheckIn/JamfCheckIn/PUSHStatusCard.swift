// PUSH — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit

struct PUSHStatusCard:View {
    @ObservedObject var store:StatusMenuStore
    @State private var confirm=false
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack{Label("PUSH",systemImage:"arrow.down.circle.fill").font(.headline);Spacer();Button{store.refresh()}label:{Image(systemName:"arrow.clockwise")}.buttonStyle(.plain)}
            Text(store.snapshot.title).font(.title3.bold())
            if !store.snapshot.protocolReady {Text("Install the matching PUSH Client package to enable guarded update requests.").font(.caption).foregroundStyle(.secondary)}
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
            Text("PUSH manages updates independently of this menu.").font(.caption2).foregroundStyle(.secondary)
        }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius:12))
        .confirmationDialog("Request the configured macOS update?",isPresented:$confirm,titleVisibility:.visible){Button("Request update"){store.submit(.install)};Button("Cancel",role:.cancel){}}message:{Text("PUSH will recheck the target, authorization and safety conditions on its next cycle. Save your work: an accepted update can download macOS, close apps and restart this Mac.")}
    }
}
