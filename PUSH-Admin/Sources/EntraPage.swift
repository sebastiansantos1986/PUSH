// PUSH Admin — Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit

struct EntraPage: View {
    @EnvironmentObject var store: AdminStore
    @State private var stage = 1
    @State private var refresh = UUID()
    private func resolved(_ key: String) -> String {
        if let field = configGroups.flatMap(\.fields).first(where: { $0.id == key }) { return store.document.value(field) }
        return store.document.value(key) ?? ""
    }
    private func value(_ key: String) -> Binding<String> { Binding(get:{resolved(key)},set:{store.document.edits[key]=$0}) }
    private func flag(_ key: String) -> Binding<Bool> { Binding(get:{resolved(key)=="true"},set:{store.document.edits[key]=$0 ? "true":"false"}) }
    private var saved: EntraUserState? {
        guard let data = FileManager.default.contents(atPath:"/Library/Management/PUSH/entra-state.json"), let state = try? JSONDecoder().decode(EntraNudgeState.self,from:data), let user = state.users[String(getuid())], user.userName == NSUserName() else { return nil }
        return user
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                PageHeading(eyebrow:"IDENTITY READINESS",title:"Registration nudges that know when to stop.",subtitle:"Guide users into your existing Jamf Self Service registration policy. Recheck local evidence, cap reminders, and explain why a prompt was skipped.")
                AdminCard {
                    Label("Saved result for this user",systemImage:"person.crop.circle.badge.checkmark").font(.headline)
                    LabeledContent("Local registration",value:saved?.status.title ?? "Not checked")
                    LabeledContent("Cloud compliance",value:"Not assessed")
                    LabeledContent("Last checked",value:saved?.checkedAt.map { $0.formatted(date:.abbreviated,time:.shortened) } ?? "Never")
                    LabeledContent("Later / closed / timed out",value:"\(saved?.laterCount ?? 0) / \(saved?.closedCount ?? 0) / \(saved?.timedOutCount ?? 0)")
                    Text(saved?.nextReason ?? "Enable and apply the policy, then run an Entra check on an enrolled test Mac.").font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Refresh saved result") { refresh = UUID() }
                        Button("Copy check command") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("sudo /Library/Management/PUSH/push-cli entra check",forType:.string);store.notice="Copied the local-evidence check command. It does not prompt users, open Self Service, or run inventory sync." }
                    }
                }
                AdminCard {
                    Label("Set up the registration workflow",systemImage:"slider.horizontal.3").font(.headline)
                    Toggle("Enable Entra registration reminders",isOn:flag("entra.enabled"))
                    TextField("Self Service registration policy ID",text:value("entra.policyID")).textFieldStyle(.roundedBorder)
                    HStack {
                        Stepper("From \(resolved("entra.startHour")):00",value:Binding(get:{Int(resolved("entra.startHour")) ?? 8},set:{value("entra.startHour").wrappedValue=String($0)}),in:0...23)
                        Spacer()
                        Stepper("Until \(resolved("entra.endHour")):00",value:Binding(get:{Int(resolved("entra.endHour")) ?? 18},set:{value("entra.endHour").wrappedValue=String($0)}),in:1...24)
                    }
                    Toggle("Weekdays only",isOn:flag("entra.weekdaysOnly"))
                    Toggle("Wait during meetings and screen sharing",isOn:flag("entra.skipMeetings"))
                    Toggle("Refresh Jamf inventory after a registration transition",isOn:flag("entra.reconOnRegistration"))
                    Text("Register Now opens this policy; it does not mark registration complete. Only a fresh local registration check stops reminders. Setup failures and uncertain evidence are shown to IT rather than repeatedly prompting users.").font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Advanced paths & message") {
                        VStack(spacing:12) {
                            TextField("Self Service app",text:value("entra.selfServicePath"))
                            TextField("Company Portal app",text:value("entra.companyPortalPath"))
                            TextField("Jamf binary",text:value("entra.jamfBinaryPath"))
                            TextField("Optional custom message · blank uses stage messages",text:value("entra.message"),axis:.vertical).lineLimit(3...7)
                        }.textFieldStyle(.roundedBorder).padding(.top,12)
                    }
                }
                AdminCard {
                    Label("Four stages, bounded reminders",systemImage:"bell.badge").font(.headline)
                    ForEach(1...4,id:\.self) { number in
                        let policy = EntraPolicy.stage(laterCount:[0,4,8,12][number-1])
                        HStack { Text("Stage \(number)").font(.callout.weight(.semibold)); Spacer(); Text("Up to \(policy.cap)/day · at least \(Int(policy.gap/60)) minutes apart").font(.caption).foregroundStyle(.secondary) }
                    }
                    Text("Only an explicit Later click advances escalation. Closing, timing out, and opening Self Service have separate counters. The monitor checks every 5 minutes; it does not show a prompt every 5 minutes.").font(.caption).foregroundStyle(.secondary)
                }
                AdminCard {
                    Label("Preview the registration reminder",systemImage:"rectangle.on.rectangle").font(.headline)
                    Picker("Stage",selection:$stage) { ForEach(1...4,id:\.self) { Text("Stage \($0)").tag($0) } }.pickerStyle(.segmented)
                    StudioPreview(state:.entraRegistration,yaml:store.document.yaml,progress:0,deferrals:0,logoData:store.document.logoImageData,chooseLogo:{store.choosePopupLogo()},entraNotice:store.document.entraPreviewNotice(stage:stage))
                        .id(store.document.yaml + String(stage)).frame(height:600)
                    Text("Preview buttons are simulated: no Self Service, Microsoft sign-in, email, or Jamf inventory operation is started.").font(.caption).foregroundStyle(.secondary)
                }
                AdminCard {
                    Label("Deployment readiness",systemImage:"checkmark.shield").font(.headline)
                    Text("This release supports the Jamf device-registration workflow using the current user's jamfAAD preference. It does not treat Platform SSO, a certificate, or an old marker as proof of Jamf registration or cloud compliance.").font(.callout).foregroundStyle(.secondary)
                    Text("Apply your draft in Deployment, then enable monitoring. Production nudges require MDM enrollment, Jamf, Company Portal, and the legacy Jamf Self Service app. Disable the old registration reminder policy to avoid duplicate prompts. Unenrolled Macs remain inactive; previews are available anywhere.").font(.caption).foregroundStyle(.secondary)
                }
                ValidationSummary()
            }.padding(28).id(refresh)
        }
    }
}
