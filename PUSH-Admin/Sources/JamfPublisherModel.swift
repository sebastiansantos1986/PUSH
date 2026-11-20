// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import AppKit
import Combine

@MainActor
final class JamfPublisherModel:ObservableObject {
    @Published var connection=JamfPublisherConnection()
    @Published var secret=""
    @Published var rememberSecret=true
    @Published var busy=false
    @Published var status="Connect to prepare a read-only server check. Nothing is published automatically."
    @Published var snapshot:JamfPublisherSnapshot?
    @Published var selectedGroupID=0 {didSet{plan=nil;receipt=nil}}
    @Published var clientOverride:URL? {didSet{plan=nil;receipt=nil}}
    @Published var useBundledMist=true {didSet{plan=nil;receipt=nil}}
    @Published var mistPackage:URL? {didSet{plan=nil;receipt=nil}}
    @Published var plan:JamfPublisherPlan?
    @Published var receipt:JamfPublisherReceipt?
    @Published var successReport:JamfPublishSuccess?
    @Published var preparedFolder:URL?
    @Published var nameReview:JamfNameReview?
    @Published var nameResult:JamfNameResult?
    private var publisher:JamfPublisher?
    private var resumePlan:JamfPublisherPlan?
    var canResume:Bool {resumePlan != nil && connected && !busy}
    var connected:Bool {publisher != nil && snapshot != nil}
    init(){
        connection.server=UserDefaults.standard.string(forKey:"PUSHJamfServer") ?? ""
        connection.clientID=UserDefaults.standard.string(forKey:"PUSHJamfClientID") ?? ""
    }
    static func fingerprint(_ document:ConfigDocument)->String {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        return (try? encoder.encode(document)).map(DeploymentBundle.digest) ?? ""
    }
    func savedSecret(){do{_=try connection.validatedURL();secret=try JamfPublisherKeychain.read(connection:connection);status="Saved secret loaded for this server/client. Choose Check connection."}catch{status=error.localizedDescription}}
    func forgetSecret(){do{_=try connection.validatedURL();try JamfPublisherKeychain.remove(connection:connection);secret="";disconnect();status="Saved API secret removed and disconnected from Jamf."}catch{status=error.localizedDescription}}
    func connect(){
        guard !busy else{return};busy=true
        Task {
            defer{busy=false}
            do {
                let origin=try connection.validatedURL();connection.server=origin.absoluteString
                let api=try JamfPublisherAPI(connection:connection,secret:secret)
                let publisherRoot=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("PUSH Admin/Publisher")
                let service=JamfPublisher(api:api,receiptSearchRoot:publisherRoot)
                service.progress={ [weak self] text in Task { @MainActor in self?.status=text }}
                status="Checking Jamf version, cloud distribution and read access…"
                let result=try await service.inspect()
                if rememberSecret {try JamfPublisherKeychain.save(secret,connection:connection)}
                publisher=service;snapshot=result;plan=nil;receipt=nil;secret=""
                UserDefaults.standard.set(connection.server,forKey:"PUSHJamfServer");UserDefaults.standard.set(connection.clientID,forKey:"PUSHJamfClientID")
                status="Connected to Jamf Pro \(result.version) · \(result.distribution). Read access checked. Jamf validates write permissions when you publish."
            }catch{publisher=nil;snapshot=nil;status=error.localizedDescription}
        }
    }
    func disconnect(){guard !busy else{return};let old=publisher;publisher=nil;snapshot=nil;plan=nil;resumePlan=nil;receipt=nil;nameReview=nil;nameResult=nil;successReport=nil;secret="";Task{await old?.api.disconnect()};status="Disconnected. Saved secrets remain in Keychain unless you choose Forget saved secret."}
    func choosePackage(mist:Bool){
        let panel=NSOpenPanel();panel.allowedContentTypes=[.init(filenameExtension:"pkg")!];panel.canChooseDirectories=false;panel.allowsMultipleSelection=false
        panel.message=mist ? "Choose your approved flat Mist installer package. It must install a root-protected Mist executable in a supported path.":"Choose your signed production PUSH Client 1.16.7 package, or use the bundled client for local testing."
        guard panel.runModal() == .OK,let url=panel.url else{return}
        if mist {mistPackage=url}else{clientOverride=url}
    }
    func review(document:ConfigDocument,project:UUID,wallpaperFolder:URL?=nil){
        guard !busy,let publisher,let snapshot else{return}
        busy=true;plan=nil;receipt=nil
        let frozen=document,settings=document.selfServiceSettings ?? SelfServiceSettings(),deployment=document.jamfDeploymentSettings ?? JamfDeploymentSettings(),hash=Self.fingerprint(document)
        let group=snapshot.groups.first{$0.id==selectedGroupID}
        let mist:URL?
        do{mist=try mistPackage ?? ((useBundledMist && deployment.needsMist) ? JamfBundledDependencies.mist():nil)}catch{busy=false;status=error.localizedDescription;return}
        guard selectedGroupID==0 || group != nil else {busy=false;status="Choose a current pilot group.";return}
        guard let client=clientOverride ?? Bundle.main.url(forResource:"PUSH-Client-1.16.7",withExtension:"pkg") else {busy=false;status="The matching client package is missing. Reinstall Admin.";return}
        Task {
            defer{busy=false}
            do {
                let support=try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
                let parent=support.appendingPathComponent("PUSH Admin/Publisher")
                try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                let kit=parent.appendingPathComponent("review-"+UUID().uuidString)
                try deployment.validate()
                status="Building the configured Jamf kit for review. No Jamf configuration is being changed…"
                let defaultImage:NSImage?
                let symbol=frozen.setupValue("ui.sfSymbolName")
                if !symbol.isEmpty {defaultImage=NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:128,weight:.semibold))?.withSymbolConfiguration(.init(paletteColors:[.systemBlue]))}
                else {defaultImage=Bundle.main.url(forResource:"InstallAssistant",withExtension:"icns").flatMap{NSImage(contentsOf:$0)}}
                let iconBytes=try defaultImage?.tiffRepresentation.map{try BrandingImage.normalizedPNG($0)}
                try await Task.detached {
                    try JamfDeploymentKit.write(document:frozen,settings:settings,deployment:deployment,client:client,to:kit,wallpaperFolder:wallpaperFolder)
                    if let mist {
                        try FileManager.default.copyItem(at:mist,to:kit.appendingPathComponent("Approved-Mist.pkg"))
                        if DeploymentBundle.digest(try Data(contentsOf:mist))==JamfBundledDependencies.mistSHA256 {
                            for name in ["Mist-CLI-LICENSE.txt","Mist-CLI-Provenance.json"] {if let url=Bundle.main.url(forResource:(name as NSString).deletingPathExtension,withExtension:(name as NSString).pathExtension) {try FileManager.default.copyItem(at:url,to:kit.appendingPathComponent(name))}}
                        }
                    }
                    let icon=kit.appendingPathComponent("Self-Service-Icon.png")
                    if !FileManager.default.fileExists(atPath:icon.path),let iconBytes {try iconBytes.write(to:icon)}
                    let manifest=kit.appendingPathComponent("manifest.json")
                    var object=try JSONSerialization.jsonObject(with:Data(contentsOf:manifest)) as! [String:Any]
                    let entries=try FileManager.default.contentsOfDirectory(at:kit,includingPropertiesForKeys:nil).filter{$0.lastPathComponent != "manifest.json"}.map{["path":$0.lastPathComponent,"sha256":DeploymentBundle.digest(try Data(contentsOf:$0))]}.sorted{$0["path"]!<$1["path"]!}
                    object["files"]=entries
                    try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]).write(to:manifest,options:.atomic)
                }.value
                preparedFolder=kit
                plan=try await publisher.prepare(kit:kit,project:project,settings:settings,group:group,draftHash:hash,mistURL:mist==nil ? nil:kit.appendingPathComponent("Approved-Mist.pkg"),bindings:frozen.jamfObjectBindings,deployment:deployment)
                resumePlan=plan
                status="Review ready. No Jamf policies, scripts, groups or packages were written. Publish creates/updates the reviewed setup disabled."
            }catch{status=error.localizedDescription}
        }
    }
    func resume(){
        guard !busy,let publisher,let previous=resumePlan else{return};busy=true;receipt=nil
        Task {defer{busy=false};do{
            plan=try await publisher.prepare(kit:previous.kit,project:previous.project,settings:previous.settings,group:previous.group,draftHash:previous.draftHash,mistURL:previous.mist?.url,deployment:previous.deployment)
            resumePlan=plan;status="Server review refreshed using the SAME prepared package files. Review and choose Publish disabled setup to resume; available verified packages are reused."
        }catch{status=error.localizedDescription}}
    }
    func publish(){
        guard !busy,let publisher,let plan else{return};busy=true
        Task {defer{busy=false};do{receipt=try await publisher.publish(plan);status=receipt!.message;successReport=JamfPublishSuccess(plan:plan,receipt:receipt!)}catch{status=error.localizedDescription;self.plan=nil;receipt=nil}}
    }
    func enable(){
        guard !busy,let publisher,let plan,let receipt else{return}
        let alert=NSAlert();alert.messageText="Enable this reviewed pilot?"
        alert.informativeText="Server: \(plan.connection.server)\nGroup: \(plan.scopeName)\n\n"+plan.deployment.summary+"\n\n"+(plan.deployment.mode.requiresCampaign ? "The campaign installs its configured client at check-in, replaces YAML after backup and starts live monitoring; reminders and deadline installation can follow. Deploy management approvals and verify a pilot first. Self Service repairs use a separate on-demand installer that preserves existing policy and monitoring.":"Only a user selecting a Self Service offer starts this workflow. Missing or outdated prerequisites are repaired on demand and verified before continuing. Existing configuration, state, monitoring and Keychain storage are preserved. No check-in installation or history reset is required.")
        alert.addButton(withTitle:"Enable Pilot");alert.addButton(withTitle:"Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else{return}
        busy=true;Task{defer{busy=false};do{self.receipt=try await publisher.enablePilot(plan,receipt:receipt);status=self.receipt!.message;successReport=JamfPublishSuccess(plan:plan,receipt:self.receipt!)}catch{status=error.localizedDescription;self.receipt=nil;self.plan=nil}}
    }
    func loadNames(project:UUID?){
        guard !busy,let publisher,let project else {status="Connect and publish this workflow once before editing its names.";return}
        busy=true
        Task{defer{busy=false};do{
            let records=JamfPublishedRecord.records(root:publisher.receiptSearchRoot,kit:preparedFolder,server:publisher.api.base.absoluteString,project:project)
            guard let record=records.first(where:{$0.receipt.verified}) else {throw JamfPublisherError("No verified published setup was found for this draft/server. Publish it first, then edit its names.")}
            nameReview=try await JamfNameEditor(api:publisher.api).review(record:record)
            status="Published names loaded by Jamf ID. Review your edits before saving."
        }catch{status=error.localizedDescription}}
    }
    func saveNames(_ review:JamfNameReview,policies:[Int:String],group:String){
        guard !busy,let publisher else{return};busy=true
        Task{defer{busy=false};do{
            let result=try await JamfNameEditor(api:publisher.api).apply(review,policyNames:policies,groupName:group)
            nameReview=nil;nameResult=result;plan=nil;receipt=nil;resumePlan=nil;successReport=nil
            if var snapshot=self.snapshot {snapshot.groups=snapshot.groups.map{$0.id==result.groupID ? .init(id:$0.id,name:result.group):$0};self.snapshot=snapshot}
            status="Names updated on the same Jamf IDs. Policy settings, group criteria and membership were preserved. Build/review again for further workflow changes."
        }catch{status=error.localizedDescription}}
    }
    func showSuccess(){if let plan,let receipt {successReport=JamfPublishSuccess(plan:plan,receipt:receipt)}}
    func showFiles(){if let preparedFolder {NSWorkspace.shared.open(preparedFolder)}}
}
