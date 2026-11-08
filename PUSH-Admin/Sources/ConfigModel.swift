// PUSH Admin — Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

struct ConfigField: Identifiable {
    enum Kind { case text, multiline, boolean, number(ClosedRange<Int>), choice([String]) }
    let id: String
    let title: String
    let kind: Kind
    let initial: String
    let help: String
    init(_ id: String, _ title: String, _ kind: Kind = .text, _ initial: String = "", _ help: String = "") {
        self.id = id; self.title = title; self.kind = kind; self.initial = initial; self.help = help
    }
}
struct ConfigGroup: Identifiable {
    let id: String, title: String, subtitle: String, icon: String
    let fields: [ConfigField]
}
let configGroups: [ConfigGroup] = [
    .init(id:"wallpaper",title:"Compliance wallpaper",subtitle:"Reapply the managed image while the Mac is below its configured macOS target.",icon:"photo",fields:[
        .init("compliance.wallpaperEnabled","Enable compliance wallpaper",.boolean,"false"),
        .init("compliance.nonCompliantWallpaper","Non-compliant background path",.text,"/Library/Management/PUSH/assets/wallpapers/PUSH-NonCompliant.png"),
        .init("compliance.compliantWallpaper","Compliant background · blank restores personal image")]),
    .init(id:"entra", title:"Entra registration", subtitle:"Opt-in Jamf registration reminders, separate from cloud compliance.", icon:"person.crop.circle.badge.checkmark", fields:[
        .init("entra.enabled","Enable registration reminders",.boolean,"false"),
        .init("entra.policyID","Self Service registration policy ID",.text,"876"),
        .init("entra.startHour","Registration prompt start hour",.number(0...23),"8"),
        .init("entra.endHour","Registration prompt end hour",.number(1...24),"18"),
        .init("entra.weekdaysOnly","Weekdays only",.boolean,"true"),
        .init("entra.skipMeetings","Defer during meetings",.boolean,"true"),
        .init("entra.reconOnRegistration","Refresh inventory after local registration transition",.boolean,"true"),
        .init("entra.selfServicePath","Jamf Self Service app",.text,"/Applications/Self Service.app"),
        .init("entra.companyPortalPath","Microsoft Company Portal app",.text,"/Applications/Company Portal.app"),
        .init("entra.jamfBinaryPath","Trusted Jamf binary",.text,"/usr/local/bin/jamf"),
        .init("entra.message","Optional registration message",.multiline,"")]),
    .init(id:"apps", title:"App updates", subtitle:"Approve installed apps explicitly. Open apps and App Store copies are left alone.", icon:"square.stack.3d.up", fields:[
        .init("apps.enabled","Enable approved app management",.boolean,"false"),
        .init("apps.approved","Approved app IDs · comma separated",.text,"","Supported: chrome, firefox, vscode. Select these in App Updates."),
        .init("apps.autoUpdateClosed","Automatically update closed approved apps",.boolean,"false"),
        .init("apps.notifyHourly","Hourly grouped app reminders",.boolean,"true"),
        .init("apps.graceDays","App deadline · days from detection",.number(1...365),"7"),
        .init("apps.deadline","All-app deadline override · ISO 8601"),
        .init("apps.chromeDeadline","Chrome deadline override · ISO 8601"),
        .init("apps.firefoxDeadline","Firefox deadline override · ISO 8601"),
        .init("apps.vscodeDeadline","VS Code deadline override · ISO 8601"),
        .init("apps.installomatorPath","Administrator-owned Installomator script",.text,"/usr/local/Installomator/Installomator.sh")]),
    .init(id:"identity", title:"Organization & appearance", subtitle:"Make messages recognizable to your users.", icon:"building.2", fields:[
        .init("ui.menuBarEnabled","Show PUSH status in JamfCheckIn",.boolean,"true"),
        .init("ui.appName","Application title",.text,"PUSH — Software Update"), .init("ui.orgName","Organization"),
        .init("ui.itContactEmail","Support email"), .init("ui.itContactPhone","Support phone"), .init("ui.helpURL","Support website"),
        .init("ui.accentColorHex","Accent color",.text,"#0A84FF"), .init("ui.popupWidth","Popup width",.number(420...900),"540"),
        .init("ui.popupBackgroundStyle","Popup background",.choice(["solid","frosted"]),"solid"),
        .init("ui.popupOpacityPercent","Background strength · percent",.number(55...100),"85"),
        .init("ui.requireDeferralReason","Ask for a reason when choosing Later",.boolean,"false"),
        .init("ui.logoPath","Deployed logo path"), .init("ui.sfSymbolName","System symbol name"), .init("ui.hardBlockFullscreen","Cover all displays for hard blocks",.boolean,"false")]),
    .init(id:"updates", title:"Update policy", subtitle:"Choose the target explicitly, or let PUSH detect updates after deployment.", icon:"arrow.down.circle", fields:[
        .init("update.targetVersion","Required macOS version",.text,"","Use a full version such as 27.0. Selecting a catalog release fills this field."),
        .init("update.macOSName","macOS display name",.text,"macOS"), .init("update.releaseType","Update type",.choice(["minor","major"]),"minor"),
        .init("update.deadline","Deadline (ISO 8601)",.text,"","Overrides the automatic deadline, including for new targets. Clear it to use days from first detection. Example: 2026-12-01T18:00:00Z."),
        .init("update.deadlineRecoveryEnabled","Enable deadline failure recovery",.boolean,"true"),
        .init("update.retryCountdownMinutes","Recovery countdown · minutes",.number(1...60),"10"),
        .init("update.retryBackoffMinutes","Automatic retry spacing · minutes",.number(5...240),"30"),
        .init("update.maxAutomaticRetriesPerDay","Recovery attempts per rolling 24 hours",.number(0...6),"3"),
        .init("update.allowUserUpdateRequests","Allow user update requests",.boolean,"true"),
        .init("update.maxDeferrals","Allowed deferrals",.number(0...100),"5"),
        .init("update.toastIntervalSeconds","Toast interval · seconds",.number(60...604800),"3600"),
        .init("update.autoInstallAfterDeadline","Install automatically after deadline",.boolean,"false"),
        .init("update.silentInstallAfterDeadline","Install silently after deadline",.boolean,"false"),
        .init("update.prepareAtDeadlineWhenLoggedOut","Download at deadline while logged out",.boolean,"true"),
        .init("update.forceRestartAfterInstall","Request restart after installation",.boolean,"false")]),
    .init(id:"detection", title:"Automatic detection", subtitle:"Discovery and enforcement are separate from checking the catalog in this app.", icon:"sparkle.magnifyingglass", fields:[
        .init("auto.enabled","Enable PUSH auto-check policy",.boolean,"false"),
        .init("auto.trackLatest","Keep following new releases after the saved target is met",.boolean,"false"),
        .init("auto.useMist","Also discover compatible full installers using mist-cli",.boolean,"true"),
        .init("auto.minorOnly","Limit detection to the current major release",.boolean,"true"),
        .init("auto.skipBetas","Exclude beta releases",.boolean,"true"),
        .init("auto.enforceMinimumMajorVersion","Minimum major version · 0 disables",.number(0...100),"0"),
        .init("auto.minorDeadlineDays","Minor update deadline · days",.number(1...365),"7"),
        .init("auto.majorDeadlineDays","Major upgrade deadline · days",.number(1...365),"14"),
        .init("auto.minorMaxDeferrals","Minor update deferrals",.number(0...100),"5"),
        .init("auto.majorMaxDeferrals","Major upgrade deferrals",.number(0...100),"7"),
        .init("auto.autoInstallNonSystemUpdates","Install non-system updates automatically",.boolean,"false"),
        .init("ddm.enabled","Step aside when DDM manages the update",.boolean,"true")]),
    .init(id:"schedule", title:"Hours & interruptions", subtitle:"Respect working hours, calls, and screen sharing.", icon:"calendar.badge.clock", fields:[
        .init("schedule.respectAlertWindow","Restrict reminders to working hours",.boolean,"false"),
        .init("schedule.alertStartHour","Start hour · local time",.number(0...23),"8"),
        .init("schedule.alertEndHour","End hour · local time",.number(1...24),"18"),
        .init("schedule.skipWeekends","Skip weekends",.boolean,"true"),
        .init("schedule.skipDuringMeetings","Defer prompts during meetings",.boolean,"true"),
        .init("schedule.skipInstallDuringScreenShare","Defer installation during screen sharing",.boolean,"true"),
        .init("schedule.skipOnVPN","Defer prompts while on VPN",.boolean,"false")]),
    .init(id:"restart", title:"Restart reminders", subtitle:"Use uptime to nudge, then escalate when necessary.", icon:"restart", fields:[
        .init("uptime.enabled","Enable uptime reminders",.boolean,"false"),
        .init("uptime.warningThresholdDays","First reminder after · days",.number(1...365),"14"),
        .init("uptime.forceThresholdDays","Escalate after · days",.number(1...365),"20"),
        .init("uptime.maxDeferrals","Restart deferrals",.number(0...100),"3"),
        .init("uptime.promptIntervalDays","Repeat interval · days",.number(1...30),"1"),
        .init("uptime.forceTimerSeconds","Forced countdown · seconds",.number(60...7200),"600"),
        .init("uptime.skipDuringMeeting","Defer during meetings",.boolean,"true")]),
    .init(id:"preflight", title:"Preflight checks", subtitle:"Check capacity and power before attempting installation.", icon:"checkmark.shield", fields:[
        .init("preflight.minDiskSpaceGB","Required free disk space · GB",.number(15...200),"40"),
        .init("preflight.minBatteryPercent","Minimum battery · 0 disables",.number(0...100),"50"),
        .init("preflight.powerCheckTimeoutMinutes","Wait for power · minutes",.number(1...120),"5"),
        .init("preflight.checkNetworkReachability","Check network reachability",.boolean,"true"),
        .init("preflight.skipOnVPN","Defer installation on VPN",.boolean,"false"),
        .init("preflight.diskSpaceLearnMoreURL","Storage help website")]),
    .init(id:"messages", title:"User messages", subtitle:"Preview these messages in Popup Studio before exporting.", icon:"text.bubble", fields:[
        .init("ui.minorMessage","Minor update",.multiline,"A required macOS security update is available. Please save your work and install the update."),
        .init("ui.majorMessage","Major upgrade",.multiline,"A major macOS upgrade is available. Please save your work before continuing."),
        .init("ui.deadlineMessage","Deadline reached",.multiline,"The update deadline has passed. Please save your work."),
        .init("ui.alreadyUpToDateMessage","Already compliant",.multiline,"Your Mac is running the required version of macOS. No action needed."),
        .init("ui.installingMessage","Installation",.multiline,"Please keep your Mac powered on and connected to power."),
        .init("ui.installMinorButtonLabel","Install button",.text,"Install Now"),
        .init("ui.installMajorButtonLabel","Upgrade button",.text,"Begin Upgrade"),
        .init("ui.deferButtonLabel","Defer button",.text,"Remind Me Later")]),
    .init(id:"toast", title:"Toast notifications", subtitle:"Set placement, appearance, and optional sound.", icon:"bell.badge", fields:[
        .init("toast.message","Toast message · empty uses the concise default",.multiline,""),
        .init("toast.autoDismissSeconds","Close automatically · seconds, 0 stays open",.number(0...900),"0"),
        .init("toast.position","Corner",.choice(["topRight","topLeft","bottomRight","bottomLeft"]),"topRight"),
        .init("toast.width","Width",.number(300...700),"420"), .init("toast.screenMargin","Screen margin",.number(0...100),"16"),
        .init("toast.showCloseButton","Show close button",.boolean,"true"), .init("toast.showDeferButton","Show Later button",.boolean,"true"),
        .init("toast.soundName","System sound · empty is silent",.text,""),
        .init("toast.installButtonLabel","Install button",.text,"Install Now"), .init("toast.deferButtonLabel","Defer button",.text,"Later")]),
    .init(id:"management", title:"Management & authorization", subtitle:"Configure IT-managed authorization. End-user password prompts remain disabled.", icon:"key.horizontal", fields:[
        .init("auth.localAccount","Managed local admin account"), .init("jamf.url","Jamf Pro URL"),
        .init("jamf.clientId","Jamf API client ID"), .init("jamf.reportEAAfterCheck","Report compliance to Jamf",.boolean,"false"),
        .init("jamf.eaName","Extension attribute",.text,"OS Update Compliance"),
        .init("laps.enabled","Use Jamf LAPS",.boolean,"false"), .init("laps.accountName","LAPS managed account"), .init("laps.clientId","LAPS API client ID")]),
    .init(id:"testing", title:"Testing & logs", subtitle:"New drafts start in dry-run mode. Exporting never enables a daemon.", icon:"ladybug", fields:[
        .init("debug.dryRun","Dry-run mode",.boolean,"true"),
        .init("debug.testToastIntervalMinutes","Test toast interval · 0 uses policy",.number(0...1440),"0"),
        .init("debug.testNudgeIntervalMinutes","Test nudge interval · 0 uses policy",.number(0...1440),"0"),
        .init("logging.maxLogSizeMB","Maximum log size · MB",.number(1...1000),"10"),
        .init("logging.maxRotatedLogs","Rotated logs to keep",.number(1...50),"5")])
]

struct ConfigDocument: Codable {
    var source = "# PUSH — configured with PUSH Admin\n# Developer: Sebastian Santos\n# Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS\n"
    var edits: [String:String] = [:]
    var sourceName = "New configuration"
    var majorOfferSettings:MajorOfferSettings?=nil
    var logoImageData: Data? = nil
    var wallpaperAssets: [String:WallpaperAssetReference]? = nil
    var logoImageName: String? = nil
    var omittedCredentials = 0
    var formatIssues: [String] = []
    static let sensitive: Set<String> = ["localPassword","accountPassword","clientSecret","accessToken","refreshToken"]
    static func load(_ text: String, name: String) -> ConfigDocument {
        var document = ConfigDocument(); document.sourceName = name
        var clean: [String] = [], blockIndent: Int?
        for line in text.components(separatedBy:"\n") {
            let t = line.trimmingCharacters(in:.whitespaces)
            let indent = line.prefix { $0 == " " }.count
            if let b = blockIndent, t.isEmpty || indent > b { continue }
            blockIndent = nil
            if t.hasPrefix("#"), sensitive.contains(where: { t.contains($0 + ":") }) {
                clean.append("# Credential-bearing comment omitted by PUSH Admin.")
                continue
            }
            let key = String(t.prefix { $0 != ":" })
            if sensitive.contains(key), let colon = line.firstIndex(of:":") {
                let value = String(line[line.index(after:colon)...]).trimmingCharacters(in:.whitespaces)
                if !["", "\"\"", "''"].contains(value) { document.omittedCredentials += 1 }
                clean.append(String(line[..<line.index(after:colon)]) + " \"\"")
                blockIndent = indent
            } else { clean.append(line) }
        }
        var seenSections = Set<String>()
        var scalarBlock: Int?
        for (index,line) in clean.enumerated() {
            let t = line.trimmingCharacters(in:.whitespaces)
            let indent = line.prefix { $0 == " " }.count
            if t.isEmpty || t.hasPrefix("#") || t == "---" { continue }
            if let block = scalarBlock, indent > block { continue }
            scalarBlock = nil
            if line.contains("\t") { document.formatIssues.append("Line \(index+1): use spaces instead of tabs in PUSH YAML.") }
            if t.hasPrefix("{") || t.hasPrefix("[") { document.formatIssues.append("Use PUSH section-and-field YAML rather than a JSON or flow-style document."); break }
            guard let colon = t.firstIndex(of:":") else {
                if !t.hasPrefix("- ") { document.formatIssues.append("Line \(index+1): expected a YAML field or section.") }
                continue
            }
            if indent == 0, t.hasSuffix(":") {
                if !seenSections.insert(t).inserted { document.formatIssues.append("Duplicate section \(t) must be merged before import.") }
            }
            let raw = String(t[t.index(after:colon)...]).trimmingCharacters(in:.whitespaces)
            if ["|","|-","|+",">",">-",">+"].contains(raw) { scalarBlock = indent }
            if raw.hasPrefix("&") || raw.hasPrefix("*") || raw.hasPrefix("!") { document.formatIssues.append("YAML anchors and tags are not supported by PUSH’s configuration parser.") }
        }
        document.source = clean.joined(separator:"\n")
        return document
    }
    static var fresh: ConfigDocument {
        var document = ConfigDocument()
        for field in configGroups.flatMap(\.fields) { document.edits[field.id] = field.initial }
        return document
    }
    func value(_ field: ConfigField) -> String { value(field.id) ?? field.initial }
    func value(_ id: String) -> String? {
        if let value = edits[id] { return value }
        let pieces = id.split(separator:".").map(String.init)
        guard pieces.count == 2 else { return nil }
        var section = ""
        let sourceLines = source.components(separatedBy:"\n")
        for (lineIndex,line) in sourceLines.enumerated() {
            let t = line.trimmingCharacters(in:.whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            let indent = line.prefix { $0 == " " }.count
            if indent == 0, t.hasSuffix(":") { section = String(t.dropLast()); continue }
            guard indent == 2, section == pieces[0], let colon = t.firstIndex(of:":"), String(t[..<colon]) == pieces[1] else { continue }
            let raw = String(t[t.index(after:colon)...]).trimmingCharacters(in:.whitespaces)
            if ["|","|-","|+",">",">-",">+"].contains(raw) {
                var body: [String] = []
                for continuation in sourceLines.dropFirst(lineIndex+1) {
                    if !continuation.isEmpty && continuation.prefix(while: { $0 == " " }).count <= 2 { break }
                    body.append(String(continuation.dropFirst(min(4,continuation.prefix(while: { $0 == " " }).count))))
                }
                return body.joined(separator:raw.hasPrefix(">") ? " " : "\n")
            }
            if raw.hasPrefix("\""), let data = raw.data(using:.utf8), let decoded = try? JSONDecoder().decode(String.self,from:data) { return decoded }
            if raw.hasPrefix("'"), raw.hasSuffix("'") { return String(raw.dropFirst().dropLast()).replacingOccurrences(of:"''",with:"'") }
            return raw.components(separatedBy:" #").first ?? raw
        }
        return nil
    }
    var yaml: String {
        var lines = source.components(separatedBy:"\n")
        let fields = Dictionary(uniqueKeysWithValues:configGroups.flatMap(\.fields).map { ($0.id,$0) })
        for id in fields.keys.sorted() {
            guard let field = fields[id] else { continue }
            let value = self.value(field)
            let parts = id.split(separator:".").map(String.init)
            var start: Int
            if let header = lines.firstIndex(where:{ $0 == parts[0] + ":" }) { start = header+1 }
            else { if lines.last != "" { lines.append("") }; lines.append(parts[0]+":"); start = lines.count }
            var end = (start..<lines.count).first { index in
                let line = lines[index]; return !line.isEmpty && !line.hasPrefix(" ") && !line.hasPrefix("#")
            } ?? lines.count
            let encoded: String
            switch field.kind {
            case .boolean: encoded = value == "true" ? "true" : "false"
            case .number: encoded = String(Int(value) ?? 0)
            default:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.withoutEscapingSlashes]
                encoded = String(data:try! encoder.encode(value),encoding:.utf8)!
            }
            var index = start
            while index < end {
                if lines[index].hasPrefix("  " + parts[1] + ":") {
                    var stop = index+1
                    while stop < end && (lines[stop].isEmpty || lines[stop].prefix { $0 == " " }.count > 2) { stop += 1 }
                    lines.removeSubrange(index..<stop); end -= stop-index
                } else { index += 1 }
            }
            lines.insert("  " + parts[1] + ": " + encoded,at:end)
        }
        return lines.joined(separator:"\n") + "\n"
    }
    var problems: [String] {
        var errors: [String] = formatIssues
        for field in configGroups.flatMap(\.fields) {
            let v = value(field)
            if case .number(let range) = field.kind, Int(v).map({range.contains($0)}) != true { errors.append("\(field.title): enter a number in \(range.lowerBound)…\(range.upperBound).") }
            if case .choice(let options) = field.kind, !options.contains(v) { errors.append("\(field.title): choose a supported value.") }
        }
        if EntraPolicy.selfServiceURL(policyID:value("entra.policyID") ?? "876") == nil { errors.append("Entra Self Service policy ID must be a positive number.") }
        if let start = Int(value("entra.startHour") ?? "8"), let end = Int(value("entra.endHour") ?? "18"), start >= end { errors.append("Entra end hour must follow its start hour.") }
        for key in ["entra.selfServicePath","entra.companyPortalPath"] {
            if let path = value(key), !path.hasPrefix("/Applications/") || !path.hasSuffix(".app") { errors.append(key + ": choose an app in /Applications.") }
        }
        if let path = value("entra.jamfBinaryPath"), !path.hasPrefix("/") || !path.hasSuffix("/jamf") { errors.append("Entra Jamf binary path must be absolute and end in /jamf.") }
        if (value("entra.message") ?? "").count > 2000 { errors.append("Keep the Entra message within 2000 characters.") }
        let approved = AppUpdatePolicy.ids(value("apps.approved") ?? "")
        if !approved.allSatisfy({ id in ApprovedApp.catalog.contains { $0.id == id } }) { errors.append("Choose supported app IDs: chrome, firefox, vscode.") }
        if value("apps.enabled") == "true" && approved.isEmpty { errors.append("Approve at least one app before enabling app management.") }
        for key in ["apps.deadline","apps.chromeDeadline","apps.firefoxDeadline","apps.vscodeDeadline"] {
            if let date = value(key), !date.isEmpty, ISO8601DateFormatter().date(from:date) == nil { errors.append(key + ": use an ISO 8601 timestamp with time zone.") }
        }
        if let path = value("apps.installomatorPath"), !path.hasPrefix("/") || !path.hasSuffix("/Installomator.sh") { errors.append("Choose an absolute path ending in /Installomator.sh.") }
        if let v = value("update.targetVersion"), !v.isEmpty, versionParts(v) == nil { errors.append("Target macOS version must be numeric, such as 27.0.") }
        if let date = value("update.deadline"), !date.isEmpty, ISO8601DateFormatter().date(from:date) == nil { errors.append("Deadline must include date, time, and time zone in ISO 8601 format.") }
        if let start = Int(value("schedule.alertStartHour") ?? "8"), let end = Int(value("schedule.alertEndHour") ?? "18"), start >= end { errors.append("Alert end hour must be after the start hour.") }
        if let warning = Int(value("uptime.warningThresholdDays") ?? "14"), let force = Int(value("uptime.forceThresholdDays") ?? "20"), force < warning { errors.append("Restart escalation must follow the first reminder.") }
        if let path = value("ui.logoPath"), !path.isEmpty, !path.hasPrefix("/") { errors.append("The deployed logo path must be an absolute path on managed Macs.") }
        let color = value("ui.accentColorHex") ?? "#0A84FF"
        if color.range(of:"^#[0-9a-fA-F]{6}$",options:.regularExpression) == nil { errors.append("Accent color must be a six-digit hex color, such as #0A84FF.") }
        for id in ["jamf.url","ui.helpURL","preflight.diskSpaceLearnMoreURL"] {
            if let v = value(id), !v.isEmpty, URL(string:v)?.scheme != "https" { errors.append("\(id): use an HTTPS address.") }
        }
        if value("compliance.wallpaperEnabled") == "true" && value("auto.enabled") != "true" {errors.append("Enable automatic macOS checks before using compliance wallpaper.")}
        for key in ["compliance.nonCompliantWallpaper","compliance.compliantWallpaper"] {
            if let path=value(key),!path.isEmpty,!path.hasPrefix("/Library/Management/PUSH/") {errors.append("Wallpaper paths must be inside /Library/Management/PUSH. Use Wallpaper to stage a custom image.")}
        }
        if let settings=majorOfferSettings {do{_=try settings.validated()}catch{errors.append(error.localizedDescription)}}
        return errors
    }
}

func versionParts(_ text: String) -> [Int]? {
    let pieces = text.split(separator:".",omittingEmptySubsequences:false)
    guard (1...3).contains(pieces.count), pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy({$0.isASCII && $0.isNumber}) }) else { return nil }
    let numbers = pieces.compactMap { Int($0) }; guard numbers.count == pieces.count else { return nil }
    return numbers + Array(repeating:0,count:3-numbers.count)
}

extension ConfigDocument {
    mutating func followReleases(allowMajorUpgrades: Bool) {
        edits["auto.enabled"] = "true"
        edits["auto.trackLatest"] = "true"
        edits["auto.minorOnly"] = allowMajorUpgrades ? "false" : "true"
        edits["auto.skipBetas"] = "true"
        edits["auto.useMist"] = "true"
        edits["update.targetVersion"] = ""
        // Preserve the admin's deadline override, branding, hours, and enforcement choices.
    }
}


extension ConfigDocument {
    mutating func approveApp(_ id: String, enabled: Bool) {
        guard ApprovedApp.catalog.contains(where: { $0.id == id }) else { return }
        var selected = Set(AppUpdatePolicy.ids(value("apps.approved") ?? ""))
        if enabled { selected.insert(id) } else { selected.remove(id) }
        edits["apps.approved"] = selected.sorted().joined(separator:",")
    }
}

extension ConfigDocument {
    func appPreviewNotices(now: Date = Date()) -> [AppUpdateNotice] {
        let selected = AppUpdatePolicy.ids(value("apps.approved") ?? "")
        return AppUpdateNotice.examples.filter { selected.isEmpty || selected.contains($0.id) }.map { sample in
            var row = sample
            let perApp = value("apps." + sample.id + "Deadline") ?? ""
            let all = value("apps.deadline") ?? ""
            let date = AppUpdatePolicy.deadline(override:perApp.isEmpty ? all : perApp,firstSeen:now,days:Int(value("apps.graceDays") ?? "7") ?? 7)
            row.deadline = date.map { ISO8601DateFormatter().string(from:$0) } ?? "Invalid draft deadline"
            return row
        }
    }
}

extension ConfigDocument {
    func entraPreviewNotice(stage: Int) -> EntraNotice {
        var notice = EntraNotice.preview(stage:stage)
        if let text = value("entra.message"), !text.isEmpty { notice.message = text }
        return notice
    }
}
