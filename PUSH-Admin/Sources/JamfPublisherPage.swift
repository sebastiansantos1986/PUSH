// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
private enum JamfPublisherModal:Identifiable {
    case success(JamfPublishSuccess),names(JamfNameReview),renamed(JamfNameResult)
    var id:String {switch self {case .success(let value):return "success-"+value.id.uuidString;case .names(let value):return "names-"+value.id.uuidString;case .renamed(let value):return "renamed-"+value.id.uuidString}}
}
struct JamfPublisherPage:View {
    @EnvironmentObject var store:AdminStore
    @StateObject private var model=JamfPublisherModel()
    private var currentReview:Bool {model.plan?.draftHash==JamfPublisherModel.fingerprint(store.document)}
    private var modal:Binding<JamfPublisherModal?> {Binding(get:{
        if let value=model.nameResult {return .renamed(value)}
        if let value=model.nameReview {return .names(value)}
        if let value=model.successReport {return .success(value)}
        return nil
    },set:{_ in model.nameResult=nil;model.nameReview=nil;model.successReport=nil})}
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:22){
            PageHeading(eyebrow:"Publish to Jamf",title:"Build, review and publish your Jamf deployment.",subtitle:"Choose optional offers, required updates, or both. Review the packages and policies before publishing; enable the pilot separately.")
            JamfDeploymentControls(document:$store.document)
            AdminCard {
                Text("1. Connect your Jamf server").font(.title3.bold())
                TextField("https://your-company.jamfcloud.com",text:$model.connection.server).textFieldStyle(.roundedBorder).disabled(model.connected || model.busy)
                TextField("API client ID",text:$model.connection.clientID).textFieldStyle(.roundedBorder).disabled(model.connected || model.busy)
                if !model.connected {
                    SecureField("API client secret",text:$model.secret).textFieldStyle(.roundedBorder)
                    Toggle("Remember this API secret in my login Keychain",isOn:$model.rememberSecret)
                    HStack {Button("Use saved secret"){model.savedSecret()};Button("Check connection"){model.connect()}.buttonStyle(.borderedProminent)}.disabled(model.busy)
                }else {Button("Disconnect"){model.disconnect()}.disabled(model.busy)}
                Button("Forget saved secret"){model.forgetSecret()}.disabled(model.busy)
                Text("Credentials stay on this admin Mac. API tokens stay in memory. No API secret is added to workflow files, packages or users' Macs. HTTPS with normal certificate trust is required.").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("API role permissions"){
                    Text(JamfPublisherPolicy.privileges.joined(separator:"\n")).font(.callout).textSelection(.enabled)
                    Text("Group renaming additionally needs Update Static Computer Groups or Update Smart Computer Groups, according to the selected group type.").font(.caption).foregroundStyle(.secondary)
                    Text("Create Static Computer Groups is needed only for a new empty pilot group. This publisher requires Jamf Pro 11.5+ and a cloud distribution point. File-share servers can use the export kit/Jamf Sync.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let snapshot=model.snapshot {
                AdminCard {
                    Text("2. Choose your pilot and prerequisites").font(.title3.bold())
                    Picker("Pilot group",selection:$model.selectedGroupID){Text("Create a new EMPTY pilot group").tag(0);ForEach(snapshot.groups){Text($0.name).tag($0.id)}}
                    Text("PUSH never selects All Computers. A new group starts empty; add your approved pilot Macs in Jamf. Selecting an existing group uses its current and future membership. Use compatible pilot Macs running macOS 14 or later.").font(.caption).foregroundStyle(.secondary)
                    Button("Edit names of published policies & group…"){model.loadNames(project:store.document.jamfDeploymentID)}
                    Text("Loads this workflow's published items by Jamf ID. Use it to rename a static pilot group or an existing smart group while preserving its definition.").font(.caption).foregroundStyle(.secondary)
                    Text("Offers: "+((store.document.jamfDeploymentSettings?.mode.includesOffers ?? true) ? store.selfServiceSettings.majors:[]).map{"macOS \($0)"}.joined(separator:", "))
                    Text("Popup wording and icons come from the current draft. Configure required reminders above; edit optional offers in Jamf Self Service.").font(.caption).foregroundStyle(.secondary)
                    Label("PUSH Client 1.16.7 is included automatically",systemImage:"checkmark.circle.fill").foregroundStyle(.green)
                    Text("Mist: "+(model.mistPackage?.lastPathComponent ?? (model.useBundledMist && (store.document.jamfDeploymentSettings ?? JamfDeploymentSettings()).needsMist ? "Bundled Mist CLI 2.3 — included automatically":"Uses the Mist already managed on endpoints, if needed")))
                    Text("Mist CLI by Nindi Gill / ninxsoft. Same-generation point updates use Apple Software Update; major-upgrade workflows include the verified Mist package by default.").font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Advanced package overrides") {
                        Text("PUSH client: "+(model.clientOverride?.lastPathComponent ?? "Bundled 1.16.7 · local testing"))
                        HStack {Button("Choose production-signed client…"){model.choosePackage(mist:false)};if model.clientOverride != nil {Button("Use bundled client"){model.clientOverride=nil}}}
                        Toggle("Include bundled Mist when needed",isOn:$model.useBundledMist)
                        HStack {Button("Choose organization-approved Mist installer…"){model.choosePackage(mist:true)};if model.mistPackage != nil {Button("Use bundled Mist"){model.mistPackage=nil;model.useBundledMist=true}}}
                        Text("Overrides are optional. A custom Mist package must deploy a root-protected executable in a supported path.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Build & review setup"){
                        if store.document.jamfDeploymentID==nil {store.document.jamfDeploymentID=UUID()}
                        model.review(document:store.document,project:store.document.jamfDeploymentID!,wallpaperFolder:store.wallpaperAssetDirectory)
                    }.buttonStyle(.borderedProminent)
                }.disabled(model.busy)
            }
            if let plan=model.plan {
                AdminCard {
                    Text("3. Review the exact setup").font(.title3.bold())
                    Text(plan.summary).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                    if !currentReview {Text("The draft changed. Build & review again to publish its latest settings.").foregroundStyle(.orange)}
                    if let receipt=model.receipt {
                        Text(receipt.message).font(.callout)
                        Button("Show names & IDs"){model.showSuccess()}
                        ForEach(receipt.objects.filter{$0.kind=="policies"},id:\.id){object in Text("Policy \(object.id) · \(object.name)").font(.caption).textSelection(.enabled)}
                        if let url=try? model.connection.validatedURL(){Link("Open Jamf Pro",destination:url)}
                        Button(receipt.enabled ? "Pilot enabled":"Enable for pilot…"){model.enable()}.buttonStyle(.borderedProminent).disabled(!receipt.verified || receipt.enabled || !currentReview || model.busy)
                    }else {Button("Publish disabled setup"){model.publish()}.buttonStyle(.borderedProminent).disabled(!currentReview || model.busy)}
                    Text(plan.deployment.mode.requiresCampaign ? "The campaign policy installs the configured client at check-in, once per computer. Its local monitor then delivers reminders and enforces the deadline. Publishing sends no remote OS-update or restart command.":"Offers automatically repair missing, outdated or damaged prerequisites through a repeatable, on-demand policy. Working current clients skip reinstallation. No check-in trigger or Jamf history reset is needed.").font(.caption).foregroundStyle(.secondary)
                }
            }
            AdminCard {
                if model.busy {ProgressView().controlSize(.small)}
                Text(model.status).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                Button("Preview success popup (safe)"){model.successReport = .preview}.disabled(model.busy)
                if model.preparedFolder != nil {Button("Open prepared files & publish receipt"){model.showFiles()}}
                if model.canResume,model.receipt==nil {Button("Review / resume prepared kit"){model.resume()}}
                Text("Partial failures retain a receipt with object IDs and leave policies requested disabled. Rebuild/review to resume; uncertain writes are not retried automatically. Verify your managed pilot before broader rollout.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(28).frame(maxWidth:1250,alignment:.leading)}
        .sheet(item:modal){value in
            switch value {
            case .success(let report):JamfPublishSuccessView(report:report,showFiles:{model.showFiles()})
            case .names(let review):JamfNameEditorView(review:review,model:model)
            case .renamed(let result):JamfNameResultView(result:result)
            }
        }
        .onChange(of:model.nameResult?.id){_,_ in if let bindings=model.nameResult?.bindings {store.document.jamfObjectBindings=bindings}}
    }
}
