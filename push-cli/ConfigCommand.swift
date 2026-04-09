// ConfigCommand.swift — Config inspection and modification

import Foundation

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
        cliPrint(content)
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
        case "jamf.clientSecret":                 return config.jamf.clientSecret
        case "jamf.accountName":                  return config.jamf.accountName
        case "jamf.accountPassword":              return config.jamf.accountPassword
        case "jamf.computerId":                   return config.jamf.computerId
        case "auth.localAccount":                 return config.auth.localAccount
        case "auth.localPassword":                return config.auth.localPassword
        case "preflight.minBatteryPercent":       return "\(config.preflight.minBatteryPercent)"
        case "preflight.checkNetworkReachability":return "\(config.preflight.checkNetworkReachability)"
        case "preflight.skipOnVPN":               return "\(config.preflight.skipOnVPN)"
        case "schedule.skipDuringMeetings":       return "\(config.schedule.skipDuringMeetings)"
        case "logging.maxLogSizeMB":              return "\(config.logging.maxLogSizeMB)"
        case "logging.maxRotatedLogs":            return "\(config.logging.maxRotatedLogs)"
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

        // Read file, update the matching line
        guard var yaml = try? String(contentsOfFile: cfgPath, encoding: .utf8) else {
            cliError("Cannot read config"); exit(1)
        }

        // Map key to YAML field name (last component)
        let field   = key.split(separator: ".").last.map(String.init) ?? key
        let pattern = "^(\\s*\(NSRegularExpression.escapedPattern(for: field)):).*$"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            cliError("Cannot build regex for key '\(key)'"); exit(1)
        }

        let range   = NSRange(yaml.startIndex..., in: yaml)
        let matches = regex.numberOfMatches(in: yaml, range: range)

        guard matches > 0 else {
            cliError("Key '\(key)' not found in config. Add it manually first."); exit(1)
        }

        // Format value: strings get quotes, booleans/integers don't
        let formatted: String
        if value == "true" || value == "false" || Int(value) != nil || Double(value) != nil {
            formatted = value
        } else {
            formatted = "\"\(value)\""
        }

        yaml = regex.stringByReplacingMatches(in: yaml, range: range,
                                               withTemplate: "$1 \(formatted)")
        do {
            try yaml.write(toFile: cfgPath, atomically: true, encoding: .utf8)
            cliSuccess("Set \(key) = \(formatted)")
            cliLog("[Config] Set \(key) = \(formatted)")
        } catch {
            cliError("Failed to write config: \(error.localizedDescription)"); exit(1)
        }
    }

    // MARK: - Validate

    private func validateConfig() {
        guard let config = try? loadConfig() else {
            cliError("Cannot load config — check YAML syntax at \(resolvedConfigPath ?? managedBase + "/config.yaml")")
            exit(1)
        }

        var issues: [String] = []

        if config.update.targetVersion.isEmpty {
            issues.append("update.targetVersion is not set — run: sudo push-cli auto-check")
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
