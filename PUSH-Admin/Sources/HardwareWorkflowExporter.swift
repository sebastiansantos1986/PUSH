// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import AppKit

enum HardwareWorkflowExporter {
    static let guide="""
    PUSH Tahoe inventory — Developer: Sebastian Santos
    The configured full client includes the Tahoe reporting helper when selected.
    For an audit-only export, deploy PUSH-Tahoe-Readiness.pkg first.
    Create a Jamf String computer Extension Attribute named PUSH Tahoe Readiness
    using the supplied script, then update inventory. Group exact results:
    Tahoe supported / Tahoe unsupported - replacement review / Unverified - IT review /
    Tahoe supported - OS below PUSH minimum / Above Tahoe - do not downgrade.
    Exclude unsupported and unverified Macs from the update policy. Hardware that
    supports Tahoe but runs below macOS 14 needs an IT-assisted OS bridge before
    installing the full PUSH client. Do not label it replacement-only for an old OS.
    Reporting never downloads an installer, prompts for a password, or restarts.
    Native inventory and update authorization require your managed pilot.
    """
    static func validateCatalog(_ catalog:AppleHardwareCatalog,now:Date=Date())throws {
        guard catalog.source=="https://gdmf.apple.com/v2/pmv",now.timeIntervalSince(catalog.fetchedAt)>=(-300),now.timeIntervalSince(catalog.fetchedAt)<=30*86400,catalog.releases.contains(where:{$0.version.hasPrefix("26.") && $0.posted<=now && $0.expires>now}) else {throw DeploymentBundleError.invalid("Refresh Apple hardware data before building a Tahoe inventory workflow.")}
    }
    static func unpack(_ data:Data,stage:URL)throws->URL {
        let fm=FileManager.default,package=stage.appendingPathComponent("hardware-source.pkg"),folder=stage.appendingPathComponent("hardware-component")
        guard data.count<2_097_152 else {throw DeploymentBundleError.invalid("The bundled hardware reporter is invalid.")}
        try data.write(to:package)
        try ConfiguredClientBuilder.command("/usr/sbin/pkgutil",["--expand-full",package.path,folder.path],folder:stage)
        guard !fm.fileExists(atPath:folder.appendingPathComponent("Scripts").path),let info=try? String(contentsOf:folder.appendingPathComponent("PackageInfo")),info.contains("identifier=\"com.push.tahoe.readiness\""),info.contains("version=\"1.0.0\"") else {throw DeploymentBundleError.invalid("The bundled hardware reporter contains unexpected installation actions.")}
        let payload=folder.appendingPathComponent("Payload")
        try ConfiguredClientBuilder.checkPayload(payload,allowed:["Library/Management/PUSH/Tahoe-Campaign/push-tahoe-readiness","Library/Management/PUSH/Tahoe-Campaign/AppleHardwareCatalog.json"])
        return payload
    }
    static func writeAudit(package:Data,script:Data,catalog:AppleHardwareCatalog,to destination:URL)throws {
        try validateCatalog(catalog)
        let fm=FileManager.default
        guard !fm.fileExists(atPath:destination.path) else {throw DeploymentBundleError.invalid("Choose a new output folder.")}
        let stage=fm.temporaryDirectory.appendingPathComponent("push-audit-"+UUID().uuidString);try fm.createDirectory(at:stage,withIntermediateDirectories:true);defer{try? fm.removeItem(at:stage)}
        let payload=try unpack(package,stage:stage)
        try JSONEncoder().encode(catalog).write(to:payload.appendingPathComponent("Library/Management/PUSH/Tahoe-Campaign/AppleHardwareCatalog.json"))
        let output=stage.appendingPathComponent("output");try fm.createDirectory(at:output,withIntermediateDirectories:true)
        try ConfiguredClientBuilder.command("/usr/bin/pkgbuild",["--root",payload.path,"--ownership","recommended","--identifier","com.push.tahoe.readiness","--version","1.0.0","--install-location","/",output.appendingPathComponent("PUSH-Tahoe-Readiness.pkg").path],folder:stage)
        try script.write(to:output.appendingPathComponent("Jamf-EA-Tahoe-Readiness.sh"));try Data(guide.utf8).write(to:output.appendingPathComponent("READ-ME-FIRST.txt"))
        var files:[[String:String]]=[]
        for file in try fm.contentsOfDirectory(at:output,includingPropertiesForKeys:nil) {files.append(["path":file.lastPathComponent,"sha256":DeploymentBundle.digest(try Data(contentsOf:file))])}
        try JSONSerialization.data(withJSONObject:["developer":"Sebastian Santos","reportingOnly":true,"files":files],options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("manifest.json"))
        try fm.moveItem(at:output,to:destination)
    }
}
extension AdminStore {
    func tahoeReporterData()throws->(Data,Data) {
        guard let pkg=Bundle.main.url(forResource:"PUSH-Tahoe-Readiness",withExtension:"pkg"),let script=Bundle.main.url(forResource:"PUSH-Tahoe-Readiness-EA",withExtension:"sh") else {throw DeploymentBundleError.invalid("Reinstall the matching PUSH Admin: its hardware reporter is missing.")}
        return (try Data(contentsOf:pkg),try Data(contentsOf:script))
    }
    func exportTahoeAudit() {
        do {
            let (pkg,script)=try tahoeReporterData()
            guard let catalog=AppleHardwareReader.bundled() else {throw DeploymentBundleError.invalid("Refresh Apple hardware data before exporting.")}
            let panel=NSSavePanel();panel.nameFieldStringValue="PUSH-Tahoe-Hardware-Audit";panel.message="Choose a new folder for the reporting-only installer and Jamf inventory script. No apps or updates run now."
            guard panel.runModal() == .OK,let url=panel.url else{return}
            try HardwareWorkflowExporter.writeAudit(package:pkg,script:script,catalog:catalog,to:url)
            notice="Built the reporting-only hardware workflow. Its READ-ME-FIRST explains the inventory setup. Nothing was installed or activated."
        }catch{notice=error.localizedDescription}
    }
}

extension ConfiguredClientBuilder {
    /// Inspect a full signed client package, never run its apps or installer.
    static func productionRestartIdentity(client:URL)throws->RestartProfileIdentity {
        let fm=FileManager.default
        guard client.pathExtension=="pkg" else {throw DeploymentBundleError.invalid("Choose the full production PUSH client package.")}
        let stage=fm.temporaryDirectory.appendingPathComponent("push-signature-"+UUID().uuidString);try fm.createDirectory(at:stage,withIntermediateDirectories:true);defer{try? fm.removeItem(at:stage)}
        let expanded=stage.appendingPathComponent("client")
        try command("/usr/sbin/pkgutil",["--expand-full",client.path,expanded.path],folder:stage)
        let root=expanded.appendingPathComponent("push-engine.pkg/Payload")
        try checkPayload(root,allowed:["Library/Management/PUSH/push-cli","Library/Management/PUSH/push-ui.app","Library/Management/PUSH/Local-Test","Library/Management/PUSH/assets","Library/Management/PUSH/user-request-protocol.json","Library/Management/PUSH/PUSH Major Upgrade Demo.app","Library/Management/PUSH/PUSH Notices.app"])
        return try RestartProfileIdentity.inspect(root.appendingPathComponent("Library/Management/PUSH/push-cli"))
    }
}

extension AdminStore {
    func confirmSuggestedMessages(recipe:WorkflowRecipe) {
        let alert=NSAlert();alert.messageText="Use the suggested update messages?"
        alert.informativeText="This replaces the seven update messages and the popup title in this draft. Your icon, organization, Keychain authorization, deadline and deployment rules remain as selected. Preview before building."
        alert.addButton(withTitle:"Use Suggested Messages");alert.addButton(withTitle:"Cancel")
        if alert.runModal() == .alertFirstButtonReturn {document=WorkflowWording.applySet(recipe:recipe,to:document);notice="Suggested copy added to the draft. Preview or simulate it before building."}
    }
}
