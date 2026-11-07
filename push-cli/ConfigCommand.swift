// ==============================================================================
// PUSH - Proactive Update Scheduling Helper
//
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
//
// Component: ConfigCommand.swift
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
// ==============================================================================

// ConfigCommand.swift — Config inspection and modification

import Foundation
import CoreFoundation

struct ConfigCommand {
    let args: [String]

    func run() {
        guard let sub = args.first else {
            cliError("Usage: push-cli config <show|get|set|validate>")
            exit(1)
        }
        let rest = Array(args.dropFirst())
        switch sub {
        case "show":     showConfig()
        case "get":      getKey(rest)
        case "set":      setKey(rest)
        case "validate": validateConfig()
        default:
            cliError("Unknown config subcommand '\(sub)'")
            exit(1)
        }
    }

    // MARK: - Show

    private func showConfig() {
        guard let path = resolvedConfigPath else {
            cliError("No config found at \(managedBase)/config.yaml")
            exit(1)
        }
        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? "(empty)"
        cliPrint(redactConfigContent(content))
    }

    // MARK: - Get

    private func getKey(_ args: [String]) {
        guard let key = args.first else {
            cliError("Usage: push-cli config get <key>  (e.g. update.targetVersion)")
            exit(1)
        }
        guard let config = try? loadConfig() else {
            cliError("Cannot load config"); exit(1)
        }
        guard let value = getValue(key: key, config: config) else {
            cliError("Unknown key: '\(key)'"); exit(1)
        }
        cliPrint(value)
    }

    private func getValue(key: String, config: CLIConfig) -> String? {
        switch key {
        case "update.targetVersion":               return config.update.targetVersion
        case "update.macOSName":                   return config.update.macOSName
        case "update.releaseType":                 return config.update.releaseType
        case "update.deadline":                    return config.update.deadline
        case "update.maxDeferrals":                return "\(config.update.maxDeferrals)"
        case "update.nudgeIntervalSeconds":        return "\(config.update.nudgeIntervalSeconds)"
        case "update.silentInstallAfterDeadline":  return "\(config.update.silentInstallAfterDeadline)"
        case "update.forceRestartAfterInstall":    return "\(config.update.forceRestartAfterInstall)"
        case "ui.appName":                         return config.ui.appName
        case "ui.orgName":                         return config.ui.orgName
        case "ui.accentColorHex":                  return config.ui.accentColorHex
        case "ui.itContactEmail":                  return config.ui.itContactEmail
        case "ui.itContactPhone":                  return config.ui.itContactPhone
        case "ui.hardBlockFullscreen":             return "\(config.ui.hardBlockFullscreen)"
        case "preflight.powerCheckTimeoutMinutes": return "\(config.preflight.powerCheckTimeoutMinutes)"
        case "preflight.minDiskSpaceGB":           return "\(config.preflight.minDiskSpaceGB)"
        case "entra.enabled": return "\(config.entra.enabled)"
        case "entra.policyID": return config.entra.policyID
        case "entra.startHour": return "\(config.entra.startHour)"
        case "entra.endHour": return "\(config.entra.endHour)"
        case "entra.weekdaysOnly": return "\(config.entra.weekdaysOnly)"
        case "entra.skipMeetings": return "\(config.entra.skipMeetings)"
        case "entra.reconOnRegistration": return "\(config.entra.reconOnRegistration)"
        case "entra.selfServicePath": return config.entra.selfServicePath
        case "entra.companyPortalPath": return config.entra.companyPortalPath
        case "entra.jamfBinaryPath": return config.entra.jamfBinaryPath
        case "entra.message": return config.entra.message
        case "apps.enabled": return "\(config.apps.enabled)"
        case "apps.approved": return config.apps.approved
        case "apps.graceDays": return "\(config.apps.graceDays)"
        case "apps.deadline": return config.apps.deadline
        case "apps.chromeDeadline": return config.apps.chromeDeadline
        case "apps.firefoxDeadline": return config.apps.firefoxDeadline
        case "apps.vscodeDeadline": return config.apps.vscodeDeadline
        case "apps.autoUpdateClosed": return "\(config.apps.autoUpdateClosed)"
        case "apps.notifyHourly": return "\(config.apps.notifyHourly)"
        case "apps.installomatorPath": return config.apps.installomatorPath
        case "auto.trackLatest": return "\(config.auto.trackLatest)"
        case "auto.useMist": return "\(config.auto.useMist)"
        case "update.automaticDeadline": return config.update.automaticDeadline
        case "update.automaticDeadlineTarget": return config.update.automaticDeadlineTarget
        case "update.effectiveDeadline": return config.effectiveDeadline
        case "auto.enabled":                       return "\(config.auto.enabled)"
        case "auto.minorOnly":                     return "\(config.auto.minorOnly)"
        case "auto.minorDeadlineDays":             return "\(config.auto.minorDeadlineDays)"
        case "auto.majorDeadlineDays":             return "\(config.auto.majorDeadlineDays)"
        case "auto.minorMaxDeferrals":             return "\(config.auto.minorMaxDeferrals)"
        case "auto.majorMaxDeferrals":             return "\(config.auto.majorMaxDeferrals)"
        case "auto.adminWebhookURL":               return config.auto.adminWebhookURL
        case "auto.notifyAdminOnDetection":        return "\(config.auto.notifyAdminOnDetection)"
        case "auto.notifyOnDeadlineHit":           return "\(config.auto.notifyOnDeadlineHit)"
        case "auto.notifyOnDeferralExhausted":     return "\(config.auto.notifyOnDeferralExhausted)"
        case "auto.notifyOnInstallComplete":       return "\(config.auto.notifyOnInstallComplete)"
        case "auto.enforceMinimumMajorVersion":    return "\(config.auto.enforceMinimumMajorVersion)"
        case "auto.skipBetas":                     return "\(config.auto.skipBetas)"
        case "jamf.binaryPath":                   return config.jamf.binaryPath
        case "jamf.eaName":                       return config.jamf.eaName
        case "jamf.url":                          return config.jamf.url
        case "jamf.reportEAAfterCheck":           return "\(config.jamf.reportEAAfterCheck)"
        case "jamf.clientId":                     return config.jamf.clientId
        case "jamf.clientSecret":                 return redactedValue(config.jamf.clientSecret)
        case "jamf.accountName":                  return config.jamf.accountName
        case "jamf.accountPassword":              return redactedValue(config.jamf.accountPassword)
        case "jamf.computerId":                   return config.jamf.computerId
        case "auth.localAccount":                 return config.auth.localAccount
        case "auth.localPassword":                return redactedValue(config.auth.localPassword)
        case "preflight.minBatteryPercent":       return "\(config.preflight.minBatteryPercent)"
        case "preflight.checkNetworkReachability":return "\(config.preflight.checkNetworkReachability)"
        case "preflight.skipOnVPN":               return "\(config.preflight.skipOnVPN)"
        case "update.deadlineRecoveryEnabled": return "\(config.update.deadlineRecoveryEnabled)"
        case "update.retryCountdownMinutes": return "\(config.update.retryCountdownMinutes)"
        case "update.retryBackoffMinutes": return "\(config.update.retryBackoffMinutes)"
        case "update.maxAutomaticRetriesPerDay": return "\(config.update.maxAutomaticRetriesPerDay)"
        case "update.allowUserUpdateRequests": return "\(config.update.allowUserUpdateRequests)"
        case "ui.menuBarEnabled": return "\(config.ui.menuBarEnabled)"
        case "compliance.wallpaperEnabled": return "\(config.compliance.wallpaperEnabled)"
        case "compliance.nonCompliantWallpaper": return config.compliance.nonCompliantWallpaper
        case "compliance.compliantWallpaper": return config.compliance.compliantWallpaper
        case "schedule.respectAlertWindow": return "\(config.schedule.respectAlertWindow)"
        case "update.prepareAtDeadlineWhenLoggedOut": return "\(config.update.prepareAtDeadlineWhenLoggedOut)"
        case "schedule.skipDuringMeetings":       return "\(config.schedule.skipDuringMeetings)"
        case "logging.maxLogSizeMB":              return "\(config.logging.maxLogSizeMB)"
        case "logging.maxRotatedLogs":            return "\(config.logging.maxRotatedLogs)"
        case "uptime.enabled":                    return "\(config.uptime.enabled)"
        case "uptime.warningThresholdDays":       return "\(config.uptime.warningThresholdDays)"
        case "uptime.forceThresholdDays":         return "\(config.uptime.forceThresholdDays)"
        case "uptime.maxDeferrals":               return "\(config.uptime.maxDeferrals)"
        case "uptime.promptIntervalDays":         return "\(config.uptime.promptIntervalDays)"
        case "uptime.forceTimerSeconds":          return "\(config.uptime.forceTimerSeconds)"
        case "uptime.skipDuringMeeting":          return "\(config.uptime.skipDuringMeeting)"
        case "schedule.alertStartHour":            return "\(config.schedule.alertStartHour)"
        case "schedule.alertEndHour":              return "\(config.schedule.alertEndHour)"
        case "schedule.skipWeekends":              return "\(config.schedule.skipWeekends)"
        case "debug.dryRun":                       return "\(config.debug.dryRun)"
        case "debug.testToastIntervalMinutes":     return "\(config.debug.testToastIntervalMinutes)"
        case "debug.testNudgeIntervalMinutes":     return "\(config.debug.testNudgeIntervalMinutes)"
        case "schedule.skipDuringMeetings":        return "\(config.schedule.skipDuringMeetings)"
        case "toast.position":                     return config.toast.position
        case "toast.width":                        return "\(config.toast.width)"
        case "toast.showCloseButton":              return "\(config.toast.showCloseButton)"
        case "toast.showDeferButton":              return "\(config.toast.showDeferButton)"
        case "toast.soundName":                    return config.toast.soundName
        case "toast.installButtonLabel":           return config.toast.installButtonLabel
        case "toast.deferButtonLabel":             return config.toast.deferButtonLabel
        case "update.toastIntervalSeconds":        return "\(config.update.toastIntervalSeconds)"
        default: return nil
        }
    }

    // MARK: - Set

    private func setKey(_ args: [String]) {
        guard args.count >= 2 else {
            cliError("Usage: push-cli config set <key> <value>")
            exit(1)
        }
        guard getuid() == 0 else {
            cliError("config set requires root. Run: sudo push-cli config set ..."); exit(1)
        }
        guard let cfgPath = resolvedConfigPath else {
            cliError("No config found"); exit(1)
        }

        let key   = args[0]
        let value = args[1]

        do {
            let source = try String(contentsOfFile:cfgPath,encoding:.utf8)
            let edited = try Self.upsertingConfig(source,key:key,value:value)
            guard (try String(contentsOfFile:cfgPath,encoding:.utf8)) == source else {
                throw CLIError.invalidValue("Configuration changed while editing. Retry with the latest file.")
            }
            let original = URL(fileURLWithPath:cfgPath)
            let attributes = try FileManager.default.attributesOfItem(atPath:cfgPath)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw CLIError.invalidValue("Edit the managed configuration source rather than a linked file.") }
            let backups = original.deletingLastPathComponent().appendingPathComponent("config-backups")
            if FileManager.default.fileExists(atPath:backups.path) {
                let info = try FileManager.default.attributesOfItem(atPath:backups.path)
                guard info[.type] as? FileAttributeType == .typeDirectory, (info[.ownerAccountID] as? NSNumber)?.intValue == 0,
                      ((info[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o022 == 0 else { throw CLIError.invalidValue("Configuration backup folder is not protected.") }
            } else { try FileManager.default.createDirectory(at:backups,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]) }
            let backup = backups.appendingPathComponent(original.lastPathComponent + "." + UUID().uuidString + ".bak")
            guard FileManager.default.createFile(atPath:backup.path,contents:Data(source.utf8),attributes:[.posixPermissions:0o600]) else { throw CLIError.invalidValue("Could not back up the existing configuration.") }
            let staged = original.deletingLastPathComponent().appendingPathComponent(".push-config-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at:staged) }
            guard FileManager.default.createFile(atPath:staged.path,contents:Data(edited.utf8),attributes:[.posixPermissions:0o600]) else { throw CLIError.invalidValue("Could not stage the configuration change.") }
            var retained: [FileAttributeKey:Any] = [:]
            for key in [FileAttributeKey.posixPermissions,.ownerAccountID,.groupOwnerAccountID] { retained[key] = attributes[key] }
            try FileManager.default.setAttributes(retained,ofItemAtPath:staged.path)
            guard (try String(contentsOfFile:cfgPath,encoding:.utf8)) == source else { throw CLIError.invalidValue("Configuration changed; retry the edit.") }
            guard rename(staged.path,cfgPath) == 0 else { throw CLIError.invalidValue("Could not commit the configuration change.") }
            let loggedValue = isSensitiveConfigKey(key) ? redactedValue(value) : value
            cliSuccess("Set \(key) = \(loggedValue)")
            cliInfo("Previous config backup:",backup.path)
        } catch { cliError("Configuration was not updated: \(error.localizedDescription)"); exit(1) }
    }

    /// A missing supported field is an upsert, including in an older installed YAML.
    static func upsertingConfig(_ source: String, key: String, value: String) throws -> String {
        let parts = key.split(separator:".",omittingEmptySubsequences:false).map(String.init)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } }) else { throw CLIError.invalidKey(key) }
        let schema = try JSONSerialization.jsonObject(with:JSONEncoder().encode(CLIConfig())) as! [String:Any]
        let fields: [String:Any]?
        if parts[0] == "laps" { fields = (schema["jamf"] as? [String:Any])?["laps"] as? [String:Any] }
        else { fields = schema[parts[0]] as? [String:Any] }
        guard let sample = fields?[parts[1]] else { throw CLIError.invalidKey(key) }
        let encoded: String
        if sample is String {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
            encoded = String(decoding:try encoder.encode(value),as:UTF8.self)
        } else if let number = sample as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                guard ["true","false"].contains(value) else { throw CLIError.invalidValue("\(key) requires true or false") }
                encoded = value
            } else {
                guard let integer = Int(value) else { throw CLIError.invalidValue("\(key) requires an integer") }
                encoded = String(integer)
            }
        } else { throw CLIError.invalidValue("\(key) is not a scalar setting") }
        guard !source.trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("{"), !source.contains("\t") else { throw CLIError.invalidValue("Use PUSH block YAML with spaces before editing this configuration") }
        var headers = 0
        for line in source.components(separatedBy:"\n") where !line.hasPrefix(" ") {
            let text = line.components(separatedBy:"#")[0].trimmingCharacters(in:.whitespaces)
            if text.hasPrefix(parts[0] + ":") {
                guard text == parts[0] + ":" else { throw CLIError.invalidValue("\(parts[0]) must be a block YAML section") }
                headers += 1
            }
        }
        guard headers <= 1 else { throw CLIError.invalidValue("Merge duplicate \(parts[0]) sections before editing") }
        let result = updatingYAMLScalar(source,section:[parts[0]],field:parts[1],encoded:encoded)
        let parsed = CLIConfig.parse(yaml:result)
        if parts[0] == "entra", !EntraNudgeCommand.valid(parsed.entra) { throw CLIError.invalidValue("Invalid Entra policy settings") }
        return result
    }

    // MARK: - Validate

    private func validateConfig() {
        guard let config = try? loadConfig() else {
            cliError("Cannot load config — check YAML syntax at \(resolvedConfigPath ?? managedBase + "/config.yaml")")
            exit(1)
        }

        var issues: [String] = []

        if !EntraNudgeCommand.valid(config.entra) { issues.append("Invalid Entra registration policy ID, app paths, message, or working hours") }
        let approved = AppUpdatePolicy.ids(config.apps.approved)
        if !approved.allSatisfy({ id in ApprovedApp.catalog.contains { $0.id == id } }) || (config.apps.enabled && approved.isEmpty) { issues.append("apps.approved must contain supported, explicitly approved app IDs") }
        for id in approved {
            let deadline = config.apps.deadlineOverride(for:id)
            if !deadline.isEmpty && ISO8601DateFormatter().date(from:deadline) == nil { issues.append("Invalid app deadline for " + id) }
        }
        if !(1...365).contains(config.apps.graceDays) { issues.append("apps.graceDays must be between 1 and 365") }
        if config.update.targetVersion.isEmpty && !config.auto.trackLatest {
            issues.append("update.targetVersion is not set — run: sudo push-cli auto-check")
        }
        if !config.update.deadline.isEmpty && ISO8601DateFormatter().date(from: config.update.deadline) == nil {
            issues.append("update.deadline must be an ISO 8601 timestamp with time zone")
        }
        if !(1...365).contains(config.auto.minorDeadlineDays) || !(1...365).contains(config.auto.majorDeadlineDays) {
            issues.append("Automatic deadline days must be between 1 and 365")
        }
        if !config.update.targetVersion.isEmpty && !isValidVersion(config.update.targetVersion) {
            issues.append("update.targetVersion '\(config.update.targetVersion)' is not a valid version")
        }
        if config.update.maxDeferrals < 0 {
            issues.append("update.maxDeferrals must be >= 0")
        }
        if config.preflight.minDiskSpaceGB < 15 {
            issues.append("preflight.minDiskSpaceGB should be at least 15 GB")
        }
        if config.schedule.alertStartHour >= config.schedule.alertEndHour {
            issues.append("schedule.alertStartHour must be less than alertEndHour")
        }
        let uiPath = resolveUIBinary()
        if !FileManager.default.fileExists(atPath: uiPath) {
            issues.append("push-ui not found at \(uiPath)")
        }

        if issues.isEmpty {
            cliSuccess("Config is valid")
            cliInfo("Target:", config.update.targetVersion.isEmpty ? "(not set)" : config.update.targetVersion)
            cliInfo("Deadline:", config.update.deadline.isEmpty ? "(auto)" : config.update.deadline)
        } else {
            cliWarning("Config has \(issues.count) issue\(issues.count == 1 ? "" : "s"):")
            for issue in issues { cliPrint("  • \(issue)") }
            exit(1)
        }
    }
}

private func isSensitiveConfigKey(_ key: String) -> Bool {
    let lowered = key.lowercased()
    return lowered.contains("password")
        || lowered.contains("secret")
        || lowered.contains("token")
}

private func redactedValue(_ value: String) -> String {
    value.isEmpty ? "" : "(redacted)"
}

private func redactConfigContent(_ content: String) -> String {
    let sensitiveFields = ["clientSecret", "accountPassword", "localPassword"]
    return content.components(separatedBy: "\n").map { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"),
              let field = sensitiveFields.first(where: { trimmed.hasPrefix("\($0):") }),
              let colon = line.firstIndex(of: ":")
        else { return line }

        let currentValue = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !currentValue.isEmpty, currentValue != "\"\"" else { return line }
        let prefix = line[..<line.range(of: field)!.lowerBound]
        return "\(prefix)\(field): \"(redacted)\""
    }.joined(separator: "\n")
}
