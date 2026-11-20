// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI

struct JamfDeploymentControls:View {
    @EnvironmentObject private var store:AdminStore
    @Binding var document:ConfigDocument
    @State private var previewNotice=""
    private var settings:JamfDeploymentSettings {document.jamfDeploymentSettings ?? JamfDeploymentSettings()}
    private func value<T>(_ key:WritableKeyPath<JamfDeploymentSettings,T>)->Binding<T> {Binding(get:{settings[keyPath:key]},set:{var next=settings;next[keyPath:key]=$0;document.jamfDeploymentSettings=next})}
    private func rule<T>(_ key:WritableKeyPath<WorkflowRecipe,T>)->Binding<T> {Binding(get:{settings.campaign[keyPath:key]},set:{var next=settings;next.campaign[keyPath:key]=$0;document.jamfDeploymentSettings=next})}
    private func message(_ key:String)->Binding<String> {Binding(get:{document.setupValue(key)},set:{document.edits[key]=$0})}
    var body:some View {
        AdminCard {
            Text("Choose your deployment workflow").font(.title3.bold())
            Picker("Deployment type",selection:value(\.mode)){ForEach(JamfDeploymentMode.allCases){Text($0.title).tag($0)}}
            if settings.mode.requiresCampaign {
                Label("Hourly toasts · Daily full reminders · Enforce at deadline",systemImage:"bell.badge").font(.headline)
                Text("The configured client includes its background monitor. Reminders are allowed every day, including weekends, while a user session is available. No separate daemon-install command is needed.").font(.callout).fixedSize(horizontal:false,vertical:true)
                Picker("Required macOS",selection:rule(\.target)){ForEach(WorkflowTarget.allCases){Text($0.title).tag($0)}}
                if settings.campaign.target == .major {Picker("Generation",selection:rule(\.major)){Text("macOS Tahoe 26.x").tag(26);Text("macOS 27.x").tag(27)}}
                if settings.campaign.target == .fixed {TextField("Required version, for example 26.1",text:rule(\.fixedVersion)).textFieldStyle(.roundedBorder)}
                TextField("Deadline time zone",text:rule(\.timeZoneID)).textFieldStyle(.roundedBorder)
                DatePicker("Install by",selection:rule(\.deadline),displayedComponents:[.date,.hourAndMinute]).environment(\.timeZone,TimeZone(identifier:settings.campaign.timeZoneID) ?? .current)
                Text(settings.campaign.deadlineText).font(.caption).foregroundStyle(.secondary)
                Picker("Installation authorization",selection:rule(\.authorization)){ForEach(WorkflowAuthorization.allCases){Text($0.title).tag($0)}}
                Text("Valid saved Keychain credentials are reused. A deadline cannot bypass authorization, unsupported hardware, low storage, missing power or an unavailable update.").font(.caption).foregroundStyle(.secondary)
                Toggle("Show noncompliant wallpaper until this macOS target is met",isOn:Binding(get:{settings.useWallpaper},set:{var next=settings;next.wallpaperEnabled=$0;document.jamfDeploymentSettings=next}))
                if settings.useWallpaper {
                    HStack {Button("Choose noncompliant image…"){store.chooseWallpaper(role:"noncompliant")};Button("Use PUSH default image"){store.useDefaultWallpaper()}}
                    Text(document.wallpaperAssets?["noncompliant"]?.originalName ?? "PUSH default noncompliant wallpaper — included in the client package").font(.caption).foregroundStyle(.secondary)
                    if let image=store.wallpaperPreview(role:"noncompliant") {Image(nsImage:image).resizable().aspectRatio(contentMode:.fit).frame(maxHeight:150).clipShape(RoundedRectangle(cornerRadius:8))}
                    Text("Applied on the first eligible PUSH check after the target is resolved, then rechecked on each run. If the user changes it while noncompliant, PUSH reapplies it. Once compliant, the saved personal background is restored when PUSH's image is still active. No logged-in session means it waits.").font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Messages and preview") {
                    Text("Hourly toast message").font(.headline)
                    TextEditor(text:message("toast.message")).frame(height:80)
                    Text("Daily reminder message").font(.headline)
                    TextEditor(text:Binding(get:{document.setupValue("ui.majorMessage")},set:{document.edits["ui.majorMessage"]=$0;document.edits["ui.minorMessage"]=$0})).frame(height:110)
                    Button("Use suggested campaign messages") {document=WorkflowWording.applySet(recipe:settings.campaign,to:document)}
                    Button("Apply these rules to the simulation draft") {
                        do {document=try settings.document(from:document);previewNotice="Simulation draft updated. Open Create Workflow → Simulate for the safe popup tour."}catch{previewNotice=error.localizedDescription}
                    }
                    if !previewNotice.isEmpty {Text(previewNotice).font(.caption)}
                    Text("Customize or Popup Studio lets you select your icon. Custom wording and the selected icon are packaged with this campaign. Applying a simulation draft changes no installed policy or system setting.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(settings.campaign.issues(),id:\.self){Text($0).font(.caption).foregroundStyle(.orange)}
                Text("After you enable the pilot, Jamf installs the configured client at check-in. Installation replaces its YAML after backup and starts monitoring after five minutes. Publishing alone leaves policies disabled. Disabling a Jamf policy later does not stop a monitor already installed on a Mac.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }else {Text("Self Service offers only: users choose to update. This mode does not install a required-update reminder campaign.").font(.caption).foregroundStyle(.secondary)}
        }
    }
}
