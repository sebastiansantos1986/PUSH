// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import AppKit

extension AdminStore {
    var workflowLibrary:WorkflowLibrary {.init(folder:draftURL.deletingLastPathComponent().appendingPathComponent("Saved Workflows",isDirectory:true))}
    func refreshSavedWorkflows() {
        do{savedWorkflows=try workflowLibrary.list();workflowLibraryIssue=""}
        catch{workflowLibraryIssue="Saved workflows could not be read: "+error.localizedDescription}
    }
    private func archivedWorkflow(name:String)throws->SavedWorkflow {
        let recipe=WorkflowRecipe.from(document:document)
        let proposal=recipe.proposed(from:document)
        var images:[String:Data]=[:]
        for role in ["noncompliant","compliant"] {
            let key=role=="noncompliant" ? "compliance.nonCompliantWallpaper":"compliance.compliantWallpaper"
            if let ref=proposal.wallpaperAssets?[role],proposal.setupValue(key)==ref.deployedPath {images[ref.fileName]=try WallpaperAssetImage.read(ref,folder:wallpaperAssetDirectory)}
        }
        return try SavedWorkflow(name:name,document:proposal,wallpaperData:images)
    }
    @discardableResult func saveNamedWorkflow()->UUID? {
        let alert=NSAlert();alert.messageText="Save a reusable workflow"
        alert.informativeText="Saves the effective policy, messages and selected images as a new copy. Existing saved workflows are preserved. Known credential fields are excluded; Keychain passwords are never read."
        let input=NSTextField(frame:NSRect(x:0,y:0,width:360,height:26));input.placeholderString="For example: Required Tahoe update";alert.accessoryView=input
        alert.addButton(withTitle:"Save New Copy");alert.addButton(withTitle:"Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else{return nil}
        do{let record=try archivedWorkflow(name:input.stringValue);try workflowLibrary.save(record);refreshSavedWorkflows();notice="Saved a reusable workflow. No installed policy changed.";return record.id}
        catch{notice=error.localizedDescription;return nil}
    }
    func loadSavedWorkflow(_ id:UUID) {
        do {
            let record=try workflowLibrary.load(id)
            let alert=NSAlert();alert.messageText="Load “"+record.name+"” into this draft?"
            alert.informativeText="Your current draft will be saved as a recovery copy first. The saved workflow is preserved. Review its deadline and live/paused mode before building. Installed settings and Keychain do not change."
            alert.addButton(withTitle:"Load Workflow");alert.addButton(withTitle:"Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else{return}
            let recovery=try archivedWorkflow(name:String(("Before loading: "+record.name).prefix(100)))
            try workflowLibrary.save(recovery)
            try FileManager.default.createDirectory(at:wallpaperAssetDirectory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            for (name,data) in record.wallpaperData {
                // Validated archive filenames are digest-based; never accept arbitrary paths.
                let file=wallpaperAssetDirectory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath:file.path) {
                    let props=try file.resourceValues(forKeys:[.isSymbolicLinkKey])
                    guard props.isSymbolicLink != true,(try Data(contentsOf:file))==data else {throw AdminError.message("A staged wallpaper differs from this saved image. The draft was not replaced.")}
                }else{try data.write(to:file,options:.withoutOverwriting);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)}
            }
            document=record.restoredDocument();importedLiveConfig=false;refreshSavedWorkflows()
            notice="Loaded “"+record.name+"”. The previous draft is saved as a recovery copy. Review the deadline before building."
        }catch{notice=error.localizedDescription;refreshSavedWorkflows()}
    }
    func compareWithSavedWorkflow(_ id:UUID) {
        do{let record=try workflowLibrary.load(id);document.workflowBaseline=record.restoredDocument().workflowBaseline;notice="Comparison uses “"+record.name+"”. Your policy and images were not replaced."}
        catch{notice=error.localizedDescription}
    }
    var workflowComparison:WorkflowComparison {
        let recipe=WorkflowRecipe.from(document:document)
        return .init(baseline:document.workflowBaseline,current:WorkflowBaseline.capture(recipe.proposed(from:document),name:"Current workflow draft"))
    }
}
