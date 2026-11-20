// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

enum WorkflowTask:String,Codable,CaseIterable,Identifiable {
    case macOS,apps,registration,restart,wallpaper
    var id:String {rawValue}
    var title:String {switch self {case .macOS:return "Software Update";case .apps:return "Update approved apps";case .registration:return "Register with Entra";case .restart:return "Remind users to restart";case .wallpaper:return "Show compliance wallpaper"}}
    var detail:String {switch self {case .macOS:return "Reminders, a deadline and installation rules.";case .apps:return "Chrome, Firefox and VS Code through your managed provider.";case .registration:return "Guide users to your Self Service registration policy.";case .restart:return "Uptime reminders and escalation; signed production client required.";case .wallpaper:return "Use the macOS target to show and restore a compliance background."}}
    var icon:String {switch self {case .macOS:return "apple.logo";case .apps:return "square.stack.3d.up";case .registration:return "person.crop.circle.badge.checkmark";case .restart:return "restart";case .wallpaper:return "photo"}}
}
enum WorkflowTarget:String,Codable,CaseIterable,Identifiable {
    case major,current,fixed,latest
    var id:String {rawValue}
    var title:String {switch self {case .major:return "Latest update within a chosen macOS generation";case .current:return "Keep each Mac's current macOS generation updated";case .fixed:return "Require a specific version";case .latest:return "Latest compatible macOS, including major upgrades"}}
}
enum WorkflowAuthorization:String,Codable,CaseIterable,Identifiable {
    case userKeychain,managed
    var id:String {rawValue}
    var title:String {self == .userKeychain ? "Use PUSH's saved user Keychain password":"Use existing IT-managed authorization"}
}
struct WorkflowRecipe:Codable,Equatable {
    var tasks:Set<WorkflowTask>=[.macOS]
    var target:WorkflowTarget = .major
    var major=26
    var fixedVersion=""
    var hasDeadline=true
    var graceDays=7
    var deadline:Date
    var timeZoneID:String
    var enforceAfterDeadline=true
    var authorization:WorkflowAuthorization = .userKeychain
    var hourlyReminders=true
    var workingHoursOnly=false
    var skipMeetings=false
    var approvedApps:Set<String>=["chrome"]
    var updateClosedApps=false
    var registrationPolicy="876"
    var restartWarningDays=14,restartForceDays=20
    var startAfterInstall=false
    var includeTahoeAudit=false
    init(now:Date=Date(),timeZoneID:String=TimeZone.current.identifier) {
        self.timeZoneID=timeZoneID
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:timeZoneID) ?? .current
        var next=calendar.nextDate(after:now,matching:DateComponents(hour:17,weekday:2),matchingPolicy:.nextTime) ?? now.addingTimeInterval(7*86400)
        if calendar.isDate(next,inSameDayAs:now) {next=calendar.date(byAdding:.day,value:7,to:next) ?? next.addingTimeInterval(7*86400)}
        deadline=next
    }
    var isOSWorkflow:Bool {tasks.contains(.macOS) || tasks.contains(.wallpaper)}
    var deadlineText:String {let f=DateFormatter();f.timeZone=TimeZone(identifier:timeZoneID);f.dateStyle = .full;f.timeStyle = .short;return f.string(from:deadline)+" ("+(f.timeZone?.abbreviation(for:deadline) ?? timeZoneID)+")"}
    func issues(now:Date=Date())->[String] {
        var result:[String]=[]
        if !(1...365).contains(graceDays) {result.append("Choose 1–365 days for rolling deadlines.")}
        if tasks.isEmpty {result.append("Choose at least one task, or use the standalone popup/audit tools.")}
        if TimeZone(identifier:timeZoneID)==nil {result.append("Choose a valid deadline time zone.")}
        if isOSWorkflow && target == .major && !(11...99).contains(major) {result.append("Choose a supported macOS generation.")}
        if isOSWorkflow && target == .fixed && versionParts(fixedVersion)==nil {result.append("Choose a complete numeric macOS version.")}
        if (isOSWorkflow || tasks.contains(.apps)) && hasDeadline && deadline<=now {result.append("Choose a future deadline. A past deadline would start enforcement immediately after installation.")}
        if tasks.contains(.apps) && (approvedApps.isEmpty || !approvedApps.isSubset(of:Set(["chrome","firefox","vscode"]))) {result.append("Choose at least one supported app.")}
        if tasks.contains(.registration) && (Int(registrationPolicy) ?? 0)<=0 {result.append("Enter the Self Service policy number supplied by your Jamf administrator.")}
        if tasks.contains(.restart) && (!(1...365).contains(restartWarningDays) || restartForceDays<restartWarningDays || restartForceDays>365) {result.append("Restart escalation must follow the first reminder within 365 days.")}
        if includeTahoeAudit && !(isOSWorkflow && target == .major && major==26) {result.append("The bundled older-Mac audit is for Tahoe. Choose Tahoe or export the audit separately.")}
        return result
    }
    func proposed(from base:ConfigDocument)->ConfigDocument {
        var doc=base
        func set(_ key:String,_ value:Bool){doc.edits[key]=value ? "true":"false"}
        set("auto.enabled",isOSWorkflow);set("apps.enabled",tasks.contains(.apps));set("entra.enabled",tasks.contains(.registration));set("uptime.enabled",tasks.contains(.restart));set("compliance.wallpaperEnabled",tasks.contains(.wallpaper))
        set("debug.dryRun",!startAfterInstall)
        set("update.autoInstallAfterDeadline",isOSWorkflow && hasDeadline && enforceAfterDeadline)
        set("update.silentInstallAfterDeadline",false);set("auto.autoInstallNonSystemUpdates",false)
        set("update.allowUserUpdateRequests",isOSWorkflow)
        if isOSWorkflow {set("auth.promptUserForInstall",authorization == .userKeychain)}
        set("schedule.respectAlertWindow",workingHoursOnly);set("schedule.skipWeekends",workingHoursOnly);set("schedule.skipDuringMeetings",skipMeetings);set("schedule.skipInstallDuringScreenShare",skipMeetings)
        doc.edits["update.toastIntervalSeconds"]="3600";doc.edits["update.nudgeIntervalSeconds"]="86400"
        // Hourly toasts are independent from full reminders; use a day when opted out.
        if !hourlyReminders {doc.edits["update.toastIntervalSeconds"]="86400"}
        doc.edits["debug.testToastIntervalMinutes"]="0";doc.edits["debug.testNudgeIntervalMinutes"]="0"
        doc.edits["auto.minorDeadlineDays"]=String(graceDays);doc.edits["auto.majorDeadlineDays"]=String(graceDays)
        doc.edits["apps.graceDays"]=String(graceDays)
        doc.edits["update.deadline"]=isOSWorkflow && hasDeadline ? ISO8601DateFormatter().string(from:deadline):""
        doc.edits["update.targetVersion"]="";doc.edits["auto.enforceMinimumMajorVersion"]="0";doc.edits["auto.maximumMajorVersion"]="0"
        set("auto.trackLatest",isOSWorkflow);set("auto.minorOnly",true);set("auto.skipBetas",true)
        if isOSWorkflow {
            switch target {
            case .major:doc.edits["auto.enforceMinimumMajorVersion"]=String(major);doc.edits["auto.maximumMajorVersion"]=String(major);doc.edits["update.macOSName"]=major==26 ? "macOS Tahoe":"macOS \(major)"
            case .current:doc.edits["update.macOSName"]="macOS"
            case .latest:set("auto.minorOnly",false);doc.edits["update.macOSName"]="macOS"
            case .fixed:doc.edits["update.targetVersion"]=fixedVersion;set("auto.trackLatest",false);set("auto.minorOnly",false);doc.edits["update.macOSName"]="macOS \(fixedVersion)"
            }
        }
        if tasks.contains(.apps) {doc.edits["apps.deadline"]=hasDeadline ? ISO8601DateFormatter().string(from:deadline):"";doc.edits["apps.approved"]=approvedApps.sorted().joined(separator:",");set("apps.autoUpdateClosed",updateClosedApps)}
        if tasks.contains(.registration) {doc.edits["entra.policyID"]=registrationPolicy}
        if tasks.contains(.restart) {doc.edits["uptime.warningThresholdDays"]=String(restartWarningDays);doc.edits["uptime.forceThresholdDays"]=String(restartForceDays)}
        if tasks.contains(.wallpaper) && doc.setupValue("compliance.nonCompliantWallpaper").isEmpty {doc.edits["compliance.nonCompliantWallpaper"]=WallpaperPolicy.defaultImage}
        doc.workflowRecipe=self
        return doc
    }
    var summary:[String] {
        var lines=WorkflowTask.allCases.filter{tasks.contains($0)}.map{$0.title}
        if isOSWorkflow {lines.append(target == .major ? "Stay on macOS \(major).x; no automatic move to a newer generation.":target == .current ? "Update each Mac within its current macOS generation.":target == .latest ? "Require the latest compatible macOS; major upgrades are allowed.":"Require macOS \(fixedVersion).")
            lines.append(hasDeadline ? "Deadline: "+deadlineText:"Allow \(graceDays) days from discovery for each new update.")
            lines.append(hasDeadline && enforceAfterDeadline ? "After deadline: start the required installation workflow; authorization and preflight still apply.":"No automatic deadline installation.")
            lines.append(authorization == .userKeychain ? "Reuse valid user Keychain credentials; ask and save securely only when needed.":"Use existing managed authorization; do not ask users for a password.")}
        if tasks.contains(.apps) && !isOSWorkflow && hasDeadline {lines.append("App deadline: "+deadlineText)}
        if tasks.contains(.apps) {lines.append("Approved apps: "+approvedApps.sorted().joined(separator:", ")+". Open apps stay running.")}
        lines.append(startAfterInstall ? "Deployment: start selected monitors after installation; first checks wait five minutes.":"Deployment: install paused for testing.")
        return lines
    }
}

extension WorkflowRecipe {
    static func from(document:ConfigDocument,now:Date=Date())->Self {
        if let saved=document.workflowRecipe {return saved}
        var recipe=Self(now:now)
        // A fresh empty draft gets the starter. Imported policies keep their
        // module selection, authorization and version strategy until reviewed.
        let hasSource=document.source.components(separatedBy:.newlines).contains{let line=$0.trimmingCharacters(in:.whitespaces);return !line.isEmpty && !line.hasPrefix("#")}
        let fresh=ConfigDocument.fresh
        let changedTaskKeys=["auto.enabled","apps.enabled","entra.enabled","uptime.enabled","compliance.wallpaperEnabled","auto.trackLatest","update.targetVersion"].contains{document.setupValue($0) != fresh.setupValue($0)}
        guard hasSource || changedTaskKeys else{return recipe}
        recipe.tasks=[]
        for (key,task) in [("auto.enabled",WorkflowTask.macOS),("apps.enabled",.apps),("entra.enabled",.registration),("uptime.enabled",.restart),("compliance.wallpaperEnabled",.wallpaper)] {if document.setupFlag(key){recipe.tasks.insert(task)}}
        let target=document.setupValue("update.targetVersion"),cap=Int(document.setupValue("auto.maximumMajorVersion")) ?? 0
        if !document.setupFlag("auto.trackLatest") && !target.isEmpty {recipe.target = .fixed;recipe.fixedVersion=target}
        else if cap>0 {recipe.target = .major;recipe.major=cap}
        else {recipe.target=document.setupFlag("auto.minorOnly") ? .current:.latest}
        if let deadline=ISO8601DateFormatter().date(from:document.setupValue("update.deadline")){recipe.hasDeadline=true;recipe.deadline=deadline}else{recipe.hasDeadline=false}
        recipe.graceDays=Int(document.setupValue("auto.minorDeadlineDays")) ?? 7
        recipe.enforceAfterDeadline=document.setupFlag("update.autoInstallAfterDeadline")
        recipe.authorization=document.setupFlag("auth.promptUserForInstall") ? .userKeychain:.managed
        recipe.hourlyReminders=(Int(document.setupValue("update.toastIntervalSeconds")) ?? 3600)<=3600
        recipe.workingHoursOnly=document.setupFlag("schedule.respectAlertWindow");recipe.skipMeetings=document.setupFlag("schedule.skipDuringMeetings")
        let apps=Set(AppUpdatePolicy.ids(document.setupValue("apps.approved")));if !apps.isEmpty{recipe.approvedApps=apps}
        recipe.updateClosedApps=document.setupFlag("apps.autoUpdateClosed")
        recipe.registrationPolicy=document.setupValue("entra.policyID")
        recipe.restartWarningDays=Int(document.setupValue("uptime.warningThresholdDays")) ?? 14;recipe.restartForceDays=Int(document.setupValue("uptime.forceThresholdDays")) ?? 20
        recipe.startAfterInstall=false
        return recipe
    }
}
