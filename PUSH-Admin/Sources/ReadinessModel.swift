// PUSH Admin — Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

struct ObservedHealth: Codable {
    var module: String
    var source: String
    var startedAt: Date
    var updatedAt: Date
    var finishedAt: Date?
    var phase: String
    var reason: String
    var error: String?
    var userUID: Int?
}
struct ObservedIntent: Codable { var desired: String; var changedAt: Date; var reason: String }
struct LaunchdObservation {
    var loaded: Bool?
    var running = false
    var detail: String
    static func parse(exit: Int32, text: String) -> Self {
        if exit == 0 {
            let running = text.range(of:#"(?m)^\s*state\s*=\s*running\s*$"#,options:.regularExpression) != nil
            return .init(loaded:true,running:running,detail:running ? "A background check is running":"Loaded and waiting between checks")
        }
        let lower = text.lowercased()
        if lower.contains("could not find service") || lower.contains("service not found") { return .init(loaded:false,detail:"Service is not loaded") }
        return .init(loaded:nil,detail:"The service state could not be read; no running/stopped assumption was made")
    }
}
enum DashboardTone: Equatable { case good, waiting, attention, inactive, unknown }
enum DashboardRoute { case monitoring, macPolicy, apps, entra }
struct MonitorReadiness {
    var title: String
    var reason: String
    var tone: DashboardTone
    var blocksAutomation: Bool
    static func evaluate(definition: Bool?, observed: LaunchdObservation, intent: ObservedIntent?, health: ObservedHealth?, interval: TimeInterval, now: Date, expected: Bool, dryRun: Bool) -> Self {
        if observed.loaded == true {
            if definition == false || intent?.desired == "paused" {
                return .init(title:"Loaded · review setup",reason:"The service is loaded but its saved definition or pause request disagrees. Review monitoring before relying on it.",tone:.attention,blocksAutomation:false)
            }
            if expected && !dryRun {
                if let health {
                    let age = now.timeIntervalSince(health.updatedAt)
                    if age < -120 {return .init(title:"Check time needs attention",reason:"The saved check time is in the future. Review the Mac clock and saved history.",tone:.attention,blocksAutomation:false)}
                    let busyLimit: Double = health.phase == "updating" ? 2400 : 1200
                    if observed.running && health.finishedAt == nil && age < busyLimit {
                        return .init(title:health.phase == "waitingForUser" ? "Waiting for response":"Check running",reason:health.reason,tone:.waiting,blocksAutomation:false)
                    }
                    if !observed.running && health.finishedAt == nil && age > 120 {
                        return .init(title:"Last check unfinished",reason:"The monitor is loaded, but its last recorded check did not finish. Review the saved step and logs.",tone:.attention,blocksAutomation:false)
                    }
                    if age > max(interval * 2 + 120,600) {
                        return .init(title:"Overdue",reason:"The service is loaded, but no recent scheduled result was recorded. A manual check does not replace this background history.",tone:.attention,blocksAutomation:false)
                    }
                    if health.error != nil || health.phase == "failed" { return .init(title:"Check needs attention",reason:health.error ?? health.reason,tone:.attention,blocksAutomation:false) }
                } else { return .init(title:"Loaded · not yet verified",reason:"No scheduled result has been recorded. Review logs if this continues after the next interval.",tone:.waiting,blocksAutomation:false) }
            }
            return .init(title:dryRun ? "Loaded · dry run":"Monitor loaded",reason:observed.detail,tone:.good,blocksAutomation:false)
        }
        if observed.loaded == nil {
            return .init(title:"State unknown",reason:observed.detail,tone:.unknown,blocksAutomation:true)
        }
        if intent?.desired == "paused" { return .init(title:"Paused",reason:"Monitoring was explicitly paused. No scheduled reminders will run until it is enabled again.",tone:.inactive,blocksAutomation:true) }
        if definition == true { return .init(title:"Installed, not loaded",reason:"A schedule file exists, but the service is not loaded. File presence alone does not mean monitoring is working.",tone:.attention,blocksAutomation:true) }
        if definition == nil { return .init(title:"Definition unreadable",reason:"The schedule definition could not be inspected.",tone:.unknown,blocksAutomation:true) }
        return .init(title:"Missing",reason:"No loaded service or installed schedule definition was found. Scheduled reminders cannot run.",tone:.attention,blocksAutomation:true)
    }
}
struct DashboardHours {
    let start: Int, end: Int
    let weekdays: Bool
    func nextAllowed(_ candidate: Date, calendar: Calendar = .current) -> Date? {
        guard (0...23).contains(start),(1...24).contains(end),start < end else { return nil }
        var date = candidate
        for _ in 0..<9 {
            let day = calendar.startOfDay(for:date)
            let weekday = calendar.component(.weekday,from:day)
            let begin = calendar.date(bySettingHour:start,minute:0,second:0,of:day)!
            let finish = (end == 24 ? calendar.date(byAdding:.day,value:1,to:day)! : calendar.date(bySettingHour:end,minute:0,second:0,of:day)!)
            if !weekdays || ![1,7].contains(weekday) {
                if date < begin { return begin }
                if date < finish { return date }
            }
            guard let next = calendar.date(byAdding:.day,value:1,to:day) else { return nil }; date = next
        }
        return nil
    }
}
struct InstalledPolicySummary {
    var macEnabled: Bool, appsEnabled: Bool, entraEnabled: Bool, dryRun: Bool
    var target: String, deadline: Date?, tracking: Bool
    var macHours: DashboardHours, entraHours: DashboardHours
    var approved: [String], autoClosed: Bool, appReminders: Bool, providerPath: String
    init(_ config: DashboardConfig) {
        macEnabled=config.auto.enabled;appsEnabled=config.apps.enabled;entraEnabled=config.entra.enabled;dryRun=config.debug.dryRun
        target=config.update.targetVersion;deadline=ISO8601DateFormatter().date(from:config.effectiveDeadline);tracking=config.auto.trackLatest
        macHours = .init(start:config.schedule.alertStartHour,end:config.schedule.alertEndHour,weekdays:config.schedule.skipWeekends)
        entraHours = .init(start:config.entra.startHour,end:config.entra.endHour,weekdays:config.entra.weekdaysOnly)
        approved=AppUpdatePolicy.ids(config.apps.approved);autoClosed=config.apps.autoUpdateClosed;appReminders=config.apps.notifyHourly;providerPath=config.apps.installomatorPath
    }
}
struct DashboardOSState: Decodable {
    var nextToastDate: Date?, nextNudgeDate: Date?, lastDiscoveryDate: Date?
    var installStarted: Bool?, installCompleted: Bool?
    var lastDiscoveryError: String?
}
struct DashboardAppState: Decodable {
    struct Record: Decodable { var installed: String?;var target: String?;var result: String?;var checked: Date?;var deadline: Date? }
    var apps: [String:Record]
    var nextToast: Date?
}
struct DashboardFact: Identifiable { var label: String; var value: String; var id: String { label } }
struct ModuleReadiness: Identifiable {
    var id: String, title: String, status: String, reason: String
    var tone: DashboardTone
    var facts: [DashboardFact]
    var nextStep: String
    var route: DashboardRoute
    var checkCommand: String
    var observation: String?
}
struct ReadinessSnapshot {
    var capturedAt: Date
    var engineVersion: String
    var engineInstalled: Bool
    var policy: InstalledPolicySummary?
    var configIssue: String?
    var os: DashboardOSState?
    var osIssue: String?
    var apps: DashboardAppState?
    var appsIssue: String?
    var entra: EntraUserState?
    var entraIssue: String?
    var mainMonitor: MonitorReadiness
    var entraMonitor: MonitorReadiness
    var scheduled: [String:ObservedHealth]
    var manual: [String:ObservedHealth]
    var providerPresent: Bool
    var calendar = Calendar.current
    static func stamp(_ date: Date?) -> String { date.map { $0.formatted(date:.abbreviated,time:.shortened) } ?? "Not recorded" }
    var headline: String {
        if !engineInstalled { return "Install the PUSH engine to begin" }
        if configIssue != nil { return "The installed policy needs attention" }
        guard let policy else { return "No installed policy is available" }
        if policy.dryRun { return "Dry-run policy · no live prompts or updates" }
        let needsMain = policy.macEnabled || policy.appsEnabled
        let needsEntra = policy.entraEnabled && entra?.status != .notApplicable
        if needsMain && mainMonitor.blocksAutomation || needsEntra && entraMonitor.blocksAutomation { return "Scheduled reminders are not fully active" }
        if needsMain && mainMonitor.tone == .attention || needsEntra && entraMonitor.tone == .attention { return "Monitoring needs attention" }
        if !needsMain && !needsEntra { return "No live monitoring is needed by the current policy and saved result" }
        return "Monitoring is loaded · review the next actions below"
    }
    var explanation: String {
        if !engineInstalled { return "This companion can edit drafts and show previews, but it cannot schedule checks without the engine." }
        if let configIssue { return configIssue }
        guard let policy else { return "Import or apply a configuration before activating monitoring." }
        if policy.dryRun { return "The installed configuration is in dry-run mode. A loaded monitor will not run live discovery, prompts, or installations." }
        if (policy.macEnabled || policy.appsEnabled) && mainMonitor.blocksAutomation { return "macOS/app monitoring: " + mainMonitor.reason }
        if policy.entraEnabled && entra?.status != .notApplicable && entraMonitor.blocksAutomation { return "Registration monitoring: " + entraMonitor.reason }
        return "This is the installed policy and saved evidence—not the unsaved draft. Refresh reads local files and service status only."
    }
    private func latest(_ module: String) -> ObservedHealth? {
        [scheduled[module],manual[module]].compactMap { $0 }.max { $0.updatedAt < $1.updatedAt }
    }
    private func observation(_ module: String) -> String? {
        guard let row = latest(module) else { return nil }
        return "Last \(row.source == "scheduled" ? "scheduled":"manual") observation · \(Self.stamp(row.updatedAt)): \(row.reason)"
    }
    private func base(_ id: String, title: String, route: DashboardRoute, command: String) -> ModuleReadiness {
        .init(id:id,title:title,status:"Not checked",reason:"No result recorded",tone:.unknown,facts:[],nextStep:"Review the policy and run a check when ready.",route:route,checkCommand:command,observation:observation(id))
    }
    var modules: [ModuleReadiness] {
        var mac=base("macos",title:"macOS updates",route:.macPolicy,command:"sudo /Library/Management/PUSH/push-cli check-now")
        var app=base("apps",title:"Approved app updates",route:.apps,command:"sudo /Library/Management/PUSH/push-cli apps check")
        var reg=base("entra",title:"Entra registration",route:.entra,command:"sudo /Library/Management/PUSH/push-cli entra check")
        guard engineInstalled, let p=policy, configIssue == nil else {
            for key in 0..<3 {
                var item=[mac,app,reg][key];item.status="Setup needed";item.reason=configIssue ?? "The engine or installed policy is missing.";item.nextStep="Review Deployment before enabling monitoring."
                if key==0 {mac=item};if key==1 {app=item};if key==2 {reg=item}
            };return [mac,app,reg]
        }
        let now=capturedAt
        let toast = (os?.nextToastDate).flatMap {p.macHours.nextAllowed(max(now,$0),calendar:calendar)}
        mac.facts=[.init(label:"Running macOS",value:runningOS),.init(label:"Saved target",value:p.target.isEmpty ? "Not selected":p.target),.init(label:"Deadline",value:Self.stamp(p.deadline)),.init(label:"Toast eligible",value:Self.stamp(toast)),.init(label:"Next full prompt",value:Self.stamp(os?.nextNudgeDate)),.init(label:"Monitor",value:mainMonitor.title)]
        mac.nextStep="Copy Check now to refresh discovery, or review the update policy."
        if !p.macEnabled { mac.status="Disabled by policy";mac.reason="Automatic macOS checks are disabled in the installed configuration.";mac.tone = .inactive }
        else if p.dryRun { mac.status="Dry run";mac.reason="Live update checks and reminders are disabled by dry-run mode.";mac.tone = .inactive }
        else if let osIssue {mac.status="State needs attention";mac.reason=osIssue;mac.tone = .attention}
        else if os?.installStarted == true {mac.status="Awaiting reboot verification";mac.reason="PUSH is waiting to verify the installation result before scheduling another installation.";mac.tone = .waiting;mac.nextStep="Review restart and installation status with IT."}
        else if mainMonitor.blocksAutomation {mac.status=mainMonitor.title;mac.reason="A saved toast date alone cannot display a reminder. " + mainMonitor.reason;mac.tone = .attention;mac.route = .monitoring;mac.nextStep="Review Deployment and explicitly enable monitoring after checking the live policy."}
        else if p.target.isEmpty {mac.status="Discovery needed";mac.reason="No target is saved yet. A new check must select an eligible release.";mac.tone = .waiting}
        else if AppUpdatePolicy.version(p.target) == nil {mac.status="Invalid target";mac.reason="The saved macOS target could not be interpreted.";mac.tone = .attention}
        else if !AppUpdatePolicy.newer(p.target,than:runningOS) {mac.status="At the saved target";mac.reason=p.tracking ? "PUSH can continue discovering newer eligible releases.":"The Mac meets the configured target; release tracking is not enabled.";mac.tone = .good}
        else if os == nil {mac.status="Not checked";mac.reason="No saved macOS check state exists. Run Check now when ready; Refresh does not create a check result.";mac.tone = .waiting}
        else if let error=os?.lastDiscoveryError, !error.isEmpty {mac.status="Discovery needs attention";mac.reason=error;mac.tone = .attention}
        else if let deadline=p.deadline, deadline < now {mac.status="Deadline reached";mac.reason="The next eligible check follows your deadline-install policy. Authorization and preflight requirements still apply.";mac.tone = .attention;mac.nextStep="Review the deadline and installation policy before activating or forcing anything."}
        else if let toast, toast > now {mac.status="Waiting for eligibility";mac.reason="The toast is not yet eligible under its saved time and working hours. It can appear on a later monitor check.";mac.tone = .waiting}
        else {mac.status="Toast eligible";mac.reason="The saved toast is due. The next monitor check still evaluates meetings, user availability, and installation activity.";mac.tone = .waiting}
        let approvedRecords = (apps?.apps ?? [:]).filter { p.approved.contains($0.key) }
        let pending = approvedRecords.filter { AppUpdatePolicy.newer($0.value.target ?? "",than:$0.value.installed ?? "") }
        let failures = approvedRecords.values.filter { ($0.result ?? "").hasPrefix("Skipped:") || ($0.result ?? "").hasPrefix("Update failed") }
        let appDate=(apps?.nextToast).flatMap {p.macHours.nextAllowed(max(now,$0),calendar:calendar)}
        app.facts=[.init(label:"Approved apps",value:p.approved.isEmpty ? "None":p.approved.joined(separator:", ")),.init(label:"Last-known pending",value:String(pending.count)),.init(label:"Next toast eligible",value:p.appReminders ? Self.stamp(appDate):"Hourly reminders disabled"),.init(label:"Closed-app updates",value:p.autoClosed ? "Enabled":"Explicit request required"),.init(label:"Installomator file",value:providerPresent ? "Present · engine verifies trust":"Not found"),.init(label:"Monitor",value:mainMonitor.title)]
        app.nextStep="Review approvals and saved per-app results in App Updates."
        if !p.appsEnabled {app.status="Disabled by policy";app.reason="Third-party app management is opt-in and currently disabled.";app.tone = .inactive}
        else if p.dryRun {app.status="Dry run";app.reason="No live app checks, reminders, or updates are run.";app.tone = .inactive}
        else if p.approved.isEmpty {app.status="No apps approved";app.reason="Select approved apps before enabling their management.";app.tone = .attention}
        else if let appsIssue {app.status="Saved results unavailable";app.reason=appsIssue;app.tone = .attention}
        else if mainMonitor.blocksAutomation {app.status=mainMonitor.title;app.reason=mainMonitor.reason;app.tone = .attention;app.route = .monitoring;app.nextStep="Review Deployment to enable macOS/app monitoring explicitly."}
        else if approvedRecords.isEmpty {app.status="Not checked";app.reason="There are no saved results for the currently approved apps.";app.tone = .waiting}
        else if !failures.isEmpty {app.status="Check needs attention";app.reason="\(failures.count) approved app result(s) were skipped or failed. Review their saved reasons.";app.tone = .attention}
        else if !pending.isEmpty && !providerPresent {app.status="Update provider missing";app.reason="Checks and previews can work, but actual updates need the configured administrator-owned Installomator provider.";app.tone = .attention}
        else if pending.values.contains(where:{ ($0.result ?? "").lowercased().contains("open") }) {app.status="Apps were open at last check";app.reason="PUSH leaves open apps running. Close them when ready; the next check reassesses them.";app.tone = .waiting}
        else if !pending.isEmpty {app.status="\(pending.count) saved update(s) pending";app.reason=p.autoClosed ? "Automatic closed-app updates are enabled; the engine rechecks eligibility before updating.":"A user or admin must request app updates. No automatic installation is inferred.";app.tone = .waiting}
        else {app.status="No saved updates pending";app.reason="Saved approved-app results show no pending updates. This refresh did not query vendors.";app.tone = .good}
        reg.facts=[.init(label:"Local registration",value:entra?.status.title ?? "Not checked for this user"),.init(label:"Cloud compliance",value:"Not assessed"),.init(label:"Last check",value:Self.stamp(entra?.checkedAt)),.init(label:"Monitor",value:entraMonitor.title)]
        reg.nextStep="Review Entra setup, or copy the local-evidence check command."
        if !p.entraEnabled {reg.status="Disabled by policy";reg.reason="Entra reminders are disabled in the installed configuration.";reg.tone = .inactive}
        else if p.dryRun {reg.status="Dry run";reg.reason="Registration detection and user prompts remain inactive.";reg.tone = .inactive}
        else if let entraIssue {reg.status="Saved state unavailable";reg.reason=entraIssue;reg.tone = .attention}
        else if entra?.status == .notApplicable {reg.status="Inactive on this Mac";reg.reason="The last check found this Mac was not MDM enrolled. Production Entra prompts are inactive for that result.";reg.tone = .inactive;reg.nextStep="Validate registration on an enrolled test Mac. Recheck if this Mac's enrollment changes."}
        else if entra?.status == .localRegistered {reg.status="No registration nudge needed";reg.reason="Local Jamf registration evidence was detected. This is not a cloud-compliance verdict.";reg.tone = .good;if entra?.needsRecon == true {reg.nextStep="Inventory sync is pending; the monitor retries it separately from registration."}}
        else if entra?.status == .setupMissing || entra?.status == .verificationUnavailable {reg.status=entra?.status.title ?? "Unable to verify";reg.reason=entra?.reason ?? "No reliable evidence";reg.tone = .attention}
        else if entraMonitor.blocksAutomation {reg.status=entraMonitor.title;reg.reason=entraMonitor.reason;reg.tone = .attention;reg.route = .monitoring;reg.nextStep="Review monitoring after confirming the registration workflow on an enrolled test Mac."}
        else if let user=entra {
            let stage=EntraPolicy.stage(laterCount:user.laterCount)
            var eligible=max(now,(user.lastPromptAt ?? .distantPast).addingTimeInterval(stage.gap))
            let capped=user.dayKey == EntraPolicy.dayKey(now:now,calendar:calendar) && user.promptsToday >= stage.cap
            if capped {eligible=max(eligible,calendar.date(byAdding:.day,value:1,to:calendar.startOfDay(for:now))!)}
            let next=p.entraHours.nextAllowed(eligible,calendar:calendar)
            reg.status=capped ? "Daily prompt limit reached":"Registration reminder pending"
            reg.reason=capped ? "Today's attempt budget is exhausted. The next eligible working window is shown below.":"The monitor checks local evidence before deciding whether to prompt. Meetings and other active prompts can delay it."
            reg.tone = .waiting
            reg.facts += [.init(label:"Stage",value:String(stage.number)),.init(label:"Next eligibility",value:Self.stamp(next))]
        } else {reg.status="Not checked for this user";reg.reason="No production registration result is saved for the account using this dashboard.";reg.tone = .waiting}
        return [mac,app,reg]
    }
    // Assigned from the host snapshot, never used to query update catalogs.
    var runningOS: String = ""
    var summaryText: String {
        (["PUSH readiness · " + Self.stamp(capturedAt),"Engine: " + engineVersion,headline,explanation] + modules.flatMap { ["\($0.title): \($0.status)",$0.reason,"Next step: " + $0.nextStep] }).joined(separator:"\n")
    }
}
