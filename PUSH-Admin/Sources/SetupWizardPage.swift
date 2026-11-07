// PUSH Admin — Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit

struct SetupWizardPage:View {
    @EnvironmentObject var store:AdminStore
    var navigate:(AdminPage)->Void
    @State private var selectedPreview:UIState = .toast
    @State private var showPreview=false
    @State private var previewRevision=UUID()
    @State private var entraStage=1
    @State private var deadlineNoticePreview=false
    private var step:SetupWizardStep {store.setupProgress.currentStep}
    private var document:ConfigDocument {store.document}
    private var requirements:[SetupPreviewRequirement] {document.setupPreviewRequirements}
    private var exercised:Int {requirements.filter{$0.exercised(document:document,progress:store.setupProgress)}.count}
    private func text(_ key:String)->Binding<String> {Binding(get:{store.document.setupValue(key)},set:{store.document.edits[key]=$0})}
    private func flag(_ key:String)->Binding<Bool> {Binding(get:{store.document.setupFlag(key)},set:{store.document.edits[key]=$0 ? "true":"false"})}
    private func number(_ key:String,_ fallback:Int)->Binding<Int> {Binding(get:{Int(store.document.setupValue(key)) ?? fallback},set:{store.document.edits[key]=String($0)})}
    private func move(_ value:SetupWizardStep) {store.setupProgress.step=value.rawValue;showPreview=false}
    private func input(_ title:String,_ key:String)->some View {
        VStack(alignment:.leading,spacing:5){Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary);TextField(title,text:text(key)).textFieldStyle(.roundedBorder)}
    }
    private func count(_ title:String,_ key:String,_ fallback:Int,_ range:ClosedRange<Int>)->some View {
        Stepper(title+": "+document.setupValue(key),value:number(key,fallback),in:range)
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                PageHeading(eyebrow:"Guided setup",title:"Set it up once. Know what happens next.",subtitle:"Seven steps for your saved draft. Export or review deployment when you are ready.")
                HStack(spacing:5) {
                    ForEach(SetupWizardStep.allCases) {item in
                        Button {move(item)} label:{
                            VStack(spacing:7){Text(String(item.rawValue+1)).font(.caption.bold()).frame(width:26,height:26).background(step == item ? Color.blue:Color.secondary.opacity(0.12)).foregroundStyle(step == item ? Color.white:Color.primary).clipShape(Circle());Text(item.title).font(.caption.weight(step == item ? .bold:.regular))}.frame(maxWidth:.infinity).padding(.vertical,10).background(step == item ? Color.blue.opacity(0.06):Color.clear).clipShape(RoundedRectangle(cornerRadius:10))
                        }.buttonStyle(.plain)
                    }
                }
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:5){Text(step.title).font(.title2.bold());Text(step.subtitle).foregroundStyle(.secondary)}
                    Spacer()
                    Text(document.setupFlag("debug.dryRun") ? "DRY-RUN DRAFT":"LIVE DRAFT").font(.caption.bold()).padding(9).background(document.setupFlag("debug.dryRun") ? Color.blue.opacity(0.08):Color.orange.opacity(0.12)).clipShape(Capsule())
                }
                if step == .start || step == .review {SetupAdvisorCard()}
                content
                if step != .review && !document.setupIssues(for:step).isEmpty {
                    AdminCard {Label("Review before continuing",systemImage:"exclamationmark.triangle").foregroundStyle(.orange);ForEach(document.setupIssues(for:step),id:\.self){Text($0).font(.callout)}}
                }
                HStack {
                    Button("Back"){if let previous=SetupWizardStep(rawValue:step.rawValue-1){move(previous)}}.disabled(step == .start)
                    Spacer()
                    Text("Draft only · progress saved locally").font(.caption).foregroundStyle(.secondary)
                    if step != .review {
                        Button("Continue"){if let next=SetupWizardStep(rawValue:step.rawValue+1){move(next)}}.buttonStyle(.borderedProminent).disabled(!document.setupIssues(for:step).isEmpty)
                    }
                }
            }.padding(28).frame(maxWidth:1200,alignment:.leading)
        }.task{await store.refreshReadiness()}
    }
    @ViewBuilder private var content:some View {
        switch step {
        case .start:start
        case .branding:branding
        case .macOS:macOS
        case .apps:apps
        case .registration:registration
        case .preview:previews
        case .review:review
        }
    }
    private var start:some View {
        VStack(spacing:18) {
            AdminCard {
                Label("Your starting point",systemImage:"doc.text").font(.headline)
                LabeledContent("Current draft",value:document.sourceName)
                LabeledContent("Last review",value:store.setupProgress.reviewed(document) ? "This exact draft was reviewed":"This draft has not been reviewed")
                Text("Continue with your current draft, or replace it deliberately. Editing here never applies settings or enables a monitor.").foregroundStyle(.secondary)
                HStack {Button("New dry-run draft…"){store.newDraft()};Button("Import YAML…"){store.chooseImport()};Button("Import installed YAML…"){store.importInstalledForSetup()}.disabled(!FileManager.default.fileExists(atPath:store.livePath))}
                if document.omittedCredentials>0 {Text("\(document.omittedCredentials) plaintext credential field(s) were omitted on import. Provision managed authorization separately.").font(.caption).foregroundStyle(.orange)}
            }
            AdminCard {
                Label("Choose your rehearsal mode",systemImage:"shield.lefthalf.filled").font(.headline)
                Toggle("Keep this draft in dry-run mode",isOn:flag("debug.dryRun"))
                Text("Dry run prevents active checks and update actions after this policy is applied. Existing live settings stay as they are until you explicitly apply a draft. The wizard does not collect passwords or provision enrollment.").font(.callout).foregroundStyle(.secondary)
                if !document.setupFlag("debug.dryRun") {Label("Live draft: review every enabled module before applying, especially if a monitor is already loaded.",systemImage:"exclamationmark.triangle.fill").foregroundStyle(.orange)}
            }
        }
    }
    private var branding:some View {
        VStack(spacing:18) {
            AdminCard {
                Label("Organization & support",systemImage:"building.2").font(.headline)
                input("Application title","ui.appName");input("Organization","ui.orgName")
                HStack {input("Support email","ui.itContactEmail");input("Support phone","ui.itContactPhone")}
                input("Support website · optional HTTPS URL","ui.helpURL")
                Text("Support details are optional, but help users recognize who manages the update.").font(.caption).foregroundStyle(.secondary)
            }
            AdminCard {
                PopupLogoControls()
                Button("Configure compliance wallpaper…"){navigate(.wallpaper)}
                Divider()
                input("Accent color · six-digit hex","ui.accentColorHex")
                Picker("Background",selection:text("ui.popupBackgroundStyle")){Text("Solid").tag("solid");Text("Frosted").tag("frosted")}.pickerStyle(.segmented)
                count("Background strength (%)","ui.popupOpacityPercent",85,55...100)
                Text("Your selected image appears in the Preview step. When you attach an image, Export includes a managed PNG; a referenced path must exist on the Macs where you deploy it.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var macOS:some View {
        VStack(spacing:18) {
            AdminCard {
                Label("Which releases should PUSH follow?",systemImage:"sparkles").font(.headline)
                Picker("Release policy",selection:Binding(get:{document.setupStrategy},set:{store.document.chooseSetupStrategy($0)})) {ForEach(SetupMacStrategy.allCases){Text($0.rawValue).tag($0)}}
                if document.setupStrategy == .fixed {input("Required macOS version","update.targetVersion")}
                if [.minor,.major].contains(document.setupStrategy) {
                    Text("PUSH keeps discovering eligible stable releases after the previous target is met. A preset changes discovery fields only; it preserves your deadline override and installation choices.").font(.callout).foregroundStyle(.secondary)
                }
                HStack{count("Minor grace days","auto.minorDeadlineDays",7,1...365);Spacer();count("Major grace days","auto.majorDeadlineDays",14,1...365)}
                Toggle("Use Mist to list compatible full installers",isOn:flag("auto.useMist"))
                Toggle("Exclude beta releases",isOn:flag("auto.skipBetas"))
            }
            AdminCard {
                Label("Reminder hours & deadline",systemImage:"calendar.badge.clock").font(.headline)
                count("Toast interval (seconds)","update.toastIntervalSeconds",3600,60...604800)
                Button("Use hourly toast reminders"){store.document.edits["update.toastIntervalSeconds"]="3600"}
                Toggle("Restrict reminders to saved working hours",isOn:flag("schedule.respectAlertWindow"))
                Text(document.setupFlag("schedule.respectAlertWindow") ? "Saved working hours and weekday rules apply.":"Working-hour restrictions are disabled. Reminders are allowed 24/7, including weekends, whenever a desktop session is available.").font(.caption).foregroundStyle(.secondary)
                HStack{count("Start hour","schedule.alertStartHour",8,0...23);Spacer();count("End hour","schedule.alertEndHour",18,1...24)}
                Toggle("Weekdays only",isOn:flag("schedule.skipWeekends"));Toggle("Wait during meetings",isOn:flag("schedule.skipDuringMeetings"))
                count("Allowed deferrals","update.maxDeferrals",5,0...100)
                input("YAML deadline override · optional ISO 8601 timestamp","update.deadline")
                Button("Clear override and use automatic grace periods"){store.document.edits["update.deadline"]=""}.disabled(document.setupValue("update.deadline").isEmpty)
                Text("An explicit override wins for every discovered target, including when it is already expired. Empty uses the target-specific automatic deadline. Full prompts follow the separate daily schedule. Due dates still require an active monitor and an eligible user session.").font(.caption).foregroundStyle(.secondary)
            }
            AdminCard {
                Label("What may happen after the deadline?",systemImage:"arrow.down.circle").font(.headline)
                Picker("Installation policy",selection:Binding(get:{document.setupFlag("update.silentInstallAfterDeadline") ? "silent":(document.setupFlag("update.autoInstallAfterDeadline") ? "prompted":"manual")},set:{mode in store.document.edits["update.silentInstallAfterDeadline"]=mode == "silent" ? "true":"false";store.document.edits["update.autoInstallAfterDeadline"]=mode == "prompted" ? "true":"false"})) {
                    Text("Wait for an explicit installation choice").tag("manual");Text("Automatic install with progress UI").tag("prompted");Text("Automatic silent install").tag("silent")
                }
                Toggle("Download at the deadline even when no user is logged in",isOn:flag("update.prepareAtDeadlineWhenLoggedOut"))
                Toggle("Automatically install non-system updates",isOn:flag("auto.autoInstallNonSystemUpdates"))
                Text("Automatic choices can perform real work after live activation. Managed authorization and preflight checks still apply. Restart and advanced settings are preserved; the final review highlights enabled restart policy.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var apps:some View {
        VStack(spacing:18) {
            AdminCard {
                Label("Choose approved apps",systemImage:"square.stack.3d.up").font(.headline)
                Toggle("Enable approved app management",isOn:flag("apps.enabled"))
                ForEach(ApprovedApp.catalog){app in Toggle(app.name,isOn:Binding(get:{AppUpdatePolicy.ids(document.setupValue("apps.approved")).contains(app.id)},set:{store.document.approveApp(app.id,enabled:$0)}))}
                Text("Installed supported copies only. Missing apps, App Store copies and unverified publishers/channels are skipped. Leave apps managed by another tool unchecked.").font(.caption).foregroundStyle(.secondary)
            }
            AdminCard {
                Toggle("Show grouped hourly reminders",isOn:flag("apps.notifyHourly"))
                Toggle("Automatically update approved apps when closed",isOn:flag("apps.autoUpdateClosed"))
                count("App grace days","apps.graceDays",7,1...365)
                input("All-app deadline override · optional","apps.deadline")
                input("Managed Installomator script path","apps.installomatorPath")
                Text("Installomator is separately managed. Open apps are never force-quit, even after a deadline. Automatic closed-app updates can run before that deadline. Per-app overrides are preserved and can be edited in App Updates.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var registration:some View {
        VStack(spacing:18) {
            AdminCard {
                Label("Jamf device registration",systemImage:"person.crop.circle.badge.checkmark").font(.headline)
                Toggle("Enable Entra registration reminders",isOn:flag("entra.enabled"))
                input("Self Service registration policy ID","entra.policyID")
                HStack{count("Start hour","entra.startHour",8,0...23);Spacer();count("End hour","entra.endHour",18,1...24)}
                Toggle("Weekdays only",isOn:flag("entra.weekdaysOnly"));Toggle("Wait during meetings",isOn:flag("entra.skipMeetings"))
                Toggle("Refresh inventory after a detected registration transition",isOn:flag("entra.reconOnRegistration"))
                Text("Production nudges require MDM enrollment, trusted Jamf, Company Portal and legacy Jamf Self Service. Register Now opens your configured policy; only a later local-evidence check stops reminders. Cloud compliance is not assessed.").font(.callout).foregroundStyle(.secondary)
            }
            AdminCard {
                DisclosureGroup("Paths & message") {
                    VStack(spacing:12){input("Self Service app","entra.selfServicePath");input("Company Portal app","entra.companyPortalPath");input("Jamf binary","entra.jamfBinaryPath");input("Custom message · optional","entra.message")}.padding(.top,12)
                }
                Text("Preview works on an unenrolled Mac. Disable any previous independent registration reminder policy before activating this workflow, to avoid duplicate reminders. This wizard never changes Jamf policies.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var previews:some View {
        VStack(spacing:18) {
            AdminCard {
                Label("Safe popup rehearsal",systemImage:"rectangle.on.rectangle").font(.headline)
                Text("All actions below are simulated in this app. No engine command, Self Service, app updater or restart is invoked. Changes to the draft require a fresh set of button checks.").font(.callout).foregroundStyle(.secondary)
                Picker("Popup",selection:$selectedPreview){ForEach([UIState.toast,.updateRecovery,.softNudge,.hardBlock,.appUpdates,.entraRegistration,.rebootNudge,.rebootForce,.compliant,.error],id:\.rawValue){Text($0.windowTitle).tag($0)}}
                if selectedPreview == .toast {Toggle("Preview the informational deadline notice",isOn:$deadlineNoticePreview)}
                if selectedPreview == .entraRegistration {Picker("Registration stage",selection:$entraStage){ForEach(1...4,id:\.self){Text("Stage \($0)").tag($0)}}.pickerStyle(.segmented)}
                HStack{Button(showPreview ? "Reset simulated preview":"Show simulated preview"){previewRevision=UUID();showPreview=true}.buttonStyle(.borderedProminent);if showPreview {Button("Hide preview"){showPreview=false}}}
                if showPreview {
                    StudioPreview(state:selectedPreview,yaml:store.previewYAML,progress:0.42,deferrals:0,logoData:document.logoImageData,chooseLogo:{store.choosePopupLogo()},appNotices:document.appPreviewNotices(),entraNotice:document.entraPreviewNotice(stage:entraStage),informationalToastMessage:selectedPreview == .toast && deadlineNoticePreview ? "The macOS update deadline has passed. PUSH will now attempt the configured update workflow. Please save your work. Dismissing this notice does not postpone enforcement.":nil)
                        .id(PopupPreviewIdentity(revision:previewRevision,yaml:store.previewYAML+selectedPreview.rawValue+String(entraStage)+String(deadlineNoticePreview),imageData:document.logoImageData)).frame(height:[UIState.toast,.appUpdates].contains(selectedPreview) ? 620:860)
                }
            }
            coverage
        }.onChange(of:selectedPreview){_,_ in previewRevision=UUID()}
    }
    private var coverage:some View {
        AdminCard {
            Label("\(exercised) of \(requirements.count) suggested button choices exercised",systemImage:"checklist").font(.headline)
            ForEach(requirements){item in
                let done=item.exercised(document:document,progress:store.setupProgress)
                Label(item.title,systemImage:done ? "checkmark.circle.fill":"circle").font(.callout).foregroundStyle(done ? Color.green:Color.secondary)
            }
            Text("Recorded simulated choices for this exact draft. Opening a scheduler or an automatic timeout does not count as clicking a button. This is not an end-to-end installation or native-window test.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var review:some View {
        VStack(spacing:18) {
            AdminCard {
                Label(document.setupIssues.isEmpty ? "Draft ready for deployment review":"Resolve draft issues",systemImage:document.setupIssues.isEmpty ? "doc.badge.checkmark":"exclamationmark.triangle").font(.title3.bold())
                LabeledContent("macOS strategy",value:document.setupStrategy.rawValue)
                LabeledContent("Mode",value:document.setupFlag("debug.dryRun") ? "Dry run":"Live policy")
                LabeledContent("Deadline override",value:document.setupValue("update.deadline").isEmpty ? "Automatic, target-specific":document.setupValue("update.deadline"))
                LabeledContent("Apps",value:document.setupFlag("apps.enabled") ? document.setupValue("apps.approved"):"Disabled")
                LabeledContent("Registration",value:document.setupFlag("entra.enabled") ? "Enabled · policy "+document.setupValue("entra.policyID"):"Disabled")
                Text("This wizard has not applied the draft, enabled monitoring or verified unattended installation. Export the policy, or continue to Deployment for explicit apply and monitoring controls.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(document.setupFindings(snapshot:store.readiness,providerPresent:FileManager.default.fileExists(atPath:document.setupValue("apps.installomatorPath")))){finding in
                AdminCard {Label(finding.title,systemImage:finding.level == .good ? "checkmark.circle":(finding.level == .attention ? "exclamationmark.triangle":"info.circle")).font(.headline).foregroundStyle(finding.level == .attention ? Color.orange:Color.primary);Text(finding.detail).font(.callout).foregroundStyle(.secondary)}
            }
            coverage
            AdminCard {
                Label("Your next step",systemImage:"arrow.right.circle").font(.headline)
                HStack{
                    Button("Refresh local readiness"){Task{await store.refreshReadiness()}}.disabled(store.isRefreshingReadiness)
                    Button("Return to previews"){move(.preview)}
                    Button("Advanced configuration"){navigate(.configuration)}
                }
                HStack {
                    Button("Export YAML…"){store.exportDocument()}.disabled(!document.setupIssues.isEmpty)
                    Button("Mark draft reviewed"){store.setupProgress.markReviewed(store.document);store.notice="This draft is marked reviewed. It has not been applied or activated; preview coverage and unverified prerequisites remain listed."}.disabled(!document.setupIssues.isEmpty)
                    Spacer()
                    Button("Review deployment →"){navigate(.deployment)}.buttonStyle(.borderedProminent).disabled(!document.setupIssues.isEmpty)
                }
                if store.setupProgress.reviewed(document) {Text("Reviewed "+ReadinessSnapshot.stamp(store.setupProgress.reviewedAt)+" · \(exercised)/\(requirements.count) suggested simulated choices recorded.").font(.caption).foregroundStyle(.secondary)}
                Text("Export and Review deployment do not start a check. Applying to a Mac with active monitors changes what future checks use. Activation remains a separate administrator choice.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
