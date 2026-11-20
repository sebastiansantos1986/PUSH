// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import AppKit

/// A comparison record contains policy values and asset hashes, never image bytes or Keychain data.
struct WorkflowBaseline:Codable {
    let name:String
    let capturedAt:Date
    let values:[String:String]
    static func capture(_ document:ConfigDocument,name:String,assets:[String:Data]=[:],now:Date=Date())->Self {
        let safe=ConfigDocument.load(document.yaml,name:name)
        var ids=Set(configGroups.flatMap(\.fields).map(\.id)),section=""
        for line in safe.source.components(separatedBy:.newlines) {
            let t=line.trimmingCharacters(in:.whitespaces)
            if t.isEmpty || t.hasPrefix("#") {continue}
            if line.first != " " && t.hasSuffix(":") {section=String(t.dropLast());continue}
            if line.prefix(while:{$0==" "}).count==2,let colon=t.firstIndex(of:":"),!section.isEmpty {ids.insert(section+"."+String(t[..<colon]))}
        }
        var values=Dictionary(uniqueKeysWithValues:ids.sorted().compactMap{key in safe.value(key).map{(key,$0)}})
        if let recipe=document.workflowRecipe {
            values["workflow.timeZone"]=recipe.timeZoneID
            values["workflow.tahoeInventory"]=recipe.includeTahoeAudit ? "true":"false"
        }
        // Selected image bytes take priority; they can change without the deployed path changing.
        if safe.value("ui.logoPath")==deployedPopupLogoPath,let logo=document.logoImageData {values["asset.popupLogo"]=DeploymentBundle.digest(logo)}
        for (path,bytes) in assets where path=="assets/popup-logo.png" && safe.value("ui.logoPath")==deployedPopupLogoPath {values["asset.popupLogo"]=DeploymentBundle.digest(bytes)}
        for (role,ref) in document.wallpaperAssets ?? [:] where ref.valid {let key=role=="noncompliant" ? "compliance.nonCompliantWallpaper":"compliance.compliantWallpaper";if document.setupValue(key)==ref.deployedPath {values["asset.wallpaper."+role]=ref.digest}}
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];if let data=try? encoder.encode(document.majorOfferSettings ?? MajorOfferSettings()) {values["workflow.majorOfferPresentationHash"]=DeploymentBundle.digest(data)}
        if let data=try? encoder.encode(document.selfServiceSettings ?? SelfServiceSettings()) {values["workflow.selfServiceHash"]=DeploymentBundle.digest(data)}
        return .init(name:name,capturedAt:now,values:values)
    }
}
struct WorkflowChange:Identifiable {
    let id:String,title:String,before:String,after:String
    var affectsEnforcement:Bool {id.hasPrefix("auth.") || id.hasPrefix("schedule.") || ((id.hasPrefix("update.") || id.hasPrefix("apps.") || id.hasPrefix("auto.")) && id.lowercased().contains("deadline")) || id=="debug.dryRun" || id=="auto.enabled" || id=="auto.trackLatest" || id=="auto.maximumMajorVersion" || id=="auto.enforceMinimumMajorVersion" || id=="update.targetVersion" || id=="update.autoInstallAfterDeadline" || id=="update.silentInstallAfterDeadline" || id=="update.forceRestartAfterInstall" || id=="uptime.enabled"}
}
struct WorkflowComparison {
    let baseline:WorkflowBaseline?
    let current:WorkflowBaseline
    var changes:[WorkflowChange] {
        guard let baseline else{return []}
        let titles=Dictionary(uniqueKeysWithValues:configGroups.flatMap(\.fields).map{($0.id,$0.title)})
        return Set(baseline.values.keys).union(current.values.keys).sorted().compactMap{key in
            let old=baseline.values[key],new=current.values[key]
            guard old != new else{return nil}
            let title=titles[key] ?? (key.hasPrefix("asset.") ? "Image content · "+String(key.dropFirst(6)):key)
            return .init(id:key,title:title,before:old ?? "Not present",after:new ?? "Not present")
        }.sorted{a,b in a.affectsEnforcement != b.affectsEnforcement ? a.affectsEnforcement:a.id<b.id}
    }
    var report:String {
        var lines=["PUSH workflow change review","Developer: Sebastian Santos — PUSH-DEV-SEBASTIAN-SANTOS","Current: "+current.name,"Captured: "+ISO8601DateFormatter().string(from:current.capturedAt)]
        if let baseline {
            lines += ["Compared with: "+baseline.name,"Baseline captured: "+ISO8601DateFormatter().string(from:baseline.capturedAt),"Changed settings/assets: \(changes.count)"]
            for change in changes {lines += ["",change.title+" ["+change.id+"]"+(change.affectsEnforcement ? " — review enforcement":""),"Before: "+change.before,"After: "+change.after]}
        } else {lines += ["No comparison baseline selected. This is a first-package review, not a claim that nothing changed."]}
        lines += ["","Compares supported policy values, additional simple YAML fields and selected image content. Does not compare installer binaries, management profile identities, fleet state or Keychain passwords. A saved workflow is not proof of deployment."]
        return lines.joined(separator:"\n")+"\n"
    }
}
struct SavedWorkflowInfo:Codable,Identifiable {
    let id:UUID,name:String,savedAt:Date
}
struct SavedWorkflow:Codable,Identifiable {
    let formatVersion:Int
    let id:UUID
    let name:String
    let savedAt:Date
    let document:ConfigDocument
    let wallpaperData:[String:Data]
    var info:SavedWorkflowInfo {.init(id:id,name:name,savedAt:savedAt)}
    init(name:String,document:ConfigDocument,wallpaperData:[String:Data],now:Date=Date())throws {
        let title=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !title.isEmpty,title.count<=100 else {throw AdminError.message("Give this saved workflow a name of 1–100 characters.")}
        var safe=ConfigDocument.load(document.yaml,name:title)
        safe.workflowRecipe=document.workflowRecipe;safe.majorOfferSettings=document.majorOfferSettings;safe.selfServiceSettings=document.selfServiceSettings;safe.jamfDeploymentID=document.jamfDeploymentID;safe.jamfObjectBindings=document.jamfObjectBindings;safe.jamfDeploymentSettings=document.jamfDeploymentSettings
        safe.logoImageData=safe.setupValue("ui.logoPath")==deployedPopupLogoPath ? document.logoImageData:nil;safe.logoImageName=document.logoImageName
        safe.wallpaperAssets=document.wallpaperAssets?.filter{role,ref in (role=="noncompliant" || role=="compliant") && safe.setupValue(role=="noncompliant" ? "compliance.nonCompliantWallpaper":"compliance.compliantWallpaper")==ref.deployedPath}
        // No comparison chain is archived. Loading establishes a fresh baseline.
        safe.workflowBaseline=nil
        formatVersion=1;id=UUID();self.name=title;savedAt=now;self.document=safe;self.wallpaperData=wallpaperData
        try validate()
    }
    func validate()throws {
        guard formatVersion==1,!name.isEmpty,name.count<=100,document.formatIssues.isEmpty,document.workflowBaseline==nil else {throw AdminError.message("This saved workflow has an unsupported or invalid format.")}
        guard ConfigDocument.load(document.source,name:name).source==document.source,!document.edits.contains(where:{ConfigDocument.sensitive.contains(String($0.key.split(separator:".").last ?? "")) && !$0.value.isEmpty}) else {throw AdminError.message("Known plaintext credential fields cannot be stored in a reusable workflow.")}
        let logoPath=document.setupValue("ui.logoPath")
        guard logoPath.isEmpty || logoPath==deployedPopupLogoPath else {throw AdminError.message("Choose the custom popup icon again so it is included in the saved workflow.")}
        if logoPath==deployedPopupLogoPath {
            guard let bytes=document.logoImageData,bytes.count<=1_048_576,NSImage(data:bytes) != nil else {throw AdminError.message("Choose the custom popup icon again before saving this workflow.")}
        }
        var expected=Set<String>()
        for role in ["noncompliant","compliant"] {
            let key=role=="noncompliant" ? "compliance.nonCompliantWallpaper":"compliance.compliantWallpaper"
            let path=document.setupValue(key)
            if path.isEmpty || path==WallpaperPolicy.defaultImage {continue}
            guard let ref=document.wallpaperAssets?[role],ref.valid,ref.role==role,ref.deployedPath==path,let bytes=wallpaperData[ref.fileName],bytes.count<=20_971_520,WallpaperAssetImage.digest(bytes)==ref.digest,NSImage(data:bytes) != nil else {throw AdminError.message("Choose the custom wallpaper again before saving or loading this workflow.")}
            expected.insert(ref.fileName)
        }
        guard Set(wallpaperData.keys)==expected else {throw AdminError.message("The saved workflow contains unexpected image data.")}
    }
    func restoredDocument()->ConfigDocument {
        var safe=ConfigDocument.load(document.yaml,name:name)
        safe.workflowRecipe=document.workflowRecipe;safe.majorOfferSettings=document.majorOfferSettings;safe.selfServiceSettings=document.selfServiceSettings;safe.jamfDeploymentID=document.jamfDeploymentID;safe.jamfObjectBindings=document.jamfObjectBindings;safe.jamfDeploymentSettings=document.jamfDeploymentSettings
        safe.logoImageData=document.logoImageData;safe.logoImageName=document.logoImageName;safe.wallpaperAssets=document.wallpaperAssets
        safe.workflowBaseline=WorkflowBaseline.capture(safe,name:"Saved workflow: "+name,now:savedAt)
        return safe
    }
}
struct WorkflowLibrary {
    let folder:URL
    private func file(_ id:UUID)->URL {folder.appendingPathComponent(id.uuidString+".json")}
    private func bytes(_ url:URL)throws->Data {
        let props=try url.resourceValues(forKeys:[.isSymbolicLinkKey,.fileSizeKey,.isRegularFileKey])
        guard props.isSymbolicLink != true,props.isRegularFile==true,(props.fileSize ?? Int.max)<=80_000_000 else {throw AdminError.message("A saved workflow is unreadable or too large.")}
        return try Data(contentsOf:url)
    }
    func list()throws->[SavedWorkflowInfo] {
        guard FileManager.default.fileExists(atPath:folder.path) else{return []}
        let urls=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[]).filter{$0.pathExtension=="json"}
        return try urls.map{url in
            let info=try JSONDecoder().decode(SavedWorkflowInfo.self,from:bytes(url))
            guard url.lastPathComponent==info.id.uuidString+".json" else {throw AdminError.message("A saved workflow has an invalid identifier.")}
            return info
        }.sorted{$0.savedAt == $1.savedAt ? $0.id.uuidString<$1.id.uuidString:$0.savedAt>$1.savedAt}
    }
    func save(_ record:SavedWorkflow)throws {
        try record.validate()
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        // UUID filenames and withoutOverwriting preserve every previously saved copy.
        let data=try JSONEncoder().encode(record)
        guard data.count<=80_000_000 else {throw AdminError.message("The workflow images are too large to save together.")}
        try data.write(to:file(record.id),options:.withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file(record.id).path)
    }
    func load(_ id:UUID)throws->SavedWorkflow {
        let record=try JSONDecoder().decode(SavedWorkflow.self,from:bytes(file(id)))
        guard record.id==id else {throw AdminError.message("The saved workflow identifier does not match its file.")}
        try record.validate();return record
    }
}
