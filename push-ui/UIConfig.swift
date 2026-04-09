// UIConfig.swift — White-label config model for PUSH
// Everything comes from config.yaml — nothing hardcoded.

import Foundation
import SwiftUI

struct UIConfig {

    // MARK: - Config sections

    var update:    UpdateCfg    = .init()
    var ui:        UICfg        = .init()
    var toast:     ToastCfg     = .init()
    var preflight: PreflightCfg = .init()
    var debug:     DebugCfg     = .init()

    struct UpdateCfg {
        var targetVersion:        String = ""
        var macOSName:            String = "macOS"
        var releaseType:          String = "minor"
        var deadline:             String = ""
        var maxDeferrals:         Int    = 3
        var nudgeIntervalSeconds: Int    = 3600
    }

    struct UICfg {
        var appName:                 String = "Software Update Required"
        var orgName:                 String = ""
        var accentColorHex:          String = "#0A84FF"
        var logoPath:                String = ""
        var sfSymbolName:            String = ""
        var popupWidth:              Int    = 540
        var itContactEmail:          String = ""
        var itContactPhone:          String = ""
        var helpURL:                 String = ""
        // Rich text supported: \n = newline, \n\n = paragraph break, - item = bullet
        var minorMessage:            String = "A required macOS security update is available. Please install it at your earliest convenience."
        var majorMessage:            String = "A major macOS upgrade is required. Please save your work and begin the upgrade today."
        var deadlineMessage:         String = "Your Mac must be updated immediately. Save your work and click Install Now to begin."
        var downloadingMessage:      String = "Downloading the macOS update in the background. Please keep your Mac plugged in."
        var installingMessage:       String = "Installation in progress. This takes 45–60 minutes. Please keep your Mac powered on."
        var alreadyUpToDateMessage:  String = "Your Mac is running the required version of macOS. No action needed."
        var passwordPromptMessage:   String = "Your Mac requires your password to install the update."
        var preflightPowerMessage:   String = "Please connect your Mac to power before installing the update."
        var installMinorButtonLabel: String = "Install Now"
        var installMajorButtonLabel: String = "Begin Upgrade"
        var deferButtonLabel:        String = "Remind Me Later"
        // When true, user must pick a reason before deferring
        var requireDeferralReason:   Bool   = false
        var deferralReasons:         [String] = [
            "I am busy right now",
            "I am in a meeting",
            "I am traveling",
            "I need IT support",
            "Other"
        ]
        // When true, hardBlock covers all displays with a frosted blur overlay.
        // User cannot interact with any app until they click Install Now.
        var hardBlockFullscreen:     Bool   = false
    }

    struct ToastCfg {
        var position:           String = "topRight"
        var width:              Int    = 420
        var screenMargin:       Int    = 16
        var cornerRadius:       Int    = 16
        var autoDismissSeconds: Int?   = nil   // nil = no auto-dismiss
        var showCloseButton:    Bool   = true
        var showDeferButton:    Bool   = true
        // macOS system sound name played when toast appears.
        // Options: Funk, Basso, Blow, Bottle, Frog, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink
        // Set to "" to disable sound.
        var soundName:          String = "Funk"
        var installButtonLabel: String = "Install Now"
        var deferButtonLabel:   String = "Later"
        var message:            String? = nil
    }

    struct PreflightCfg {
        var powerCheckTimeoutMinutes: Int    = 5
        var minDiskSpaceGB:           Int    = 25
        var diskSpaceLearnMoreURL:    String = ""
    }

    struct DebugCfg {
        var dryRun:                   Bool = false
        var testToastIntervalMinutes: Int  = 0
        var testNudgeIntervalMinutes: Int  = 0
    }

    // MARK: - Computed helpers

    var accentColor: Color {
        Color(hex: ui.accentColorHex) ?? Color(red: 0.039, green: 0.518, blue: 1.0)
    }

    var isMajor: Bool { update.releaseType == "major" }

    var currentVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion == 0
            ? "\(v.majorVersion).\(v.minorVersion)"
            : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    var friendlyTargetVersion: String {
        let name = update.macOSName.isEmpty ? "macOS" : update.macOSName
        return update.targetVersion.isEmpty ? name : "\(name) \(update.targetVersion)"
    }

    var deadlineDate: Date? {
        guard !update.deadline.isEmpty else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate,
                             .withColonSeparatorInTime]
        return fmt.date(from: update.deadline)
            ?? ISO8601DateFormatter().date(from: update.deadline)
    }

    var isPastDeadline: Bool {
        guard let d = deadlineDate else { return false }
        return Date() > d
    }

    // MARK: - Load

    static func load(from path: String) -> UIConfig {
        guard let data   = FileManager.default.contents(atPath: path),
              let source = String(data: data, encoding: .utf8)
        else { return UIConfig() }
        return parse(yaml: source)
    }

    // MARK: - YAML parser

    private static func parse(yaml source: String) -> UIConfig {
        var cfg = UIConfig()

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
            cfg.update.targetVersion        = str(u, "targetVersion")
            cfg.update.macOSName            = str(u, "macOSName", "macOS")
            cfg.update.releaseType          = str(u, "releaseType", "minor")
            cfg.update.deadline             = str(u, "deadline")
            cfg.update.maxDeferrals         = int(u, "maxDeferrals", 3)
            cfg.update.nudgeIntervalSeconds = int(u, "nudgeIntervalSeconds", 3600)
        }

        if let u = root["ui"] as? [String: Any] {
            cfg.ui.appName                  = str(u, "appName",  cfg.ui.appName)
            cfg.ui.orgName                  = str(u, "orgName",  "")
            cfg.ui.accentColorHex           = str(u, "accentColorHex", "#0A84FF")
            cfg.ui.logoPath                 = str(u, "logoPath", "")
            cfg.ui.sfSymbolName             = str(u, "sfSymbolName", "")
            cfg.ui.popupWidth               = int(u, "popupWidth", 500)
            cfg.ui.itContactEmail           = str(u, "itContactEmail", "")
            cfg.ui.itContactPhone           = str(u, "itContactPhone", "")
            cfg.ui.helpURL                  = str(u, "helpURL", "")
            cfg.ui.minorMessage             = str(u, "minorMessage",            cfg.ui.minorMessage)
            cfg.ui.majorMessage             = str(u, "majorMessage",            cfg.ui.majorMessage)
            cfg.ui.deadlineMessage          = str(u, "deadlineMessage",         cfg.ui.deadlineMessage)
            cfg.ui.downloadingMessage       = str(u, "downloadingMessage",      cfg.ui.downloadingMessage)
            cfg.ui.installingMessage        = str(u, "installingMessage",       cfg.ui.installingMessage)
            cfg.ui.alreadyUpToDateMessage   = str(u, "alreadyUpToDateMessage",  cfg.ui.alreadyUpToDateMessage)
            cfg.ui.passwordPromptMessage    = str(u, "passwordPromptMessage",   cfg.ui.passwordPromptMessage)
            cfg.ui.preflightPowerMessage    = str(u, "preflightPowerMessage",   cfg.ui.preflightPowerMessage)
            cfg.ui.installMinorButtonLabel  = str(u, "installMinorButtonLabel", cfg.ui.installMinorButtonLabel)
            cfg.ui.installMajorButtonLabel  = str(u, "installMajorButtonLabel", cfg.ui.installMajorButtonLabel)
            cfg.ui.deferButtonLabel         = str(u, "deferButtonLabel",        cfg.ui.deferButtonLabel)
            cfg.ui.requireDeferralReason    = boo(u, "requireDeferralReason",   false)
            cfg.ui.hardBlockFullscreen      = boo(u, "hardBlockFullscreen",     false)
        }

        if let t = root["toast"] as? [String: Any] {
            cfg.toast.position           = str(t,  "position",           "topRight")
            cfg.toast.width              = int(t,  "width",              360)
            cfg.toast.screenMargin       = int(t,  "screenMargin",       16)
            cfg.toast.cornerRadius       = int(t,  "cornerRadius",       16)
            cfg.toast.showCloseButton    = boo(t,  "showCloseButton",    true)
            cfg.toast.showDeferButton    = boo(t,  "showDeferButton",    true)
            cfg.toast.soundName          = str(t,  "soundName",          "Funk")
            cfg.toast.installButtonLabel = str(t,  "installButtonLabel", "Install Now")
            cfg.toast.deferButtonLabel   = str(t,  "deferButtonLabel",   "Later")
            if let n = t["autoDismissSeconds"] as? NSNumber { cfg.toast.autoDismissSeconds = n.intValue }
            if let m = t["message"] as? String, !m.isEmpty  { cfg.toast.message = m }
        }

        if let p = root["preflight"] as? [String: Any] {
            cfg.preflight.powerCheckTimeoutMinutes = int(p, "powerCheckTimeoutMinutes", 5)
            cfg.preflight.minDiskSpaceGB           = int(p, "minDiskSpaceGB",           25)
            cfg.preflight.diskSpaceLearnMoreURL    = str(p, "diskSpaceLearnMoreURL",    "")
        }

        if let d = root["debug"] as? [String: Any] {
            cfg.debug.dryRun                   = boo(d, "dryRun",                   false)
            cfg.debug.testToastIntervalMinutes = int(d, "testToastIntervalMinutes", 0)
            cfg.debug.testNudgeIntervalMinutes = int(d, "testNudgeIntervalMinutes", 0)
        }

        return cfg
    }

    private static func parseYAMLDict(_ source: String) -> [String: Any] {
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
}

// MARK: - Color from hex

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >>  8) & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }
}

// MARK: - String helpers

extension String {
    /// Converts escaped \n sequences to real newlines for display.
    var resolvedNewlines: String {
        replacingOccurrences(of: "\\n", with: "\n")
    }
}

// MARK: - Preview config

extension UIConfig {
    static func preview(major: Bool = false) -> UIConfig {
        var cfg = UIConfig()
        cfg.update.targetVersion        = major ? "26.0" : "15.7.5"
        cfg.update.macOSName            = major ? "macOS Tahoe" : "macOS Sequoia"
        cfg.update.releaseType          = major ? "major" : "minor"
        cfg.update.maxDeferrals         = 3
        cfg.update.deadline             = ISO8601DateFormatter()
            .string(from: Date().addingTimeInterval(5 * 86400))
        cfg.ui.appName                  = "PUSH — Software Update"
        cfg.ui.orgName                  = "Your Organization"
        cfg.ui.itContactEmail           = "it@yourorg.com"
        cfg.ui.itContactPhone           = "1-512-555-0100"
        cfg.ui.accentColorHex           = "#0A84FF"
        cfg.ui.minorMessage             = "A required macOS security update is available.\n\nThis update includes:\n- Critical security patches\n- Performance improvements\n- Bug fixes for Safari and Mail"
        cfg.preflight.powerCheckTimeoutMinutes = 5
        return cfg
    }
}
