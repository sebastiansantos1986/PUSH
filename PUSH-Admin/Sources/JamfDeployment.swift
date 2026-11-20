// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

enum JamfDeploymentMode:String,Codable,CaseIterable,Identifiable {
    case offer,required,both
    var id:String {rawValue}
    var title:String {switch self {case .offer:return "Optional Self Service offers";case .required:return "Required update with reminders";case .both:return "Required update + Self Service offers"}}
    var requiresCampaign:Bool {self != .offer}
    var includesOffers:Bool {self != .required}
}
struct JamfDeploymentSettings:Codable {
    var mode:JamfDeploymentMode = .offer
    var campaign=WorkflowRecipe()
    var wallpaperEnabled:Bool?=nil
    var useWallpaper:Bool {wallpaperEnabled ?? true}
    var needsMist:Bool {mode.includesOffers || (mode.requiresCampaign && campaign.target != .current)}
    init(){campaign.startAfterInstall=true;campaign.hourlyReminders=true;campaign.workingHoursOnly=false;campaign.skipMeetings=false}
    func validate(now:Date=Date())throws {
        guard mode.requiresCampaign else{return}
        guard campaign.tasks==[.macOS],campaign.hasDeadline,campaign.enforceAfterDeadline,campaign.startAfterInstall,campaign.hourlyReminders,!campaign.workingHoursOnly,!campaign.skipMeetings,!campaign.includeTahoeAudit else {throw JamfPublisherError("Required deployment needs the macOS task, a deadline, enforcement and live monitoring, with hourly toasts and reminders allowed every day. Review the required-update settings.")}
        let issues=campaign.issues(now:now)
        guard issues.isEmpty else {throw JamfPublisherError(issues.joined(separator:"; "))}
    }
    func document(from source:ConfigDocument)throws->ConfigDocument {
        try validate()
        var value=campaign.proposed(from:source)
        if campaign.target == .major {value.edits["update.targetVersion"]="\(campaign.major).0"}
        value.edits["update.prepareAtDeadlineWhenLoggedOut"]="true"
        value.edits["update.automaticDeadline"]="";value.edits["update.automaticDeadlineTarget"]=""
        // This deployment configures one macOS campaign. Other scheduled modules
        // are not silently enabled by an unrelated draft.
        value.edits["compliance.wallpaperEnabled"]=String(useWallpaper)
        value.edits["compliance.nonCompliantWallpaper"]=useWallpaper ? (source.setupValue("compliance.nonCompliantWallpaper").isEmpty ? WallpaperPolicy.defaultImage:source.setupValue("compliance.nonCompliantWallpaper")):""
        value.edits["compliance.compliantWallpaper"]=useWallpaper ? source.setupValue("compliance.compliantWallpaper"):""
        value.edits["update.toastIntervalSeconds"]="3600";value.edits["update.nudgeIntervalSeconds"]="86400"
        for item in WorkflowMessage.allCases where source.setupValue(item.key).isEmpty || source.setupValue(item.key)==ConfigDocument.fresh.setupValue(item.key) {value=WorkflowWording.apply(item,recipe:campaign,to:value)}
        let safe=ConfigDocument.load(value.yaml,name:"Required Jamf campaign")
        guard safe.omittedCredentials==0,safe.problems.isEmpty else {throw JamfPublisherError("The campaign contains invalid configuration or plaintext credentials. Review it before packaging.")}
        return value
    }
    func validatePolicy(_ yaml:String)throws {
        let actual=ConfigDocument.load(yaml,name:"Prepared required policy")
        var expected=campaign.proposed(from:actual)
        expected.edits["compliance.wallpaperEnabled"]=String(useWallpaper)
        if campaign.target == .major {expected.edits["update.targetVersion"]="\(campaign.major).0"}
        let keys=["auto.enabled","debug.dryRun","update.autoInstallAfterDeadline","update.toastIntervalSeconds","update.nudgeIntervalSeconds","update.deadline","auto.trackLatest","auto.minorOnly","auto.skipBetas","auto.maximumMajorVersion","auto.enforceMinimumMajorVersion","update.targetVersion","auth.promptUserForInstall","schedule.respectAlertWindow","schedule.skipWeekends","schedule.skipDuringMeetings","schedule.skipInstallDuringScreenShare","debug.testToastIntervalMinutes","debug.testNudgeIntervalMinutes","apps.enabled","entra.enabled","uptime.enabled","compliance.wallpaperEnabled"]
        guard actual.omittedCredentials==0,actual.problems.isEmpty,keys.allSatisfy({actual.setupValue($0)==expected.setupValue($0)}),actual.setupFlag("update.prepareAtDeadlineWhenLoggedOut") else {throw JamfPublisherError("The packaged campaign rules differ from the reviewed required-update workflow. Build/review again.")}
    }
    var summary:String {
        guard mode.requiresCampaign else{return "Optional offers only. No reminder campaign or background monitor is installed by this workflow."}
        return ([mode.title,"Hourly toast: every 3,600 seconds","Daily full reminder: every 86,400 seconds","Reminders allowed 24/7, including weekends; available user session required.","Background check: every 5 minutes; first check waits 5 minutes after installation."]+campaign.summary+["Compliance wallpaper: "+(useWallpaper ? "enabled; rechecked on every eligible macOS run and restored after compliance":"disabled"),"No logged-in user: prepare/download at deadline; notify after login. Authorization, power, storage, hardware and update availability still apply.","Installing the configured client replaces config.yaml after backup and starts live monitoring. Existing runtime state and Keychain storage are preserved."]).joined(separator:"\n")
    }
}
enum JamfDeploymentKit {
    static func write(document:ConfigDocument,settings:SelfServiceSettings,deployment:JamfDeploymentSettings,client:URL,to destination:URL,defaultWallpaper:Data?=nil,wallpaperFolder:URL?=nil)throws {
        try deployment.validate()
        guard deployment.mode.requiresCampaign else {try SelfServiceKit.write(document:document,settings:settings,client:client,to:destination);return}
        let fm=FileManager.default
        guard !fm.fileExists(atPath:destination.path) else {throw JamfPublisherError("Choose a new prepared-kit folder.")}
        let stage=destination.deletingLastPathComponent().appendingPathComponent(".push-jamf-campaign-"+UUID().uuidString)
        try fm.createDirectory(at:stage,withIntermediateDirectories:false);defer{try? fm.removeItem(at:stage)}
        let output=stage.appendingPathComponent("kit")
        if deployment.mode.includesOffers {try SelfServiceKit.write(document:document,settings:settings,client:client,to:output)}else{try fm.createDirectory(at:output,withIntermediateDirectories:false)}
        let campaign=try deployment.document(from:document)
        var assets:[String:Data]=[:]
        let logo=campaign.setupValue("ui.logoPath")
        if !logo.isEmpty {
            guard logo==deployedPopupLogoPath,let data=campaign.logoImageData else {throw JamfPublisherError("Choose the popup logo again in Admin to include it in the campaign.")}
            assets["assets/popup-logo.png"]=try BrandingImage.normalizedPNG(data)
        }
        if deployment.useWallpaper {
            for role in ["noncompliant","compliant"] {
                let path=campaign.setupValue(role=="noncompliant" ? "compliance.nonCompliantWallpaper":"compliance.compliantWallpaper")
                if path.isEmpty {continue}
                if path==WallpaperPolicy.defaultImage {
                    guard let bytes=try defaultWallpaper ?? Bundle.main.url(forResource:"PUSH-NonCompliant",withExtension:"png").map({try Data(contentsOf:$0)}) else {throw JamfPublisherError("The bundled wallpaper is missing. Reinstall Admin.")}
                    assets["assets/wallpapers/PUSH-NonCompliant.png"]=try WallpaperAssetImage.normalizedPNG(bytes)
                }else{
                    guard let ref=campaign.wallpaperAssets?[role],ref.deployedPath==path,let wallpaperFolder else {throw JamfPublisherError("Choose the custom wallpaper again in Admin so it can be packaged.")}
                    assets["assets/wallpapers/"+ref.fileName]=try WallpaperAssetImage.read(ref,folder:wallpaperFolder)
                }
            }
        }
        let input=DeploymentBundleInput(yaml:campaign.yaml,assets:assets,teamID:"",hardwareCatalog:AppleHardwareReader.bundled())
        let configured=stage.appendingPathComponent("configured")
        try ConfiguredClientBuilder.build(input,client:client,activation:.monitor,to:configured)
        let target=output.appendingPathComponent("PUSH-Client-1.16.7.pkg")
        if fm.fileExists(atPath:target.path){try fm.removeItem(at:target)}
        try fm.copyItem(at:configured.appendingPathComponent("PUSH-Configured-Client.pkg"),to:target)
        let profiles=configured.appendingPathComponent("Profiles")
        for file in try fm.contentsOfDirectory(at:profiles,includingPropertiesForKeys:nil) {try fm.copyItem(at:file,to:output.appendingPathComponent(file.lastPathComponent))}
        try Data(campaign.yaml.utf8).write(to:output.appendingPathComponent("Required-update-config.yaml"))
        try JSONEncoder().encode(deployment).write(to:output.appendingPathComponent("Jamf-deployment.json"))
        let guide="""
        PUSH Jamf deployment — Sebastian Santos — PUSH-DEV-SEBASTIAN-SANTOS
        \(deployment.summary)

        Publish creates disabled policies. Enable the reviewed pilot separately.
        At the next eligible Jamf check-in, the client policy installs the configured
        client ONCE PER COMPUTER. That package contains the campaign YAML, images,
        and deferred five-minute monitoring schedule. No manual install-daemon step
        is needed. A disabled Jamf policy does not stop an already-installed monitor;
        use PUSH's monitoring controls on deployed Macs to pause an existing campaign.
        Deploy included .mobileconfig approvals through MDM before the pilot. This
        publisher does not upload configuration profiles or enroll/provision Macs.
        Confirm endpoint authorization, hardware, update discovery and UI delivery.
        Missing prerequisites block installation rather than bypassing macOS controls.
        Hourly/daily intervals are eligibility intervals, not guaranteed exact wall-clock
        deliveries. A locked/logged-out session or active install may defer reminders.
        After the deadline the required installation workflow starts when its awareness,
        authorization and safety checks succeed. Installation is not a reboot-verified
        success until the client confirms the target OS after restart.
        Installing this package replaces the installed YAML after backup. Review it.
        No API secret or user password is included. Admin is excluded from endpoints.
        Local packages are unsigned/ad-hoc builds; sign and validate for fleet rollout.
        No installer, monitor, upgrade or restart ran while building/publishing.
        \(deployment.mode.includesOffers ? "Optional offers additionally install isolated Self Service profiles and run only after a user click. See Self-Service-Guide.txt.":"This required-only workflow creates no Self Service offer or offer script.")
        """
        let oldGuide=output.appendingPathComponent("READ-ME-FIRST.txt")
        if fm.fileExists(atPath:oldGuide.path) {try fm.moveItem(at:oldGuide,to:output.appendingPathComponent("Self-Service-Guide.txt"))}
        try Data(guide.utf8).write(to:oldGuide)
        try refreshManifest(output,deployment:deployment)
        try fm.moveItem(at:output,to:destination)
    }
    static func refreshManifest(_ kit:URL,deployment:JamfDeploymentSettings)throws {
        let files=try FileManager.default.contentsOfDirectory(at:kit,includingPropertiesForKeys:nil).filter{$0.lastPathComponent != "manifest.json"}.map{["path":$0.lastPathComponent,"sha256":DeploymentBundle.digest(try Data(contentsOf:$0))]}.sorted{$0["path"]!<$1["path"]!}
        try JSONSerialization.data(withJSONObject:["developer":"Sebastian Santos","minimumClient":"1.16.7","deploymentMode":deployment.mode.rawValue,"configuredMonitoring":deployment.mode.requiresCampaign,"files":files],options:[.prettyPrinted,.sortedKeys]).write(to:kit.appendingPathComponent("manifest.json"),options:.atomic)
    }
}
