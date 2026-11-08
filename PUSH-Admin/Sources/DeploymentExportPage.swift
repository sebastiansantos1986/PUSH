// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit

struct DeploymentExportCard:View {
    @EnvironmentObject var store:AdminStore
    @State private var teamID=""
    @State private var scope:ClientPackageScope = .full
    @State private var activation:ClientActivation = .paused
    @State private var restartIdentity:RestartProfileIdentity?
    var body:some View {
        AdminCard {
            Label("Build the complete client installer",systemImage:"shippingbox.fill").font(.headline)
            Text("Build one installer with PUSH, JamfCheckIn, this draft’s YAML and selected images. PUSH Admin stays on IT workstations. MDM profiles accompany the installer as separate files.").font(.callout).foregroundStyle(.secondary)
            TextField("Apple Developer Team ID · optional for local testing",text:$teamID).textFieldStyle(.roundedBorder)
            Text("A Team ID narrows background-item approval; it does not sign the installer. The included local client is ad-hoc signed. Use your verified Developer ID release for fleet deployment.").font(.caption).foregroundStyle(.secondary)
            if store.document.setupFlag("uptime.enabled") {
                Button("Choose production-signed PUSH executable…") {
                    let panel=NSOpenPanel();panel.canChooseDirectories=false;panel.allowsMultipleSelection=false;panel.message="Inspect the signed push-cli from your production release. This never runs it."
                    guard panel.runModal() == .OK,let url=panel.url else{return}
                    do {let identity=try RestartProfileIdentity.inspect(url);restartIdentity=identity;teamID=identity.teamID;store.notice="Verified the selected signature. The optional restart approval will match that production build, not the bundled ad-hoc local client."}catch{restartIdentity=nil;store.notice=error.localizedDescription}
                }
                Text(restartIdentity == nil ? "Restart enforcement requires a verified signing identity before export. Local ad-hoc binaries cannot provide a stable approval.":"Production signing identity selected. Verify the matching signed release and TCC attribution on a managed pilot.").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Package contents",selection:$scope){ForEach(ClientPackageScope.allCases){Text($0.title).tag($0)}}.onChange(of:scope){_,value in if value == .majorOfferOnly {activation = .paused}}
            if scope == .majorOfferOnly {Text("Major-only preview: no JamfCheckIn or enforcement monitors. The upgrade flow stays debug-only; single informational popups and hardware checks are available.").font(.callout).foregroundStyle(.secondary)}
            Picker("After installation",selection:$activation){ForEach(ClientActivation.allCases){mode in Text(mode.title).tag(mode)}}.pickerStyle(.menu).disabled(scope == .majorOfferOnly)
            Text(activation == .paused ? "For pilots: the approved policy is installed, and monitoring stays paused.":"For reviewed live deployments: installation starts selected monitors. First checks wait five minutes, then may notify, download, install or restart according to your policy.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Button(store.isBuildingDeployment ? "Building installer…":"Build complete client installer…"){store.buildConfiguredClient(teamID:teamID,restartIdentity:restartIdentity,activation:activation,scope:scope)}.buttonStyle(.borderedProminent).disabled(store.isBuildingDeployment || !store.document.problems.isEmpty)
                if store.isBuildingDeployment {ProgressView().controlSize(.small)}
            }
            Text("Building never installs the result or starts PUSH on this Mac. Future installation replaces the previous YAML after backup. Select the matching signed release before fleet rollout.").font(.caption).foregroundStyle(.secondary)
            Button("Export deployment bundle…"){store.exportDeploymentBundle(teamID:teamID,restartIdentity:restartIdentity)}.disabled(store.isBuildingDeployment || !store.document.problems.isEmpty)
            Text("Advanced: the separate deployment bundle keeps client, policy and activation as separate steps.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
extension AdminStore {
    func exportDeploymentBundle(teamID:String,restartIdentity:RestartProfileIdentity?=nil) {
        guard document.problems.isEmpty else {notice="Resolve draft validation issues before exporting.";return}
        guard let client=Bundle.main.url(forResource:"PUSH-Client-1.11.0",withExtension:"pkg") else {notice="The matching client installer is missing from PUSH Admin. Reinstall version 1.1.0.";return}
        do {
            let input=try deploymentInput(teamID:teamID,restartIdentity:restartIdentity)
            let panel=NSSavePanel();panel.nameFieldStringValue="PUSH-Deployment-"+Date().formatted(.iso8601.year().month().day().dateSeparator(.dash));panel.title="Export a new deployment folder";panel.message="Choose a new folder name. Existing exports are never replaced.";panel.canCreateDirectories=true
            guard panel.runModal() == .OK,let destination=panel.url else{return}
            try DeploymentBundle.write(input,client:client,to:destination)
            notice="Exported the client installer, policy, images and management profiles. No settings or services changed. Read READ-ME-FIRST before deploying."
        } catch {notice="Deployment export failed: "+error.localizedDescription}
    }
}

extension AdminStore {
    func deploymentInput(teamID:String,restartIdentity:RestartProfileIdentity?,scope:ClientPackageScope = .full)throws->DeploymentBundleInput {
        if scope == .majorOfferOnly {
            return .init(yaml:ClientPackageScope.majorPolicy.yaml,assets:[:],teamID:teamID,majorSettings:try majorSettings.validated(),hardwareCatalog:AppleHardwareReader.bundled())
        }
        if document.setupFlag("uptime.enabled"),restartIdentity?.valid(for:teamID) != true {throw DeploymentBundleError.invalid("Restart enforcement uses System Events automation. Select the matching production-signed push-cli to generate its restricted approval, or disable restart enforcement for local testing.")}
        var images:[String:Data]=[:]
        let logo=document.setupValue("ui.logoPath")
        if !logo.isEmpty {
            guard logo==deployedPopupLogoPath,let data=document.logoImageData else {throw DeploymentBundleError.invalid("Choose the custom popup logo again in Popup Studio so the export includes it.")}
            images["assets/popup-logo.png"]=data
        }
        for role in ["noncompliant","compliant"] {
            let key=role=="noncompliant" ? "compliance.nonCompliantWallpaper":"compliance.compliantWallpaper"
            let path=document.setupValue(key)
            if path.isEmpty {continue}
            if path==WallpaperPolicy.defaultImage {
                guard let url=Bundle.main.url(forResource:"PUSH-NonCompliant",withExtension:"png") else {throw DeploymentBundleError.invalid("Default wallpaper is missing from this admin installation.")}
                images["assets/wallpapers/PUSH-NonCompliant.png"]=try Data(contentsOf:url)
            } else {
                guard let ref=document.wallpaperAssets?[role],ref.deployedPath==path else {throw DeploymentBundleError.invalid("Choose the custom wallpaper again on the Wallpaper page so the export includes its image.")}
                images["assets/wallpapers/"+ref.fileName]=try WallpaperAssetImage.read(ref,folder:wallpaperAssetDirectory)
            }
        }
        // Sanitize even edited drafts before bundling; never export known credential fields.
        let safe=ConfigDocument.load(document.yaml,name:"Deployment export")
        guard safe.problems.isEmpty else {throw DeploymentBundleError.invalid("The sanitized deployment policy did not validate.")}
        return .init(yaml:safe.yaml,assets:images,teamID:teamID.trimmingCharacters(in:.whitespacesAndNewlines),restartIdentity:document.setupFlag("uptime.enabled") ? restartIdentity:nil,majorSettings:try majorSettings.validated(),hardwareCatalog:AppleHardwareReader.bundled())
    }
    func buildConfiguredClient(teamID:String,restartIdentity:RestartProfileIdentity?,activation:ClientActivation,scope:ClientPackageScope = .full) {
        guard !isBuildingDeployment else{return}
        guard let client=Bundle.main.url(forResource:"PUSH-Client-1.11.0",withExtension:"pkg") else {notice="The embedded client is missing. Reinstall PUSH Admin 1.3.0.";return}
        do {
            let input=try deploymentInput(teamID:teamID,restartIdentity:restartIdentity,scope:scope)
            let reviewed=ConfigDocument.load(input.yaml,name:"Package review")
            try ConfiguredClientBuilder.validate(reviewed,activation:activation)
            let review=NSAlert();review.messageText="Build the reviewed client installer?"
            review.informativeText="Contents: "+scope.title+"\nMode: "+activation.title+"\n\nIncludes the components in the selected profile, reviewed YAML and presentation assets. Installing this package replaces the previous policy after backup.\n\n"+(activation == .monitor ? "Future installation loads live monitors with a five-minute first-check delay. Checks can download, install or restart. MDM profiles and endpoint authorization must be ready first.":"Future installation keeps monitoring paused for pilot review.")+"\n\nBuilding now performs no installation or service activation."
            review.addButton(withTitle:"Build Installer");review.addButton(withTitle:"Cancel")
            guard review.runModal() == .alertFirstButtonReturn else{return}
            let panel=NSSavePanel();panel.nameFieldStringValue="PUSH-Configured-Deployment";panel.title="Choose a new output folder";panel.message="The installer, profiles and review files will be saved together. Existing folders are never replaced.";panel.canCreateDirectories=true
            guard panel.runModal() == .OK,let destination=panel.url else{return}
            isBuildingDeployment=true;notice="Building the reviewed client installer. No installed settings or services are changing."
            Task {
                let result=await Task.detached(priority:.userInitiated){()->String? in
                    do {try ConfiguredClientBuilder.build(input,client:client,activation:activation,scope:scope,to:destination);return nil}catch{return error.localizedDescription}
                }.value
                isBuildingDeployment=false
                notice=result.map{"Installer build failed: "+$0} ?? "Built the selected client profile with reviewed policy and presentation. See its READ-ME-FIRST. Nothing was installed or activated on this Mac."
            }
        }catch {notice="Review before building: "+error.localizedDescription}
    }
}
