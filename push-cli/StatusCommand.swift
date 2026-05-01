// StatusCommand.swift — Compliance status, check, and reset

import Foundation

// MARK: - Status

struct StatusCommand {
    let args: [String]

    func run() {
        let current  = currentMacOSVersion()
        let state    = loadState()
        let config   = try? loadConfig()
        let target   = config?.update.targetVersion ?? ""
        let maxDef   = config?.update.maxDeferrals ?? 3
        let compliant = target.isEmpty ? true : versionGTE(current, target)

        cliSection("PUSH v\(cliVersion) — Compliance Status")
        cliDivider()
        cliInfo("Current macOS:", current)
        cliInfo("Target macOS:",  target.isEmpty ? "(not set)" : target)
        cliInfo("Status:", compliant
            ? "\u{001B}[32mCOMPLIANT ✓\u{001B}[0m"
            : "\u{001B}[31mNON-COMPLIANT ✗\u{001B}[0m")

        cliSection("Deferrals")
        cliDivider()
        cliInfo("Used:",              "\(state.deferralCount) / \(maxDef)")
        cliInfo("Last seen target:",  state.lastSeenVersion.isEmpty ? "(none)" : state.lastSeenVersion)
        cliInfo("Next toast:",        describeDate(state.nextToastDate))
        cliInfo("Next nudge:",        describeDate(state.nextNudgeDate))
        cliInfo("Install started:",   state.installStarted   ? "Yes" : "No")
        cliInfo("Install completed:", state.installCompleted ? "Yes" : "No")

        if let c = config {
            cliSection("Config")
            cliDivider()
            cliInfo("Release type:",    c.update.releaseType)
            cliInfo("Deadline:",        c.update.deadline.isEmpty ? "(none)" : c.update.deadline)
            cliInfo("Past deadline:",   c.isPastDeadline ? "\u{001B}[31mYES\u{001B}[0m" : "No")
            cliInfo("Toast interval:",  "\(formatInterval(Int(c.toastIntervalSeconds))) (every \(c.update.toastIntervalSeconds)s)")
            cliInfo("Nudge interval:",  "\(formatInterval(Int(c.nudgeIntervalSeconds))) (every \(c.update.nudgeIntervalSeconds)s)")
            cliInfo("Hard block mode:", c.ui.hardBlockFullscreen ? "Fullscreen lockout" : "Standard popup")
            cliInfo("Auto install after deadline:", c.update.autoInstallAfterDeadline ? "✅ Enabled — forces install when deadline passes" : "Disabled — hard block only")
            cliInfo("Alert window:",    "\(c.schedule.alertStartHour):00–\(c.schedule.alertEndHour):00\(c.schedule.skipWeekends ? " (weekdays only)" : "")")
            cliInfo("Skip meetings:",    c.schedule.skipDuringMeetings ? "Yes" : "No")
            cliInfo("DDM detection:",   c.ddm.enabled ? "Enabled" : "Disabled")
            cliInfo("Auto-check:",      c.auto.enabled ? "Enabled" : "Disabled")
            if c.debug.dryRun {
                cliInfo("Dry run:", "\u{001B}[33mYES — disable before deploying\u{001B}[0m")
            }
            if c.debug.testToastIntervalMinutes > 0 {
                cliInfo("Test toast interval:", "\(c.debug.testToastIntervalMinutes) minutes")
            }
            if c.debug.testNudgeIntervalMinutes > 0 {
                cliInfo("Test nudge interval:", "\(c.debug.testNudgeIntervalMinutes) minutes")
            }
        }

        // Daemon status
        cliSection("Daemon")
        cliDivider()
        let plistPath = "/Library/LaunchDaemons/com.push.autoupdate.plist"
        if FileManager.default.fileExists(atPath: plistPath) {
            // Read StartInterval from the plist
            if let plistData = FileManager.default.contents(atPath: plistPath),
               let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
               let interval = plist["StartInterval"] as? Int {
                cliInfo("Status:", "✅ Installed")
                cliInfo("Interval:", formatInterval(interval) + " (every \(interval)s)")
            } else {
                cliInfo("Status:", "✅ Installed")
            }
            // Check if actually running
            let (runOut, _) = shell("launchctl print system/com.push.autoupdate 2>/dev/null | grep state")
            let running = runOut.lowercased().contains("running")
            cliInfo("Running:", running ? "Yes" : "Waiting for next interval")
        } else {
            cliInfo("Status:", "❌ Not installed — run: sudo push-cli install-daemon")
        }

        // Auth credentials
        cliSection("Auth")
        cliDivider()
        if let cfg = config {
            let account = cfg.auth.localAccount
            cliInfo("Account:", account.isEmpty ? "(not set — uses console user)" : account)
            cliInfo("Keychain:", keychainPasswordExists() ? "✅ Password stored" : "(not set — will prompt user)")
            if !cfg.auth.localPassword.isEmpty {
                cliWarning("Plain text password in config.yaml — migrate: sudo push-cli auth set-password")
            }

            // Apple Silicon auth status
            if isAppleSilicon() {
                let authMethod = selectAuthMethod(config: cfg)
                cliInfo("Auth method:", authMethod.rawValue)
                let btEscrowed = isBootstrapTokenEscrowed()
                cliInfo("Bootstrap Token:", btEscrowed ? "✅ Escrowed to MDM" : "⚠️  Not escrowed — password required")
                let stEnabled = consoleUserHasSecureToken()
                cliInfo("Secure Token:", stEnabled ? "✅ Enabled for console user" : "⚠️  Not enabled — install may fail")
            }
        }

        cliSection("Files")
        cliDivider()
        let cfgPath    = resolvedConfigPath ?? "(not found)"
        let stateFound = FileManager.default.fileExists(atPath: statePath)
        let logFound   = FileManager.default.fileExists(atPath: logPath)
        cliInfo("Config:", cfgPath)
        cliInfo("State:",  stateFound ? statePath : "(not found)")
        cliInfo("Log:",    logFound   ? logPath   : "(not found)")
        cliPrint("")
    }

    /// Human-friendly relative date string. Rounds to nearest unit instead of
    /// truncating like RelativeDateTimeFormatter, so 1h 51m reads as "in 2 hours"
    /// not "in 1 hour".
    private func describeDate(_ date: Date) -> String {
        if date <= Date() || date == .distantPast { return "Now (due)" }
        let interval = date.timeIntervalSince(Date())

        // Round up to nearest unit so we don't undersell time remaining.
        let mins  = Int(interval / 60.0)
        let hours = Int((interval / 3600.0).rounded())
        let days  = Int((interval / 86400.0).rounded())

        if interval < 60 {
            return "in less than a minute"
        } else if interval < 3600 {
            return "in \(mins) minute\(mins == 1 ? "" : "s")"
        } else if interval < 86400 {
            return "in \(hours) hour\(hours == 1 ? "" : "s")"
        } else if days < 30 {
            return "in \(days) day\(days == 1 ? "" : "s")"
        } else {
            // Far future — fall back to formatter for "in X months" etc.
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
    }
}

// MARK: - Check (silent exit code)

struct CheckCommand {
    let args: [String]

    func run() {
        guard let config = try? loadConfig() else {
            cliError("Cannot load config"); exit(2)
        }
        let current   = currentMacOSVersion()
        let target    = config.update.targetVersion
        let compliant = target.isEmpty ? true : versionGTE(current, target)
        cliPrint(compliant ? "compliant" : "non-compliant (running \(current), target \(target))")
        exit(compliant ? 0 : 1)
    }
}

// MARK: - Reset

struct ResetCommand {
    let args: [String]
    var deferralsOnly: Bool { args.contains("--deferrals-only") }
    var installOnly:   Bool { args.contains("--install") }

    func run() {
        guard getuid() == 0 else {
            cliError("Reset requires root. Run: sudo push-cli reset"); exit(1)
        }

        var state = loadState()
        let prev  = state.deferralCount

        // Clear install flags only — no python3 needed, no Xcode CLT required
        if installOnly {
            state.installStarted   = false
            state.installCompleted = false
            try? saveState(state)
            cliSuccess("Install state cleared (installStarted=false, installCompleted=false)")
            return
        }

        if deferralsOnly {
            state.deferralCount = 0
            state.nextAlertDate = .distantPast
            state.nextNudgeDate = .distantPast
            state.nextToastDate = .distantPast
        } else {
            let ver = state.lastSeenVersion
            state = CLIDeferralState()
            state.lastSeenVersion = ver
            if !ver.isEmpty { DetectionLog.remove(version: ver) }
        }

        do {
            try saveState(state)
            cliSuccess("Deferrals reset (\(prev) → 0)")
            if !deferralsOnly { cliSuccess("All state cleared") }
            cliLog("[Reset] Deferrals reset (was \(prev))")
        } catch {
            cliError("Failed to save state: \(error.localizedDescription)"); exit(1)
        }
    }
}
