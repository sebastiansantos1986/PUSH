// PUSH Admin — Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import CryptoKit

enum SetupWizardStep: Int, CaseIterable, Identifiable {
    case start, branding, macOS, apps, registration, preview, review
    var id: Int {rawValue}
    var title: String { ["Start","Branding","macOS","Apps","Registration","Preview","Review"][rawValue] }
    var subtitle: String {
        switch self {
        case .start:return "Continue a draft or import existing settings."
        case .branding:return "Make messages recognizable and provide a support contact."
        case .macOS:return "Choose what to follow and when to remind people."
        case .apps:return "Approve only the apps PUSH should manage."
        case .registration:return "Connect your supported Jamf registration workflow."
        case .preview:return "Exercise the real preview views with simulated actions."
        case .review:return "Review the draft, local evidence, and what remains unverified."
        }
    }
}
enum SetupMacStrategy: String, CaseIterable, Identifiable {
    case disabled = "Leave macOS checks disabled"
    case minor = "Follow updates within the current major"
    case major = "Follow compatible major upgrades too"
    case fixed = "Use a configured target"
    var id:String {rawValue}
}
struct SetupPreviewEvent: Codable {
    var fingerprint: String
    var state: String
    var code: Int32
    var automatic: Bool
    var date: Date
}
struct SetupWizardProgress: Codable {
    var step = 0
    var reviewedFingerprint: String?
    var reviewedAt: Date?
    var previewEvents: [SetupPreviewEvent] = []
    var currentStep: SetupWizardStep { SetupWizardStep(rawValue:step) ?? .start }
    mutating func record(document:ConfigDocument,state:String,code:Int32?,automatic:Bool,now:Date = Date()) {
        guard let code, [0,1,2,3,4,5,6].contains(code), UIState(rawValue:state) != nil else { return }
        previewEvents.append(.init(fingerprint:document.setupFingerprint,state:state,code:code,automatic:automatic,date:now))
        if previewEvents.count > 100 {previewEvents.removeFirst(previewEvents.count-100)}
    }
    mutating func markReviewed(_ document:ConfigDocument,now:Date = Date()) {
        guard document.setupIssues.isEmpty else{return}
        reviewedFingerprint=document.setupFingerprint;reviewedAt=now
    }
    func reviewed(_ document:ConfigDocument)->Bool {guard let reviewedFingerprint else {return false};return reviewedFingerprint == document.setupFingerprint}
}
struct SetupPreviewRequirement: Identifiable {
    let state:String,code:Int32,title:String
    var id:String {state+":"+String(code)}
    func exercised(document:ConfigDocument,progress:SetupWizardProgress)->Bool {
        let fingerprint=document.setupFingerprint
        return progress.previewEvents.contains {$0.fingerprint == fingerprint && $0.state == state && $0.code == code && !$0.automatic}
    }
}
struct SetupReviewFinding: Identifiable {
    enum Level: Equatable {case good, attention, information}
    let id:String,title:String,detail:String,level:Level
}
extension ConfigDocument {
    func setupValue(_ key:String)->String {
        if let field=configGroups.flatMap(\.fields).first(where:{$0.id == key}) {return value(field)}
        return value(key) ?? ""
    }
    func setupFlag(_ key:String)->Bool {setupValue(key) == "true"}
    var setupFingerprint:String {
        var bytes=Data(yaml.utf8)
        // A digest of the attached image covers branding changes without storing
        // the YAML, image, account names, or credentials in preview history.
        if let image=logoImageData {bytes.append(contentsOf:SHA256.hash(data:image))}
        if let settings=majorOfferSettings {let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];if let data=try? encoder.encode(settings){bytes.append(data)}}
        return SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
    }
    var setupStrategy:SetupMacStrategy {
        if !setupFlag("auto.enabled") {return .disabled}
        if !setupFlag("auto.trackLatest") {return .fixed}
        return setupFlag("auto.minorOnly") ? .minor:.major
    }
    mutating func chooseSetupStrategy(_ strategy:SetupMacStrategy) {
        switch strategy {
        case .disabled:edits["auto.enabled"]="false"
        case .fixed:edits["auto.enabled"]="true";edits["auto.trackLatest"]="false"
        case .minor,.major:followReleases(allowMajorUpgrades:strategy == .major)
        }
    }
    static func setupKeys(_ step:SetupWizardStep)->[String] {
        switch step {
        case .branding:return ["ui.appName","ui.orgName","ui.itContactEmail","ui.itContactPhone","ui.helpURL","ui.accentColorHex","ui.logoPath","ui.popupBackgroundStyle","ui.popupOpacityPercent"]
        case .macOS:return ["auto.enabled","auto.trackLatest","auto.minorOnly","auto.useMist","auto.skipBetas","auto.minorDeadlineDays","auto.majorDeadlineDays","auto.autoInstallNonSystemUpdates","update.targetVersion","update.deadline","update.maxDeferrals","update.toastIntervalSeconds","update.autoInstallAfterDeadline","update.silentInstallAfterDeadline","update.prepareAtDeadlineWhenLoggedOut","schedule.respectAlertWindow","schedule.alertStartHour","schedule.alertEndHour","schedule.skipWeekends","schedule.skipDuringMeetings"]
        case .apps:return ["apps.enabled","apps.approved","apps.autoUpdateClosed","apps.notifyHourly","apps.graceDays","apps.deadline","apps.chromeDeadline","apps.firefoxDeadline","apps.vscodeDeadline","apps.installomatorPath"]
        case .registration:return ["entra.enabled","entra.policyID","entra.startHour","entra.endHour","entra.weekdaysOnly","entra.skipMeetings","entra.reconOnRegistration","entra.selfServicePath","entra.companyPortalPath","entra.jamfBinaryPath","entra.message"]
        case .review:return ["debug.dryRun"]
        default:return []
        }
    }
    func setupIssues(for step:SetupWizardStep)->[String] {
        if step == .start {return formatIssues}
        var result:[String]=[]
        for field in configGroups.flatMap(\.fields) where Self.setupKeys(step).contains(field.id) {
            let text=setupValue(field.id)
            switch field.kind {
            case .boolean:if !["true","false"].contains(text) {result.append(field.title+": choose true or false.")}
            case .number(let range):if Int(text).map({range.contains($0)}) != true {result.append(field.title+": enter a number in \(range.lowerBound)…\(range.upperBound).")}
            case .choice(let options):if !options.contains(text) {result.append(field.title+": choose a supported value.")}
            default:break
            }
        }
        func validDeadline(_ key:String) {let text=setupValue(key);if !text.isEmpty && ISO8601DateFormatter().date(from:text) == nil {result.append(key+": use an ISO 8601 date with time zone.")}}
        func validHours(_ start:String,_ end:String) {if let a=Int(setupValue(start)),let b=Int(setupValue(end)),a>=b {result.append("End hour must follow the start hour.")}}
        switch step {
        case .branding:
            if setupValue("ui.accentColorHex").range(of:"^#[0-9a-fA-F]{6}$",options:.regularExpression) == nil {result.append("Use a six-digit accent color such as #0A84FF.")}
            let help=setupValue("ui.helpURL");if !help.isEmpty && URL(string:help)?.scheme != "https" {result.append("Support website must use HTTPS.")}
            let path=setupValue("ui.logoPath");if !path.isEmpty && !path.hasPrefix("/") {result.append("Deployed logo path must be absolute.")}
        case .macOS:
            let target=setupValue("update.targetVersion")
            if setupStrategy == .fixed && versionParts(target) == nil {result.append("Enter a numeric macOS target, or choose release tracking.")}
            validDeadline("update.deadline");validHours("schedule.alertStartHour","schedule.alertEndHour")
        case .apps:
            let selected=AppUpdatePolicy.ids(setupValue("apps.approved"))
            if setupFlag("apps.enabled") && selected.isEmpty {result.append("Approve at least one app, or leave app management disabled.")}
            if selected.contains(where:{id in !ApprovedApp.catalog.contains{$0.id == id}}) {result.append("Only chrome, firefox and vscode are supported approvals.")}
            for key in ["apps.deadline","apps.chromeDeadline","apps.firefoxDeadline","apps.vscodeDeadline"] {validDeadline(key)}
        case .registration:
            if EntraPolicy.selfServiceURL(policyID:setupValue("entra.policyID")) == nil {result.append("Enter a positive Self Service policy ID.")}
            validHours("entra.startHour","entra.endHour")
        default:break
        }
        return result
    }
    var setupIssues:[String] {
        var seen=Set<String>()
        let booleans=configGroups.flatMap(\.fields).compactMap {field->String? in
            if case .boolean=field.kind, !["true","false"].contains(setupValue(field.id)) {return field.title+": choose true or false."};return nil
        }
        return (problems+SetupWizardStep.allCases.flatMap{setupIssues(for:$0)}+booleans).filter{seen.insert($0).inserted}
    }
    var setupPreviewRequirements:[SetupPreviewRequirement] {
        var rows:[SetupPreviewRequirement]=[.init(state:"toast",code:0,title:"Toast · Install")]
        if setupFlag("toast.showDeferButton") {rows.append(.init(state:"toast",code:1,title:"Toast · Later"))}
        if setupFlag("toast.showCloseButton") {rows.append(.init(state:"toast",code:2,title:"Toast · Close"))}
        rows.append(.init(state:"softNudge",code:0,title:"Full prompt · Install"))
        if (Int(setupValue("update.maxDeferrals")) ?? 0)>0 {
            rows += [.init(state:"softNudge",code:1,title:"Full prompt · Later"),.init(state:"softNudge",code:3,title:"Full prompt · Confirm reminder schedule")]
        }
        if setupFlag("apps.enabled") {rows += [.init(state:"appUpdates",code:0,title:"Apps · Update Closed Apps"),.init(state:"appUpdates",code:1,title:"Apps · Later")]}
        if setupFlag("entra.enabled") {rows += [.init(state:"entraRegistration",code:0,title:"Registration · Register Now"),.init(state:"entraRegistration",code:1,title:"Registration · Later")]}
        if setupFlag("uptime.enabled") {rows += [.init(state:"rebootNudge",code:0,title:"Restart · Restart Now"),.init(state:"rebootNudge",code:1,title:"Restart · Later")]}
        return rows
    }
    func setupFindings(snapshot:ReadinessSnapshot?,providerPresent:Bool?,now:Date=Date())->[SetupReviewFinding] {
        var result:[SetupReviewFinding]=[]
        func add(_ id:String,_ title:String,_ detail:String,_ level:SetupReviewFinding.Level) {result.append(.init(id:id,title:title,detail:detail,level:level))}
        if setupIssues.isEmpty {add("validation","Draft validates","Ready to export or review in Deployment. This does not certify installation authorization.",.good)}
        else {add("validation","Resolve draft issues",setupIssues.joined(separator:"\n"),.attention)}
        add("mode",setupFlag("debug.dryRun") ? "Dry-run draft":"Live draft",setupFlag("debug.dryRun") ? "Active checks and update actions remain disabled when this policy is applied.":"If applied while monitors are active, subsequent checks use this live policy. Review all enabled modules before applying.",setupFlag("debug.dryRun") ? .information:.attention)
        let deadline=setupValue("update.deadline")
        if let date=ISO8601DateFormatter().date(from:deadline),date<now {add("deadline","YAML deadline is already past","This override survives discovery of new targets. Review installation-after-deadline choices before activation.",.attention)}
        if setupFlag("update.autoInstallAfterDeadline") || setupFlag("update.silentInstallAfterDeadline") {add("automatic","Automatic OS installation selected","When macOS checks are enabled and live, this saved deadline policy can request a real installation; it is not a reminder-only setting.",.attention)}
        if setupFlag("ui.hardBlockFullscreen") {add("fullscreen","Full-screen hard blocks selected","Live deadline escalation can cover all displays. Review the full-screen experience before activating this policy.",.attention)}
        if setupFlag("update.forceRestartAfterInstall") {add("installRestart","Post-install restart requested","Review the installation and restart policy before using real update actions.",.attention)}
        if setupFlag("auto.autoInstallNonSystemUpdates") {add("extras","Non-system automatic updates selected","Normal live checks can also install configured non-system updates.",.attention)}
        if setupFlag("uptime.enabled") {add("restart","Uptime restart policy enabled","Review restart thresholds in Configuration. Live restart escalation is separate from OS update reminders.",.attention)}
        if setupFlag("compliance.wallpaperEnabled") {add("wallpaper","Compliance wallpaper enabled","A live macOS check will reapply the selected image while below the target. Export or Apply must also deploy attached wallpaper assets.",.attention)}
        add("authorization","Unattended authorization is not verified","This wizard does not query Keychain, provision MDM, or collect passwords. IT must validate authorization and the actual installation route on an enrolled test Mac.",.information)
        if let snapshot {
            add("engine",snapshot.engineInstalled ? "Engine detected · "+snapshot.engineVersion:"Engine not installed",snapshot.engineInstalled ? "Installed files were detected. No engine command was run.":"Export works without the engine. Install it before applying or activating checks.",snapshot.engineInstalled ? .information:.attention)
            add("monitors","Installed monitors: "+snapshot.mainMonitor.title+" / "+snapshot.entraMonitor.title,"Local snapshot "+ReadinessSnapshot.stamp(snapshot.capturedAt)+". These are installed service facts, not the draft's future state. The wizard never changes monitors.",.information)
            if setupFlag("entra.enabled"),snapshot.entra?.status == .notApplicable {add("enrollment","Last Entra check: not applicable","The saved result found no MDM enrollment. Production registration reminders remain inactive for that result; validate on an enrolled test Mac.",.attention)}
        } else {add("engine","Local readiness not loaded","Refresh the local snapshot, or export for review on another Mac. No installation readiness is inferred.",.information)}
        if setupFlag("apps.enabled") {
            add("provider",providerPresent == true ? "Provider file found · trust not verified":"App provider not found or not inspected","Actual app updates require a separately managed Installomator provider. The engine verifies ownership, path protection and app identity before execution.",providerPresent == true ? .information:.attention)
            if setupFlag("apps.autoUpdateClosed") {add("closed","Automatic closed-app updates selected","Approved closed apps can update after live activation, even before their deadline. Open apps are left running.",.attention)}
        }
        if setupFlag("entra.enabled") {add("registration","Registration setup requires an enrolled pilot","Verify the configured policy ID and legacy Jamf Self Service/Company Portal setup. Local evidence does not establish cloud compliance.",.information)}
        return result
    }
}
