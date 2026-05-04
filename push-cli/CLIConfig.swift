// CLIConfig.swift — Config model and YAML parser for push-cli

import Foundation

// MARK: - Root config

struct CLIConfig: Codable {
    var update:    CLIUpdateConfig    = .init()
    var ui:        CLIUIConfig        = .init()
    var toast:     CLIToastConfig     = .init()
    var preflight: CLIPreflightConfig = .init()
    var auto:      CLIAutoConfig      = .init()
    var schedule:  CLIScheduleConfig  = .init()
    var ddm:       CLIDDMConfig       = .init()
    var jamf:       CLIJamfConfig       = .init()
    var auth:       CLIAuthConfig       = .init()
    var uptime:     CLIUptimeConfig     = .init()
    var compliance: CLIComplianceConfig = .init()
    var debug:      CLIDebugConfig      = .init()
    var logging:    CLILoggingConfig    = .init()
}

struct CLIUpdateConfig: Codable {
    var targetVersion:               String = ""
    var macOSName:                   String = "macOS"
    var releaseType:                 String = "minor"
    var deadline:                    String = ""
    var maxDeferrals:                Int    = 5
    var nudgeIntervalSeconds:        Int    = 3600
    var toastIntervalSeconds:        Int    = 3600   // how often toast appears (default 1 hour)
    var silentInstallAfterDeadline:  Bool   = false
    var autoInstallAfterDeadline:     Bool   = true   // Auto-download+install when deadline passes
    var forceRestartAfterInstall:    Bool   = false
    var requirePasswordOnAppleSilicon: Bool = true
    var selfUpdateURL: String = ""   // GitHub releases API URL for self-update
}

struct CLIUIConfig: Codable {
    var appName:                 String = "Software Update Required"
    var orgName:                 String = ""
    var accentColorHex:          String = "#0A84FF"
    var logoPath:                String = ""
    var sfSymbolName:            String = ""
    var popupWidth:              Int    = 540
    var itContactEmail:          String = ""
    var itContactPhone:          String = ""
    var helpURL:                 String = ""
    var hardBlockFullscreen:     Bool   = false
    var minorMessage:            String = "A required macOS security update is available."
    var majorMessage:            String = "A major macOS upgrade is required."
    var deadlineMessage:         String = "Your Mac must be updated immediately."
    var downloadingMessage:      String = "Downloading the macOS update in the background."
    var installingMessage:       String = "Installation in progress. This takes 45–60 minutes."
    var alreadyUpToDateMessage:  String = "Your Mac is up to date."
    var forcedInstallMessage:    String = ""
    var forcedInstallNotice:     String = ""
    var installMinorButtonLabel: String = "Install Now"
    var installMajorButtonLabel: String = "Begin Upgrade"
    var deferButtonLabel:        String = "Remind Me Later"
}

struct CLIToastConfig: Codable {
    var position:           String = "topRight"
    var width:              Int    = 420
    var screenMargin:       Int    = 16
    var cornerRadius:       Int    = 16
    var showCloseButton:    Bool   = true
    var showDeferButton:    Bool   = true
    var installButtonLabel: String = "Install Now"
    var deferButtonLabel:   String = "Later"
    var soundName:          String = "Funk"
}

struct CLIPreflightConfig: Codable {
    var powerCheckTimeoutMinutes: Int    = 5
    var minDiskSpaceGB:           Int    = 25
    var diskSpaceLearnMoreURL:    String = ""
    var minBatteryPercent:        Int    = 0       // 0 = disabled
    var checkNetworkReachability: Bool   = true    // skip download if Apple CDN unreachable
    var skipOnVPN:                Bool   = false   // skip popup if VPN is active
}

struct CLIAutoConfig: Codable {
    var enabled:              Bool   = true
    var minorOnly:            Bool   = false
    var skipBetas:            Bool   = true
    var minorDeadlineDays:    Int    = 5
    var majorDeadlineDays:    Int    = 7
    var minorMaxDeferrals:    Int    = 5
    var majorMaxDeferrals:    Int    = 7
    var skipVersions:         [String] = []
    var adminWebhookURL:      String = ""
    var notifyAdminOnDetection:   Bool   = false
    // Webhook event triggers
    var notifyOnDeadlineHit:      Bool   = true
    var notifyOnDeferralExhausted:Bool   = true
    var notifyOnInstallComplete:  Bool   = true
    /// Auto-install non-system updates (Safari, XProtect, command-line tools, etc.)
    /// in the background during regular auto-check runs. These don't require reboots
    /// so they're safe to install silently — reduces deadline-day install bloat.
    var autoInstallNonSystemUpdates: Bool = true
    // Set the minimum major version you want to enforce across your fleet.
    // e.g. enforceMinimumMajorVersion: 26
    // Machines on any lower major (15.x, 14.x) → major upgrade nudge
    // Machines already on 26.x but behind on minor → minor update nudge
    // Leave 0 to let auto-check decide purely from softwareupdate output.
    var enforceMinimumMajorVersion: Int = 0
}

struct CLIScheduleConfig: Codable {
    var alertStartHour:       Int  = 8
    var alertEndHour:         Int  = 18
    var skipWeekends:         Bool = true
    // Skip popups when camera/mic is in use or screen is being shared
    var skipDuringMeetings:   Bool = true
    // Skip nudge/toast popups when on VPN.
    // Separate from preflight.skipOnVPN which blocks downloads/installs.
    var skipOnVPN:            Bool = false
    /// Defer post-deadline forced install if the user is actively screen-sharing
    /// or in a live meeting. Detection only fires on real-time signals (active
    /// screensharingd, mic capturing). Costs at most one hour of enforcement
    /// delay since the daemon will retry on the next run.
    var skipInstallDuringScreenShare: Bool = true
}

struct CLIDDMConfig: Codable {
    var enabled: Bool = true
}

/// Uptime monitoring — prompts the user to restart if their Mac has been
/// running too long. Long uptimes accumulate kernel issues and prevent
/// some security updates from applying.
struct CLIUptimeConfig: Codable {
    var enabled:                 Bool = true
    /// Days of uptime before the friendly "please restart" prompt starts appearing.
    /// Below this, PUSH says nothing about uptime.
    var warningThresholdDays:    Int  = 14
    /// Days of uptime that trigger the forced timer popup.
    /// Reached either via clock-time OR by exhausting maxDeferrals, whichever comes first.
    var forceThresholdDays:      Int  = 20
    /// How many times the user can click "Later" during the warning phase before
    /// being escalated to the forced timer.
    var maxDeferrals:            Int  = 3
    /// Days between repeat prompts during warning phase.
    var promptIntervalDays:      Int  = 1
    /// Seconds the countdown runs in the forced phase before auto-restart.
    var forceTimerSeconds:       Int  = 600
    /// Defer the forced restart if the user is in an active meeting / screen share.
    /// Same detection as install deferral. Costs at most one cycle of delay.
    var skipDuringMeeting:       Bool = true
    /// DEPRECATED — kept for config backward compatibility but no longer used.
    /// Uptime prompts now skip whenever ANY OS update is pending, regardless
    /// of how far the deadline is. The reboot-for-OS-update will cover it.
    var skipIfOSUpdateImminentDays: Int = 3
}

/// Compliance signaling — sets the desktop wallpaper based on OS update
/// compliance state, so users get a passive visual cue without an extra popup.
/// Compliant Mac → "compliant" wallpaper. Non-compliant Mac → "non-compliant"
/// wallpaper. Wallpaper changes only fire on state TRANSITIONS, not every
/// auto-check, so the user keeps any custom wallpaper between transitions.
///
/// Requires desktoppr — bundled at desktopprPkgPath, lazy-installed on first
/// wallpaper apply.
struct CLIComplianceConfig: Codable {
    /// Master switch. Default false so existing deployments don't surprise users.
    /// Flip to true once wallpapers are in place and you want visual signaling.
    var wallpaperEnabled:        Bool   = false
    var compliantWallpaper:      String = "/Library/Management/PUSH/Compliance-Background/compliant.jpg"
    var nonCompliantWallpaper:   String = "/Library/Management/PUSH/Compliance-Background/non-compliant.jpg"
    /// Hex color (no #) used as the desktop background when the image doesn't
    /// fully cover the screen (letterboxing).
    var wallpaperBackgroundColor: String = "020C19"
    /// desktoppr scale mode: fit | fill | stretch | center | tile
    var wallpaperScale:          String = "fit"
    /// Where desktoppr is installed (or expected to be).
    var desktopprPath:           String = "/usr/local/bin/desktoppr"
    /// Bundled installer for lazy-install if desktoppr is missing.
    var desktopprPkgPath:        String = "/Library/Management/PUSH/Compliance-Background/desktoppr.pkg"
}

struct CLIJamfLapsConfig: Codable {
    var enabled:       Bool   = false
    var accountName:   String = ""       // e.g. "CasperLocalAdmin"
    var clientId:      String = ""       // LAPS-scoped API client
    var clientSecret:  String = ""       // fallback if keychain has no secret
}

struct CLIJamfConfig: Codable {
    var url:              String = ""
    var eaName:           String = "OS Update Compliance"
    var binaryPath:       String = "/usr/local/bin/jamf"
    var reportEAAfterCheck: Bool = true
    // OAuth (client credentials) — preferred for Jamf Pro 10.48+
    var clientId:         String = ""
    var clientSecret:     String = ""
    // Legacy account credentials
    var accountName:      String = ""
    var accountPassword:  String = ""
    // Computer ID override (auto-detected via serial number if empty)
    var computerId:       String = ""
    // LAPS (Local Administrator Password Solution) integration
    var laps:             CLIJamfLapsConfig = .init()
}

// CLIAuthConfig — local account credentials for Apple Silicon auth
struct CLIAuthConfig: Codable {
    // Local admin account used for softwareupdate/startosinstall --user/--stdinpass
    var localAccount:  String = ""
    var localPassword: String = ""
}

struct CLIDebugConfig: Codable {
    var dryRun:                   Bool = false
    var testToastIntervalMinutes: Int  = 0
    var testNudgeIntervalMinutes: Int  = 0
}

struct CLILoggingConfig: Codable {
    var maxLogSizeMB:    Int  = 10    // rotate when log exceeds this size
    var maxRotatedLogs:  Int  = 5     // keep this many rotated logs
}

// MARK: - Deferral state

struct CLIDeferralState: Codable {
    var deferralCount:      Int    = 0
    var nextAlertDate:      Date   = .distantPast   // legacy compat
    var nextNudgeDate:      Date   = .distantPast   // 24h nudge schedule
    var nextToastDate:      Date   = .distantPast   // 1h toast schedule
    var lastSeenVersion:    String = ""
    var installStarted:     Bool   = false
    var installCompleted:   Bool   = false
    var deadlineNotifiedAt: Date?  = nil
    var gracePeriodUntil:   Date?  = nil   // IT-granted extension
    var deferralReasons:    [String] = []  // reasons user gave when deferring

    // Uptime monitoring — tracks the user's reboot deferrals within the
    // current uptime cycle. Reset to zero whenever a real reboot is detected
    // (boot timestamp differs from lastBootTimestamp).
    var uptimeDeferralCount:     Int    = 0
    var uptimeNextPromptDate:    Date   = .distantPast
    var uptimeLastBootTimestamp: Double = 0       // sysctl kern.boottime sec

    /// Compliance wallpaper transition tracking. Set to "compliant" or
    /// "non-compliant" after wallpaper applied. Empty string = not yet set.
    /// Used to avoid re-applying the same wallpaper on every auto-check.
    var lastAppliedWallpaperState: String = ""
}

// MARK: - Load

extension CLIConfig {

    static func load(from path: String) throws -> CLIConfig {
        guard let data   = FileManager.default.contents(atPath: path),
              let source = String(data: data, encoding: .utf8)
        else { throw CLIError.configNotFound }
        return parse(yaml: source)
    }

    // MARK: - YAML parser

    static func parse(yaml source: String) -> CLIConfig {
        var c = CLIConfig()

        func str(_ d: [String: Any], _ k: String, _ def: String = "") -> String {
            if let v = d[k] as? String   { return v }
            if let n = d[k] as? NSNumber { return n.stringValue }
            return def
        }
        func int(_ d: [String: Any], _ k: String, _ def: Int = 0) -> Int {
            if let n = d[k] as? NSNumber { return n.intValue }
            if let s = d[k] as? String, let i = Int(s) { return i }
            return def
        }
        func boo(_ d: [String: Any], _ k: String, _ def: Bool = false) -> Bool {
            if let b = d[k] as? Bool     { return b }
            if let n = d[k] as? NSNumber { return n.boolValue }
            if let s = d[k] as? String   { return s == "true" || s == "yes" }
            return def
        }

        let root = parseYAMLDict(source)

        if let u = root["update"] as? [String: Any] {
            c.update.targetVersion                = str(u, "targetVersion")
            c.update.macOSName                    = str(u, "macOSName", "macOS")
            c.update.releaseType                  = str(u, "releaseType", "minor")
            c.update.deadline                     = str(u, "deadline")
            c.update.maxDeferrals                 = int(u, "maxDeferrals", 5)
            c.update.nudgeIntervalSeconds         = int(u, "nudgeIntervalSeconds", 3600)
            c.update.toastIntervalSeconds         = int(u, "toastIntervalSeconds", 3600)
            c.update.silentInstallAfterDeadline   = boo(u, "silentInstallAfterDeadline", false)
            c.update.autoInstallAfterDeadline     = boo(u, "autoInstallAfterDeadline",    true)
            c.update.forceRestartAfterInstall     = boo(u, "forceRestartAfterInstall", false)
            c.update.requirePasswordOnAppleSilicon = boo(u, "requirePasswordOnAppleSilicon", true)
            c.update.selfUpdateURL                = str(u, "selfUpdateURL",                "")
        }

        if let u = root["ui"] as? [String: Any] {
            c.ui.appName                  = str(u, "appName",   c.ui.appName)
            c.ui.orgName                  = str(u, "orgName",   "")
            c.ui.accentColorHex           = str(u, "accentColorHex", "#0A84FF")
            c.ui.logoPath                 = str(u, "logoPath",  "")
            c.ui.sfSymbolName             = str(u, "sfSymbolName", "")
            c.ui.popupWidth               = int(u, "popupWidth", 500)
            c.ui.itContactEmail           = str(u, "itContactEmail", "")
            c.ui.itContactPhone           = str(u, "itContactPhone", "")
            c.ui.helpURL                  = str(u, "helpURL",   "")
            c.ui.hardBlockFullscreen      = boo(u, "hardBlockFullscreen", false)
            c.ui.minorMessage             = str(u, "minorMessage",            c.ui.minorMessage)
            c.ui.majorMessage             = str(u, "majorMessage",            c.ui.majorMessage)
            c.ui.deadlineMessage          = str(u, "deadlineMessage",         c.ui.deadlineMessage)
            c.ui.downloadingMessage       = str(u, "downloadingMessage",      c.ui.downloadingMessage)
            c.ui.installingMessage        = str(u, "installingMessage",       c.ui.installingMessage)
            c.ui.alreadyUpToDateMessage   = str(u, "alreadyUpToDateMessage",  c.ui.alreadyUpToDateMessage)
            c.ui.forcedInstallMessage     = str(u, "forcedInstallMessage",    c.ui.forcedInstallMessage)
            c.ui.forcedInstallNotice      = str(u, "forcedInstallNotice",     c.ui.forcedInstallNotice)
            c.ui.installMinorButtonLabel  = str(u, "installMinorButtonLabel", c.ui.installMinorButtonLabel)
            c.ui.installMajorButtonLabel  = str(u, "installMajorButtonLabel", c.ui.installMajorButtonLabel)
            c.ui.deferButtonLabel         = str(u, "deferButtonLabel",        c.ui.deferButtonLabel)
        }

        if let t = root["toast"] as? [String: Any] {
            c.toast.position           = str(t, "position",           "topRight")
            c.toast.width              = int(t, "width",              360)
            c.toast.screenMargin       = int(t, "screenMargin",       16)
            c.toast.cornerRadius       = int(t, "cornerRadius",       16)
            c.toast.showCloseButton    = boo(t, "showCloseButton",    true)
            c.toast.showDeferButton    = boo(t, "showDeferButton",    true)
            c.toast.installButtonLabel = str(t, "installButtonLabel", "Install Now")
            c.toast.deferButtonLabel   = str(t, "deferButtonLabel",   "Later")
            c.toast.soundName          = str(t, "soundName",          "Funk")
        }

        if let p = root["preflight"] as? [String: Any] {
            c.preflight.powerCheckTimeoutMinutes = int(p, "powerCheckTimeoutMinutes", 5)
            c.preflight.minDiskSpaceGB           = int(p, "minDiskSpaceGB",           25)
            c.preflight.diskSpaceLearnMoreURL    = str(p, "diskSpaceLearnMoreURL",    "")
            c.preflight.minBatteryPercent        = int(p, "minBatteryPercent",        0)
            c.preflight.checkNetworkReachability = boo(p, "checkNetworkReachability", true)
            c.preflight.skipOnVPN                = boo(p, "skipOnVPN",                false)
        }

        if let a = root["auto"] as? [String: Any] {
            c.auto.enabled              = boo(a, "enabled",   true)
            c.auto.minorOnly            = boo(a, "minorOnly", false)
            c.auto.skipBetas            = boo(a, "skipBetas", true)
            c.auto.minorDeadlineDays    = int(a, "minorDeadlineDays", 5)
            c.auto.majorDeadlineDays    = int(a, "majorDeadlineDays", 7)
            c.auto.minorMaxDeferrals    = int(a, "minorMaxDeferrals", 5)
            c.auto.majorMaxDeferrals    = int(a, "majorMaxDeferrals", 7)
            c.auto.adminWebhookURL      = str(a, "adminWebhookURL",   "")
            c.auto.notifyAdminOnDetection       = boo(a, "notifyAdminOnDetection",    false)
            c.auto.notifyOnDeadlineHit          = boo(a, "notifyOnDeadlineHit",        true)
            c.auto.notifyOnDeferralExhausted    = boo(a, "notifyOnDeferralExhausted",  true)
            c.auto.notifyOnInstallComplete      = boo(a, "notifyOnInstallComplete",    true)
            c.auto.autoInstallNonSystemUpdates  = boo(a, "autoInstallNonSystemUpdates", true)
            c.auto.enforceMinimumMajorVersion   = int(a, "enforceMinimumMajorVersion", 0)
        }

        if let s = root["schedule"] as? [String: Any] {
            c.schedule.alertStartHour                 = int(s, "alertStartHour",                8)
            c.schedule.alertEndHour                   = int(s, "alertEndHour",                  18)
            c.schedule.skipWeekends                   = boo(s, "skipWeekends",                  true)
            c.schedule.skipDuringMeetings             = boo(s, "skipDuringMeetings",            true)
            c.schedule.skipOnVPN                      = boo(s, "skipOnVPN",                     false)
            c.schedule.skipInstallDuringScreenShare   = boo(s, "skipInstallDuringScreenShare",  true)
        }

        if let d = root["ddm"] as? [String: Any] {
            c.ddm.enabled = boo(d, "enabled", true)
        }

        if let u = root["uptime"] as? [String: Any] {
            c.uptime.enabled                    = boo(u, "enabled",                    true)
            c.uptime.warningThresholdDays       = int(u, "warningThresholdDays",       14)
            c.uptime.forceThresholdDays         = int(u, "forceThresholdDays",         20)
            c.uptime.maxDeferrals               = int(u, "maxDeferrals",               3)
            c.uptime.promptIntervalDays         = int(u, "promptIntervalDays",         1)
            c.uptime.forceTimerSeconds          = int(u, "forceTimerSeconds",          600)
            c.uptime.skipDuringMeeting          = boo(u, "skipDuringMeeting",          true)
            c.uptime.skipIfOSUpdateImminentDays = int(u, "skipIfOSUpdateImminentDays", 3)
        }

        if let cm = root["compliance"] as? [String: Any] {
            c.compliance.wallpaperEnabled         = boo(cm, "wallpaperEnabled",         false)
            c.compliance.compliantWallpaper       = str(cm, "compliantWallpaper",       c.compliance.compliantWallpaper)
            c.compliance.nonCompliantWallpaper    = str(cm, "nonCompliantWallpaper",    c.compliance.nonCompliantWallpaper)
            c.compliance.wallpaperBackgroundColor = str(cm, "wallpaperBackgroundColor", "020C19")
            c.compliance.wallpaperScale           = str(cm, "wallpaperScale",           "fit")
            c.compliance.desktopprPath            = str(cm, "desktopprPath",            "/usr/local/bin/desktoppr")
            c.compliance.desktopprPkgPath         = str(cm, "desktopprPkgPath",         c.compliance.desktopprPkgPath)
        }

        if let j = root["jamf"] as? [String: Any] {
            c.jamf.url                = str(j, "url",                "")
            c.jamf.eaName             = str(j, "eaName",             "OS Update Compliance")
            c.jamf.binaryPath         = str(j, "binaryPath",         "/usr/local/bin/jamf")
            c.jamf.reportEAAfterCheck = boo(j, "reportEAAfterCheck", true)
            c.jamf.clientId           = str(j, "clientId",           "")
            c.jamf.clientSecret       = str(j, "clientSecret",       "")
            c.jamf.accountName        = str(j, "accountName",        "")
            c.jamf.accountPassword    = str(j, "accountPassword",    "")
            c.jamf.computerId         = str(j, "computerId",         "")
        }

        // Jamf LAPS — read from top-level `laps:` block (parser doesn't support
        // two-level nesting under jamf:).
        if let l = root["laps"] as? [String: Any] {
            c.jamf.laps.enabled      = boo(l, "enabled",      false)
            c.jamf.laps.accountName  = str(l, "accountName",  "")
            c.jamf.laps.clientId     = str(l, "clientId",     "")
            c.jamf.laps.clientSecret = str(l, "clientSecret", "")
        }

        if let a = root["auth"] as? [String: Any] {
            c.auth.localAccount  = str(a, "localAccount",  "")
            c.auth.localPassword = str(a, "localPassword", "")
        }

        if let l = root["logging"] as? [String: Any] {
            c.logging.maxLogSizeMB   = int(l, "maxLogSizeMB",   10)
            c.logging.maxRotatedLogs = int(l, "maxRotatedLogs", 5)
        }

        if let d = root["debug"] as? [String: Any] {
            c.debug.dryRun                   = boo(d, "dryRun",                   false)
            c.debug.testToastIntervalMinutes = int(d, "testToastIntervalMinutes", 0)
            c.debug.testNudgeIntervalMinutes = int(d, "testNudgeIntervalMinutes", 0)
        }

        return c
    }

    // MARK: - Minimal YAML dict parser

    static func parseYAMLDict(_ source: String) -> [String: Any] {
        var root:           [String: Any]           = [:]
        var sections:       [String: [String: Any]] = [:]
        var currentSection: String                  = ""

        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let indent = line.prefix(while: { $0 == " " }).count

            if trimmed.hasSuffix(":") && !trimmed.contains(": ") {
                currentSection = String(trimmed.dropLast())
                if sections[currentSection] == nil { sections[currentSection] = [:] }
                root[currentSection] = sections[currentSection]!
                continue
            }

            guard trimmed.contains(":") else { continue }
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key   = String(parts[0]).trimmingCharacters(in: .whitespaces)
            var value = String(parts[1]).trimmingCharacters(in: .whitespaces)

            if !value.hasPrefix("\"") && !value.hasPrefix("'"),
               let hi = value.firstIndex(of: "#") {
                value = String(value[..<hi]).trimmingCharacters(in: .whitespaces)
            }
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'")  && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }

            let parsed: Any
            if      value == "true"       { parsed = true  }
            else if value == "false"      { parsed = false }
            else if let i = Int(value)    { parsed = i     }
            else if let d = Double(value) { parsed = d     }
            else                          { parsed = value }

            if indent > 0 && !currentSection.isEmpty {
                sections[currentSection, default: [:]][key] = parsed
                root[currentSection] = sections[currentSection]!
            } else if indent == 0 {
                root[key] = parsed
            }
        }
        return root
    }

    // MARK: - Computed helpers

    var isMajor: Bool { update.releaseType == "major" }

    var isPastDeadline: Bool {
        guard !update.deadline.isEmpty else { return false }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate,
                             .withColonSeparatorInTime]
        guard let d = fmt.date(from: update.deadline)
               ?? ISO8601DateFormatter().date(from: update.deadline)
        else { return false }
        return Date() > d
    }

    /// Returns seconds for toast interval (test mode override or real 1h)
    var toastIntervalSeconds: TimeInterval {
        if debug.testToastIntervalMinutes > 0 {
            return TimeInterval(debug.testToastIntervalMinutes * 60)
        }
        return TimeInterval(update.toastIntervalSeconds)
    }

    /// Returns seconds for nudge interval (test mode override or real 24h)
    var nudgeIntervalSeconds: TimeInterval {
        if debug.testNudgeIntervalMinutes > 0 {
            return TimeInterval(debug.testNudgeIntervalMinutes * 60)
        }
        return 24 * 3600
    }
}
