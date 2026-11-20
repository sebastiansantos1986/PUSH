// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit

struct WorkflowBuilderPage:View {
    @EnvironmentObject var store:AdminStore
    var navigate:(AdminPage)->Void
    @State private var step:WorkflowStep = .goal
    @State private var selectedMessage:WorkflowMessage = .toast
    @State private var signedClient:URL?
    @State private var signedRestartIdentity:RestartProfileIdentity?
        private var recipe:WorkflowRecipe {WorkflowRecipe.from(document:store.document)}
    private var proposal:ConfigDocument {recipe.proposed(from:store.document)}
    private var issues:[String] {recipe.issues()+proposal.problems}
    private func binding<T>(_ path:WritableKeyPath<WorkflowRecipe,T>)->Binding<T> {Binding(get:{recipe[keyPath:path]},set:{var next=recipe;next[keyPath:path]=$0;if !(next.isOSWorkflow && next.target == .major && next.major==26){next.includeTahoeAudit=false};if !next.isOSWorkflow {next.includeTahoeAudit=false};store.document.workflowRecipe=next})}
    private func task(_ item:WorkflowTask)->Binding<Bool> {Binding(get:{recipe.tasks.contains(item)},set:{on in var next=recipe;if on {next.tasks.insert(item);if item == .wallpaper {next.tasks.insert(.macOS)}}else{next.tasks.remove(item);if item == .macOS {next.tasks.remove(.wallpaper)}};store.document.workflowRecipe=next})}
    private func app(_ id:String)->Binding<Bool> {Binding(get:{recipe.approvedApps.contains(id)},set:{on in var next=recipe;if on {next.approvedApps.insert(id)}else{next.approvedApps.remove(id)};store.document.workflowRecipe=next})}
    var body:some View {
        ScrollViewReader {proxy in
        ScrollView {VStack(alignment:.leading,spacing:22) {
            PageHeading(eyebrow:"Create workflow",title:"Tell PUSH what you want done.",subtitle:"Choose a goal, customize the user experience, simulate it, check readiness and build one configured installer.").id("workflow-top")
            WorkflowLibraryBar()
            HStack {ForEach(WorkflowStep.allCases){item in Button {step=item} label:{Text("\(item.rawValue+1). \(item.title)").fontWeight(step==item ? .semibold:.regular).frame(maxWidth:.infinity).padding(10).background(step==item ? Color.blue.opacity(0.12):Color.secondary.opacity(0.05),in:RoundedRectangle(cornerRadius:8))}.buttonStyle(.plain)}}
            if step == .goal {chooseTasks}
            if step == .customize {
                if recipe.isOSWorkflow {
                    HStack {Button("Messages & icon"){proxy.scrollTo("workflow-messages",anchor:.top)};Button("Deadline & update rules"){proxy.scrollTo("workflow-question",anchor:.top)}}
                    messageAndPreview.id("workflow-messages")
                }
                Text("Deadline and update rules").font(.title2.bold()).id("workflow-question")
                WorkflowAssistantCard(recipe:Binding(get:{recipe},set:{store.document.workflowRecipe=$0}),navigate:navigate,focusQuestion:{withAnimation {proxy.scrollTo("workflow-question",anchor:.top)}},skipPresentationQuestions:recipe.isOSWorkflow)
                DisclosureGroup("All settings (advanced)"){rules}
            }
            if step == .simulate {WorkflowSimulationPage(embedded:true)}
            if step == .readiness {readiness}
            if step == .build {review}
            HStack {Button("Back"){step=WorkflowStep(rawValue:max(0,step.rawValue-1)) ?? .goal;proxy.scrollTo("workflow-top",anchor:.top)}.disabled(step == .goal);Spacer();Text("Saved draft · nothing is deployed").font(.caption).foregroundStyle(.secondary);if step != .build {Button("Continue to "+(WorkflowStep(rawValue:step.rawValue+1)?.title ?? "Build")){step=WorkflowStep(rawValue:step.rawValue+1) ?? .build;proxy.scrollTo("workflow-top",anchor:.top)}.buttonStyle(.borderedProminent)}}
        }.padding(28).frame(maxWidth:1200,alignment:.leading)}
        .onChange(of:step){_,_ in proxy.scrollTo("workflow-top",anchor:.top)}
        .onAppear {if store.document.workflowRecipe == nil {store.document.workflowRecipe=WorkflowRecipe.from(document:store.document)}}
        }
    }
    private var chooseTasks:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Combine the tasks you need.").font(.title2.bold())
            ForEach(WorkflowTask.allCases){item in AdminCard {Toggle(isOn:task(item)){Label(item.title,systemImage:item.icon).font(.headline)};Text(item.detail).font(.callout).foregroundStyle(.secondary)}}
            if recipe.isOSWorkflow {AdminCard {
                Text("Which macOS should these Macs run?").font(.headline)
                Picker("Update goal",selection:binding(\.target)){ForEach(WorkflowTarget.allCases){Text($0.title).tag($0)}}
                if recipe.target == .major {Picker("Generation",selection:binding(\.major)){Text("Tahoe 26.x").tag(26);Text("Sequoia 15.x").tag(15);Text("Sonoma 14.x").tag(14);Text("macOS 27.x").tag(27)}}
                if recipe.target == .fixed {TextField("Exact macOS version",text:binding(\.fixedVersion)).textFieldStyle(.roundedBorder)}
                Text("The default stays within Tahoe 26.x. Endpoint discovery selects an available eligible release; this screen does not claim the latest point release.").font(.caption).foregroundStyle(.secondary)
            }}
            AdminCard {
                Text("Just need one popup or an optional-upgrade preview?").font(.headline)
                HStack {Button("Create a single popup"){navigate(.singlePopup)};Button("Preview an optional major upgrade"){navigate(.majorUpgrade)};Button("Audit Tahoe hardware only"){store.exportTahoeAudit()}}
                Button("Refresh Apple hardware data"){Task {do{_=try await AppleHardwareReader.refresh();store.notice="Apple hardware data refreshed for future exports."}catch{store.notice=error.localizedDescription}}}
                Text("Optional major upgrades remain simulation-only. The hardware audit exports a reporting package and an inventory script; it does not run an update.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private var rules:some View {
        AdminCard {
            Text("Make it recognizable").font(.headline)
            TextField("Organization name (optional)",text:Binding(get:{store.document.setupValue("ui.orgName")},set:{store.document.edits["ui.orgName"]=$0})).textFieldStyle(.roundedBorder)
            TextField("Support email (optional)",text:Binding(get:{store.document.setupValue("ui.itContactEmail")},set:{store.document.edits["ui.itContactEmail"]=$0})).textFieldStyle(.roundedBorder)
            Button("Choose popup logo…"){store.choosePopupLogo()}
        }
        if recipe.isOSWorkflow {AdminCard {
            Text("Which macOS should your Macs reach?").font(.headline)
            Picker("Update goal",selection:binding(\.target)){ForEach(WorkflowTarget.allCases){Text($0.title).tag($0)}}
            if recipe.target == .major {Picker("macOS generation",selection:binding(\.major)){Text("Tahoe 26.x").tag(26);Text("Sequoia 15.x").tag(15);Text("Sonoma 14.x").tag(14);Text("macOS 27.x").tag(27)};Text("Uses the latest eligible stable release in this generation and stays within it. Compatibility and availability are checked on each endpoint.").font(.caption).foregroundStyle(.secondary)}
            if recipe.target == .fixed {TextField("Exact version, such as 26.7.2",text:binding(\.fixedVersion)).textFieldStyle(.roundedBorder);Button("Choose from release catalog"){store.document=proposal;navigate(.catalog)}}
            Picker("Installation authorization",selection:binding(\.authorization)){ForEach(WorkflowAuthorization.allCases){Text($0.title).tag($0)}}
            Text(recipe.authorization == .userKeychain ? "PUSH reuses its existing user login Keychain entry. If missing or invalid, it asks the user and saves securely with their consent. A user who has never authorized cannot be updated unattended through this path.":"Existing IT credentials and Secure Token/volume ownership must be provisioned separately. This builder never embeds passwords in the package.").font(.callout).foregroundStyle(.secondary)
            Toggle("Include Tahoe replacement-review inventory",isOn:binding(\.includeTahoeAudit)).disabled(recipe.target != .major || recipe.major != 26)
        }}
        if recipe.isOSWorkflow || recipe.tasks.contains(.apps) {AdminCard {
            Text("When should the work be done?").font(.headline)
            Toggle("Set a specific deadline",isOn:binding(\.hasDeadline))
            if recipe.hasDeadline {
                Picker("Deadline time zone",selection:binding(\.timeZoneID)){ForEach(Array(Set([TimeZone.current.identifier,recipe.timeZoneID,"America/Chicago","America/New_York","America/Denver","America/Los_Angeles","Europe/London","UTC"])).sorted(),id:\.self){Text(TimeZone(identifier:$0)?.localizedName(for:.generic,locale:.current) ?? $0).tag($0)}}
                DatePicker("Finish by",selection:binding(\.deadline),displayedComponents:[.date,.hourAndMinute]).environment(\.timeZone,TimeZone(identifier:recipe.timeZoneID) ?? .current)
                Text(recipe.deadlineText).font(.callout.weight(.semibold))
                if recipe.isOSWorkflow {Toggle("Start required installation after the deadline",isOn:binding(\.enforceAfterDeadline))}
            }
            if !recipe.hasDeadline {Stepper("Allow \(recipe.graceDays) days after each update is discovered",value:binding(\.graceDays),in:1...365)}
            Picker("Small reminders",selection:binding(\.hourlyReminders)){Text("Every hour").tag(true);Text("Once a day").tag(false)}
            Toggle("Only show reminders during weekday working hours",isOn:binding(\.workingHoursOnly))
            Toggle("Wait while users are in meetings",isOn:binding(\.skipMeetings))
            Text("A full macOS reminder is shown daily. Offline, sleeping or logged-out Macs resume at an eligible check. Installation still needs power, space and valid authorization.").font(.caption).foregroundStyle(.secondary)
        }}
        if recipe.tasks.contains(.apps) {AdminCard {Text("Which apps?").font(.headline);ForEach(ApprovedApp.catalog){item in Toggle(item.name,isOn:app(item.id))};Toggle("Automatically update closed apps",isOn:binding(\.updateClosedApps));Text("Open apps stay running. An approved, protected Installomator provider must be deployed separately; the review lists this prerequisite.").font(.caption).foregroundStyle(.secondary)}}
        if recipe.tasks.contains(.registration) {AdminCard {Text("Registration").font(.headline);TextField("Self Service registration policy number",text:binding(\.registrationPolicy)).textFieldStyle(.roundedBorder);Text("Uses local registration evidence and your existing Self Service policy. This does not assess cloud compliance.").font(.caption).foregroundStyle(.secondary)}}
        if recipe.tasks.contains(.restart) {AdminCard {Stepper("First reminder after \(recipe.restartWarningDays) days",value:binding(\.restartWarningDays),in:1...365);Stepper("Escalate after \(recipe.restartForceDays) days",value:binding(\.restartForceDays),in:1...365);Text("Restart enforcement needs a verified production-signed client and its restricted management approval. The current local test build can preview it; deployment export will explain what is missing.").font(.caption).foregroundStyle(.orange)}}
        if recipe.tasks.contains(.wallpaper) {AdminCard {Text("Compliance background").font(.headline);Button("Choose noncompliant wallpaper…"){store.chooseWallpaper(role:"noncompliant")};Button("Choose compliant wallpaper…"){store.chooseWallpaper(role:"compliant")};Text("Custom images are included in the configured installer. The personal background is restored according to the reviewed compliance policy.").font(.caption).foregroundStyle(.secondary)}}
    }
    private var messageAndPreview:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Your message, beside its preview").font(.title2.bold())
            Text("Choose a message below, type your own wording or apply a suggestion. The example updates as you edit. Draft changes do not affect installed Macs.").font(.callout).foregroundStyle(.secondary)
            ViewThatFits(in:.horizontal) {
                HStack(alignment:.top,spacing:18) {
                    AdminCard {WorkflowMessageEditor(selection:$selectedMessage)}.frame(width:380)
                    messagePreview.frame(minWidth:460,maxWidth:.infinity)
                }
                VStack(alignment:.leading,spacing:18) {
                    AdminCard {WorkflowMessageEditor(selection:$selectedMessage)}
                    messagePreview
                }
            }
        }
    }
    private var messagePreview:some View {
        let sample=WorkflowPreviewSample.make(document:store.document,recipe:recipe,currentMajor:ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        var copy=ConfigDocument.load(sample.yaml,name:"Private preview")
        if selectedMessage == .minor {copy.edits["update.releaseType"]="minor"}
        if selectedMessage == .major {copy.edits["update.releaseType"]="major"}
        if selectedMessage == .deadline {copy.edits["update.deadline"]=ISO8601DateFormatter().string(from:Date().addingTimeInterval(-60))}
        let current=selectedMessage == .complete ? UIConfig.fromAdminYAML(copy.yaml).update.targetVersion:sample.currentVersion
        return VStack(alignment:.leading,spacing:8) {
            Label("Live draft preview · example device",systemImage:"eye").font(.headline)
            StudioPreview(state:selectedMessage.previewState,yaml:copy.yaml,progress:0.4,deferrals:0,logoData:store.document.logoImageData,chooseLogo:{store.choosePopupLogo()},sampleCurrentVersion:current,forcedPreview:selectedMessage == .forced,simulationAction:{_,_,_ in})
                .id(copy.setupFingerprint+selectedMessage.rawValue).frame(height:650)
            Text("Buttons here are simulated. Continue to Simulate to walk through the complete workflow.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var readiness:some View {
        let report=WorkflowPreparation(recipe:recipe,document:store.document)
        return VStack(alignment:.leading,spacing:16) {
            PageHeading(eyebrow:"Draft readiness",title:report.title,subtitle:"These checks describe the package you are creating. Pilot requirements are not proof that your fleet is ready.")
            if !report.blockers.isEmpty {AdminCard {Label("Fix before building",systemImage:"exclamationmark.triangle.fill").foregroundStyle(.orange);ForEach(report.blockers,id:\.self){Text($0)};Button("Return to Customize"){step = .customize}}}
            ForEach(report.items){item in AdminCard {
                Label(item.title,systemImage:item.kind == .ready ? "checkmark.circle":"info.circle").font(.headline)
                Text(item.kind == .pilot ? "PILOT VERIFICATION REQUIRED":item.kind == .attention ? "REVIEW YOUR CHOICE":"DRAFT SETTING").font(.caption.bold()).foregroundStyle(item.kind == .attention ? Color.orange:Color.secondary)
                Text(item.detail).font(.callout).fixedSize(horizontal:false,vertical:true)
                if item.id == "mode" || item.id == "wording" {Button("Customize this choice"){step = .customize}}
            }}
            AdminCard {
                Label("Installed state on this Admin Mac",systemImage:"desktopcomputer").font(.headline)
                Text("Separate from your draft and from fleet readiness. Refresh only reads saved local policy, evidence and service status; it never starts an update or reads passwords.").font(.callout).foregroundStyle(.secondary)
                Button(store.isRefreshingReadiness ? "Reading…":"Refresh local evidence"){Task{await store.refreshReadiness()}}.disabled(store.isRefreshingReadiness)
                if let snapshot=store.readiness {Text("Read "+ReadinessSnapshot.stamp(snapshot.capturedAt)).font(.caption);Text(snapshot.headline);Text(snapshot.explanation).font(.caption).foregroundStyle(.secondary)}
            }
        }
    }
    private var review:some View {
        VStack(alignment:.leading,spacing:16) {
            WorkflowChangesView()
            AdminCard {Text("Your workflow").font(.title2.bold());Text("Building creates files only. It does not install this policy on your Mac.").font(.callout).foregroundStyle(.secondary);ForEach(recipe.summary,id:\.self){Text("• "+$0).fixedSize(horizontal:false,vertical:true)};Toggle("Start selected monitors after installation",isOn:binding(\.startAfterInstall));Text("Building does not install anything. Installing a live package may show prompts and later download, install or restart under this policy. Paused packages keep dry-run enabled.").font(.caption).foregroundStyle(.secondary)}
            if !issues.isEmpty {AdminCard {Label("Fix these before building",systemImage:"exclamationmark.triangle").foregroundStyle(.orange);ForEach(issues,id:\.self){Text($0)}}}
            AdminCard {Text("Before deploying").font(.headline);Text("The installer includes the client, reviewed configuration, branding and selected assets. PUSH Admin stays on IT machines. Management profiles and any inventory script accompany the package for your management system.").font(.callout);if recipe.isOSWorkflow {Text("For major-upgrade discovery, deploy your approved Mist CLI. Password authorization and native delivery still need an enrolled pilot.").font(.caption)};if recipe.tasks.contains(.apps) {Text("Deploy your approved Installomator provider before app update policies run.").font(.caption)};if recipe.tasks.contains(.restart) {
                Button("Choose signed production client package…") {
                    let panel=NSOpenPanel();panel.allowsMultipleSelection=false;panel.canChooseDirectories=false;panel.message="Choose the full production-signed PUSH client package. It is inspected, never installed."
                    guard panel.runModal() == .OK,let url=panel.url else{return}
                    do{signedRestartIdentity=try ConfiguredClientBuilder.productionRestartIdentity(client:url);signedClient=url;store.notice="Verified the selected production client. Restart approvals will match its signature."}catch{signedClient=nil;signedRestartIdentity=nil;store.notice=error.localizedDescription}
                }
                Text(signedRestartIdentity == nil ? "Choose a production-signed client before packaging restart enforcement; the bundled local test client cannot create that approval.":"A signed client is selected. Its matching restart approval is included automatically.").font(.caption).foregroundStyle(.secondary)
            };if recipe.includeTahoeAudit {Text("The Tahoe inventory helper is included. Import the exported inventory script once in Jamf to group supported, unsupported and unverified Macs.").font(.caption)}}
            HStack {Button("Keep as my configuration"){store.document=proposal;store.notice="Workflow applied to this saved draft. No installed settings changed."};Button(store.isBuildingDeployment ? "Building…":"Build my workflow installer…"){let currentIssues=recipe.issues()+proposal.problems;guard currentIssues.isEmpty else {store.notice=currentIssues.joined(separator:"\n");return};store.document=proposal;store.buildConfiguredClient(teamID:signedRestartIdentity?.teamID ?? "",restartIdentity:signedRestartIdentity,activation:recipe.startAfterInstall ? .monitor:.paused,clientOverride:signedClient)}.buttonStyle(.borderedProminent).disabled(!issues.isEmpty || store.isBuildingDeployment || (recipe.tasks.contains(.restart) && signedRestartIdentity == nil))}
        }
    }
}
