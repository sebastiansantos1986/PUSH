// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit

struct RecoverySettingsPage:View {
    @EnvironmentObject var store:AdminStore
    @State private var blocked=false
    @State private var revision=UUID()
    private func flag(_ key:String)->Binding<Bool> {Binding(get:{store.document.setupFlag(key)},set:{store.document.edits[key]=$0 ? "true":"false"})}
    private func number(_ key:String,_ fallback:Int)->Binding<Int> {Binding(get:{Int(store.document.setupValue(key)) ?? fallback},set:{store.document.edits[key]=String($0)})}
    private var sample:RecoveryNotice {
        .init(target:store.document.setupValue("update.targetVersion").isEmpty ? "27.2":store.document.setupValue("update.targetVersion"),reason:blocked ? "Unattended installation authorization is not configured. IT must provision it before an update can start.":"The previous download could not finish because the network was unavailable.",retryAt:blocked ? nil:Date().addingTimeInterval(30),automatic:!blocked,explanation:"SIMULATED · Update now and the 30-second sample countdown never run a download, update or restart.")
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                PageHeading(eyebrow:"User status & recovery",title:"Explain the problem. Make the next step clear.",subtitle:"Configure the menu-bar status and guarded retries after a missed deadline. This page changes a draft only.")
                AdminCard {
                    Toggle("Show PUSH status inside JamfCheckIn",isOn:flag("ui.menuBarEnabled"))
                    Toggle("Allow users to request the configured update",isOn:flag("update.allowUserUpdateRequests"))
                    Text("JamfCheckIn runs without root privileges. It reads saved local status and queues typed requests; the privileged worker revalidates the target, user, policy and safety conditions. A queued request is not an installation success.").font(.callout).foregroundStyle(.secondary)
                    Button("Open JamfCheckIn"){NSWorkspace.shared.open(URL(fileURLWithPath:"/Applications/JamfCheckIn.app"))}.disabled(!FileManager.default.fileExists(atPath:"/Applications/JamfCheckIn.app"))
                    Text("The client login agent opens JamfCheckIn at future graphical logins. This setting controls its PUSH card; other JamfCheckIn features remain available.").font(.caption).foregroundStyle(.secondary)
                }
                AdminCard {
                    Toggle("Enable deadline failure recovery",isOn:flag("update.deadlineRecoveryEnabled"))
                    Stepper("First countdown: \(store.document.setupValue("update.retryCountdownMinutes")) minutes",value:number("update.retryCountdownMinutes",10),in:1...60)
                    Stepper("Minimum spacing after an automatic retry: \(store.document.setupValue("update.retryBackoffMinutes")) minutes",value:number("update.retryBackoffMinutes",30),in:5...240)
                    Stepper("Automatic recovery attempts per rolling 24 hours: \(store.document.setupValue("update.maxAutomaticRetriesPerDay"))",value:number("update.maxAutomaticRetriesPerDay",3),in:0...6)
                    Text("Automatic retries also require an enabled live macOS policy, a passed deadline and an automatic-install choice. Authorization, disk, power, DDM, meetings and competing-installer checks still apply. Closing a notice does not restart its saved clock.").font(.callout).foregroundStyle(.secondary)
                    Text("Missing authorization, untrusted installers and damaged state need IT attention. No countdown claims to bypass those conditions. Repeated temporary failures use spacing and a daily attempt budget.").font(.caption).foregroundStyle(.secondary)
                }
                AdminCard {
                    Label("Safe recovery preview",systemImage:"rectangle.on.rectangle").font(.headline)
                    Toggle("Simulate an IT-only blocker",isOn:$blocked)
                    Button("Reset 30-second sample"){revision=UUID()}
                    StudioPreview(state:.updateRecovery,yaml:store.previewYAML,progress:0,deferrals:0,logoData:store.document.logoImageData,chooseLogo:{store.choosePopupLogo()},recoveryNotice:sample)
                        .id(store.previewYAML+String(blocked)+revision.uuidString).frame(height:840)
                    Text("Preview only. The sample clock is not your live policy countdown.").font(.caption).foregroundStyle(.secondary)
                }
                ValidationSummary()
            }.padding(28).frame(maxWidth:1200,alignment:.leading)
        }
    }
}
