// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

struct SetupAdvice:Identifiable {
    enum Tone {case suggestion,attention,ready}
    var id:String,title:String,detail:String,tone:Tone
    var changes:[String:String]=[:]
    var action:String="Apply suggestion to draft"
}
enum SetupAdvisor {
    // Suggestions never enable live installation, disable dry-run, clear a deadline
    // override, or expand to major upgrades without an individual explicit action.
    static let smartDefaults:[String:String]=["auto.enabled":"true","auto.trackLatest":"true","auto.minorOnly":"true","auto.skipBetas":"true","auto.minorDeadlineDays":"7","auto.majorDeadlineDays":"14","update.toastIntervalSeconds":"3600","schedule.respectAlertWindow":"false","update.deadlineRecoveryEnabled":"true","update.retryCountdownMinutes":"10","update.retryBackoffMinutes":"30","update.maxAutomaticRetriesPerDay":"3","ui.menuBarEnabled":"true","update.allowUserUpdateRequests":"true"]
    static func evaluate(_ document:ConfigDocument,catalogDate:Date?,catalogCached:Bool,providerPresent:Bool?,mistPresent:Bool?,now:Date=Date())->[SetupAdvice] {
        var rows:[SetupAdvice]=[]
        func add(_ id:String,_ title:String,_ detail:String,_ tone:SetupAdvice.Tone,_ changes:[String:String]=[:],_ action:String="Apply suggestion to draft") {rows.append(.init(id:id,title:title,detail:detail,tone:tone,changes:changes,action:action))}
        if !document.setupFlag("auto.enabled") || !document.setupFlag("auto.trackLatest") {
            add("discovery","Follow new updates automatically","Use stable updates within the current major release, hourly toasts and automatic deadlines from first discovery. Your explicit deadline, dry-run choice and installation policy stay unchanged.",.suggestion,smartDefaults,"Use recommended discovery settings")
        } else {add("discovery","Automatic release tracking is selected","PUSH can discover later eligible releases after meeting the saved target. Monitoring and endpoint authorization still need to be ready.",.ready)}
        if !document.setupFlag("auto.minorOnly") {add("major","Major upgrades are allowed","This policy can move users to a new macOS major version. Keep this choice only after testing your apps and compatible installers.",.attention)}
        if !document.setupFlag("auto.skipBetas") {add("betas","Exclude beta releases","Use stable releases for employee computers.",.suggestion,["auto.skipBetas":"true"])}
        if document.setupValue("update.toastIntervalSeconds") != "3600" {add("hourly","Use hourly toast reminders","Set the ordinary toast interval to one hour; this is separate from the five-minute background check.",.suggestion,["update.toastIntervalSeconds":"3600"])}
        if document.setupFlag("schedule.respectAlertWindow") {add("hours","Reminders are limited to working hours","Users will not receive ordinary reminders outside the saved window. Turn off that restriction for your around-the-clock awareness policy; session and meeting checks still apply.",.suggestion,["schedule.respectAlertWindow":"false"])}
        let deadline=document.setupValue("update.deadline")
        if !deadline.isEmpty {
            let expired=ISO8601DateFormatter().date(from:deadline).map{$0<=now} ?? false
            add("deadline",expired ? "The explicit deadline has passed":"An explicit deadline overrides automatic timing","This YAML override remains authoritative, including for future targets. Clear it only if you want per-release deadlines anchored to first discovery.",expired ? .attention:.suggestion,["update.deadline":""],"Use per-release automatic deadlines")
        }
        if document.setupFlag("debug.dryRun") {add("dry","Dry-run is enabled","This package can be installed for inspection, but live monitor activation is unavailable. Disable dry-run deliberately when preparing a managed live pilot.",.attention)}
        if document.setupFlag("auto.enabled"),document.setupFlag("update.autoInstallAfterDeadline") || document.setupFlag("update.silentInstallAfterDeadline") {
            add("authorization","Verify unattended authorization on client Macs","IT must provision the supported MDM/bootstrap-token or managed-credential route. The setup Mac’s status cannot certify a fleet. No end-user password fallback is added.",.attention)
            if !document.setupFlag("update.deadlineRecoveryEnabled") {add("recovery","Explain failures and retry safely","Enable saved failure notices and bounded countdown retries. Authorization and installer validation remain protected.",.suggestion,["update.deadlineRecoveryEnabled":"true"])}
        }
        if document.setupValue("ui.itContactEmail").isEmpty && document.setupValue("ui.helpURL").isEmpty {add("support","Add an IT support contact","Users need a clear next step when an update cannot start. Add your support email or HTTPS help page in Branding / Configuration.",.attention)}
        if document.setupFlag("auto.useMist"),mistPresent != true {add("mist","Check Mist availability on target Macs","Mist is selected but was not found on this admin Mac. Its presence here would not verify other Macs. Deploy the supported dependency separately where your installer-discovery route needs it.",.attention)}
        if catalogDate == nil || catalogCached || now.timeIntervalSince(catalogDate ?? .distantPast)>86400 {add("catalog","Refresh release information before rollout","The local catalog is missing, cached or older than a day. Refresh macOS Releases for planning; runtime discovery happens on each managed Mac.",.suggestion)}
        if document.setupFlag("apps.enabled") {add("apps","Deploy the approved app-update provider","Third-party updates require a protected Installomator provider on each client. "+(providerPresent == true ? "A provider file was seen locally; fleet presence and trust remain unverified.":"No provider was verified locally. The client installer does not bundle it."),.attention)}
        if document.setupFlag("entra.enabled") {add("entra","Validate the registration policy on an enrolled pilot","Check the Self Service policy ID, Company Portal and enrollment. A registration reminder is not proof of cloud compliance.",.attention)}
        if document.setupFlag("uptime.enabled") {add("restart","Gentle restart needs a signed automation approval","Use the matching Developer ID-signed executable for the restricted System Events profile. The embedded local client is ad-hoc signed, so it cannot satisfy that production approval.",.attention)}
        add("profiles","Deploy management profiles through MDM","Background-item and notification profiles accompany the package. A package cannot silently grant every privacy permission or enroll a Mac.",.suggestion)
        return rows
    }
}
