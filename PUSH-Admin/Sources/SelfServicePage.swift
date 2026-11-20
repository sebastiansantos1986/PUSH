// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
struct SelfServicePage:View {
    @EnvironmentObject var store:AdminStore
    @State private var stage="downloading"
    @State private var major=26
    @State private var response="Choose a screen to preview. No update will run."
    private func value<T>(_ key:WritableKeyPath<SelfServiceSettings,T>)->Binding<T>{Binding(get:{store.selfServiceSettings[keyPath:key]},set:{var s=store.selfServiceSettings;s[keyPath:key]=$0;store.selfServiceSettings=s})}
    private func wording(_ key:String)->Binding<String>{Binding(get:{store.document.setupValue(key)},set:{store.document.edits[key]=$0})}
    private var preview:ConfigDocument {(try? SelfServiceKit.profile(store.document,major:major)) ?? .fresh}
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:22){
            PageHeading(eyebrow:"Jamf Self Service",title:"Offer an upgrade when users are ready.",subtitle:"Create separate macOS 26 and 27 items. Each selects the latest eligible stable release in its generation when clicked. No reminder campaign or deadline is added.")
            AdminCard {
                Text("1. Choose your offers").font(.title3.bold())
                Toggle("Offer macOS Tahoe 26",isOn:value(\.offer26))
                if store.selfServiceSettings.offer26 {TextField("Self Service title",text:value(\.title26));TextEditor(text:value(\.description26)).frame(height:90)}
                Toggle("Offer macOS 27",isOn:value(\.offer27))
                if store.selfServiceSettings.offer27 {TextField("Self Service title",text:value(\.title27));TextEditor(text:value(\.description27)).frame(height:90)}
                Text("Suggested descriptions are ready to use. Hardware eligibility, Apple availability and authorization are checked on the endpoint. Nothing is promised for unsupported Macs.").font(.caption).foregroundStyle(.secondary)
            }
            AdminCard {
                Text("2. Brand and preview").font(.title3.bold());PopupLogoControls()
                Text("The selected draft icon is copied into the isolated offer package. Your current campaign is not changed.").font(.caption).foregroundStyle(.secondary)
                Picker("Example target",selection:$major){Text("macOS 26").tag(26);Text("macOS 27").tag(27)}.pickerStyle(.segmented)
                Picker("Screen",selection:$stage){Text("Download progress").tag("downloading");Text("Installation preparation").tag("installing");Text("Storage warning").tag("preflightDisk");Text("Power warning").tag("preflightPower");Text("Before restart").tag("rebooting")}
                Text("Existing password authorization may also appear when valid saved credentials are unavailable. Preview buttons simulate their result and cannot access Keychain or start an update.").font(.caption).foregroundStyle(.secondary)
            }
            AdminCard {
                Text("Download screen wording").font(.title3.bold())
                Text("Write the text your users will see. Changes appear in the preview and are included in both exported offers.").font(.callout).foregroundStyle(.secondary)
                Text("Window subtitle").font(.headline)
                TextField("Download in Progress",text:wording("ui.downloadHeader")).textFieldStyle(.roundedBorder)
                Text("Main heading").font(.headline)
                TextField("Downloading {macOS}",text:wording("ui.downloadTitle")).textFieldStyle(.roundedBorder)
                Text("Message").font(.headline)
                TextEditor(text:wording("ui.downloadingMessage")).frame(height:75)
                Text("Footer guidance").font(.headline)
                TextEditor(text:wording("ui.downloadFooter")).frame(height:65)
                Text("Use {macOS} for the full release label, {version} for the selected version, or {osName} for its name. The same wording works for both offers. Live percentage and download status always come from the updater.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Preview download"){stage="downloading"}
                    Button("Use suggested download wording"){
                        for (key,text) in [("downloadHeader",DownloadWording.header),("downloadTitle",DownloadWording.title),("downloadingMessage",DownloadWording.message),("downloadFooter",DownloadWording.footer)] {store.document.edits["ui."+key]=text}
                        stage="downloading"
                    }
                }
            }
            StudioPreview(state:UIState.from(stage),yaml:preview.yaml,progress:0.58,deferrals:0,logoData:preview.logoImageData,chooseLogo:{store.choosePopupLogo()},sampleCurrentVersion:major==26 ? "15.7":"26.0",selfServicePreview:true,simulationAction:{_,code,automatic in response="Simulated response: \(code.map(String.init) ?? "none")\(automatic ? " (timer)":""). No system action occurred."}).id(stage+String(major)+preview.yaml).frame(height:650)
            Text(response).font(.callout).foregroundStyle(.blue)
            AdminCard {
                Text("3. Export the Jamf setup kit").font(.title3.bold())
                Text("Includes isolated YAML profiles, the profiles installer, one script and description per offer, and PUSH Client 1.16.7 as a separate prerequisite. PUSH Admin and JamfCheckIn are not installed on users’ Macs.")
                Text("Deploy an approved root-protected Mist CLI for major-upgrade discovery. Use Self Service policies with Ongoing frequency, no automatic triggers and scripts set to After. Scope compatible pilot Macs first. The export guide explains each step.").font(.callout).foregroundStyle(.secondary)
                Button("Export Jamf Self Service kit…"){store.exportSelfServiceKit()}.buttonStyle(.borderedProminent)
                Text("Creates local files only. Does not publish to Jamf, install PUSH, change this Mac's policy, or run an upgrade.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(28).frame(maxWidth:1250,alignment:.leading)}
    }
}
