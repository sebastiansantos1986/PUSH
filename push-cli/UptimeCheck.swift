// UptimeCheck.swift — Reboot reminder and enforcement based on Mac uptime.
//
// Long uptimes accumulate kernel issues, leaked memory, broken Bluetooth/Wi-Fi
// state, and prevent some security updates from applying cleanly. This module
// tracks how long the Mac has been running and prompts the user to restart.
//
// Two phases:
//   Warning (warningThresholdDays ≤ uptime < forceThresholdDays)
//     — Friendly popup with [Later] and [Restart Now]
//     — User can defer up to maxDeferrals times
//
//   Force (uptime ≥ forceThresholdDays OR deferrals exhausted)
//     — Countdown popup with only [Restart Now]
//     — Auto-restart when timer reaches zero
//
// Detection: sysctl kern.boottime gives the boot timestamp. We track the boot
// timestamp in state.json so we can detect when the user actually rebooted
// (timestamp changed) and reset the deferral counter.

import Foundation

struct UptimeCheck {
    let config: CLIConfig

    enum Decision {
        case quiet                              // below warning threshold or skip conditions met
        case showWarning(uptimeDays: Int, deferralsRemaining: Int)
        case showForce(uptimeDays: Int, timerSeconds: Int)
    }

    /// Single entry point — call from auto-check. Returns what (if anything)
    /// the UI should display about uptime, and updates state if needed.
    func evaluate() -> Decision {
        guard config.uptime.enabled else { return .quiet }

        let uptimeSec = currentUptimeSeconds()
        let uptimeDays = Int(uptimeSec / 86400)

        // Below warning threshold — say nothing
        if uptimeDays < config.uptime.warningThresholdDays {
            // But still update boot timestamp so we detect future reboots
            updateBootTimestampIfChanged()
            return .quiet
        }

        // Reset deferral counter if the user actually rebooted since last check.
        let rebooted = updateBootTimestampIfChanged()
        if rebooted {
            cliLog("[Uptime] Reboot detected — resetting uptime deferral counter")
            var state = loadState()
            state.uptimeDeferralCount  = 0
            state.uptimeNextPromptDate = .distantPast
            try? saveState(state)
            return .quiet
        }

        // Skip if the user is in a meeting (only for force phase; warning is non-disruptive)
        let inForcePhase = uptimeDays >= config.uptime.forceThresholdDays
                        || loadState().uptimeDeferralCount >= config.uptime.maxDeferrals

        if inForcePhase && config.uptime.skipDuringMeeting {
            // Tap into AutoCheck's existing meeting detection by re-running its
            // public-style helpers (we can't call the instance method from here,
            // so duplicate the lightweight checks).
            if isUserInMeetingSimple() {
                cliLog("[Uptime] Force phase reached but user is in a meeting — deferring")
                return .quiet
            }
        }

        // Skip if an OS update is pending. Any non-empty target version means
        // we know about an update that hasn't been installed yet — the user
        // will reboot when that lands, so prompting for a separate restart
        // would be wasted noise.
        if !config.update.targetVersion.isEmpty {
            let current = currentMacOSVersion()
            if current != config.update.targetVersion {
                cliLog("[Uptime] OS update pending (\(current) → \(config.update.targetVersion)) — skipping uptime prompt")
                return .quiet
            }
        }

        // Force phase wins over warning phase
        if inForcePhase {
            cliLog("[Uptime] Force phase: uptime=\(uptimeDays)d, deferrals=\(loadState().uptimeDeferralCount)/\(config.uptime.maxDeferrals)")
            return .showForce(uptimeDays: uptimeDays,
                              timerSeconds: config.uptime.forceTimerSeconds)
        }

        // Warning phase — only show if it's time to re-prompt
        let state = loadState()
        if state.uptimeNextPromptDate > Date() {
            return .quiet
        }

        cliLog("[Uptime] Warning phase: uptime=\(uptimeDays)d, deferrals=\(state.uptimeDeferralCount)/\(config.uptime.maxDeferrals)")
        let remaining = max(0, config.uptime.maxDeferrals - state.uptimeDeferralCount)
        return .showWarning(uptimeDays: uptimeDays, deferralsRemaining: remaining)
    }

    /// Record that the user clicked "Later" on the warning popup.
    /// Increments deferral count and pushes next prompt out one day.
    static func recordDeferral(config: CLIConfig) {
        var state = loadState()
        state.uptimeDeferralCount += 1
        state.uptimeNextPromptDate = Date()
            .addingTimeInterval(Double(config.uptime.promptIntervalDays) * 86400)
        try? saveState(state)
        cliLog("[Uptime] User deferred reboot — count=\(state.uptimeDeferralCount)/\(config.uptime.maxDeferrals), next prompt: \(state.uptimeNextPromptDate)")
    }

    /// Trigger the actual restart. Uses the soft AppleScript path so the OS
    /// politely closes apps. A user with unsaved work in non-cooperating apps
    /// might still get a "Save?" dialog, which is the right behavior — we
    /// don't want to lose user data even at force-restart time.
    static func performRestart() {
        cliLog("[Uptime] Initiating restart")
        // Prefer AppleScript-style restart so apps get a chance to close cleanly.
        // Fall back to shutdown -r if osascript isn't available for some reason.
        let (_, st) = shell("/usr/bin/osascript -e 'tell application \"System Events\" to restart' 2>&1")
        if st != 0 {
            cliLog("[Uptime] osascript restart failed — falling back to shutdown -r now")
            _ = shell("/sbin/shutdown -r now")
        }
    }

    // MARK: - Internals

    private func currentUptimeSeconds() -> Double {
        return Self.currentUptimeSeconds()
    }

    static func currentUptimeSeconds() -> Double {
        let (out, _) = shell("/usr/sbin/sysctl -n kern.boottime 2>/dev/null")
        // Output looks like: { sec = 1717168919, usec = 235814 } Mon May 31 ...
        let scanner = Scanner(string: out)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ={,sec\nMonueWdThurFiSatJanFebMrApyJlguOoNDc0123456789:")
        // Simpler: regex out the first integer after "sec ="
        if let range = out.range(of: #"sec\s*=\s*(\d+)"#, options: .regularExpression) {
            let match = String(out[range])
            if let secStr = match.split(separator: "=").last?.trimmingCharacters(in: .whitespaces),
               let secVal = Double(secStr) {
                let bootTime = secVal
                let now = Date().timeIntervalSince1970
                return now - bootTime
            }
        }
        return 0
    }

    /// Returns true if the boot timestamp differs from what we last saved.
    /// (Meaning: user actually rebooted between auto-check runs.)
    @discardableResult
    private func updateBootTimestampIfChanged() -> Bool {
        let (out, _) = shell("/usr/sbin/sysctl -n kern.boottime 2>/dev/null")
        guard let range = out.range(of: #"sec\s*=\s*(\d+)"#, options: .regularExpression) else {
            return false
        }
        let match = String(out[range])
        guard let secStr = match.split(separator: "=").last?.trimmingCharacters(in: .whitespaces),
              let currentBoot = Double(secStr)
        else { return false }

        var state = loadState()
        let lastBoot = state.uptimeLastBootTimestamp
        // First-time write — no comparison possible
        if lastBoot == 0 {
            state.uptimeLastBootTimestamp = currentBoot
            try? saveState(state)
            return false
        }
        // Boot time changed = real reboot happened
        if abs(currentBoot - lastBoot) > 1 {
            state.uptimeLastBootTimestamp = currentBoot
            try? saveState(state)
            return true
        }
        return false
    }

    /// Lightweight meeting detection — same logic as AutoCheck.isUserInMeeting()
    /// but inlined so we don't have a circular dependency.
    private func isUserInMeetingSimple() -> Bool {
        let (screenshared, _) = shell("pgrep -x screensharingd 2>/dev/null")
        if !screenshared.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        let (mic, _) = shell("ioreg -r -c IOAudioEngine -d 4 2>/dev/null | grep -iE 'input.*running|capturing'")
        return !mic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Reboot CLI

struct RebootCommand {
    let args: [String]

    private var subcommand: String { args.first ?? "status" }
    private var rest: [String] { args.isEmpty ? [] : Array(args.dropFirst()) }

    func run() {
        switch subcommand {
        case "status": status()
        case "check": check()
        case "nudge": showNudge()
        case "force": showForce()
        case "defer": recordDeferral()
        case "reset": resetState()
        case "now": restartNow()
        case "help", "--help", "-h": printHelp()
        default:
            cliError("Unknown reboot subcommand '\(subcommand)'")
            printHelp()
            exit(1)
        }
    }

    private func printHelp() {
        cliPrint("""
Usage: push-cli reboot <status|check|nudge|force|defer|reset|now>

  reboot status                 Show uptime/reboot policy and current state
  reboot check                  Evaluate policy and print quiet/warning/force
  reboot nudge                  Show restart reminder popup now
  reboot force                  Show forced restart countdown popup now
    --timer 300                 Override countdown seconds for this run
  reboot defer                  Record one reboot deferral
  reboot reset                  Clear reboot deferrals and prompt schedule
  reboot now --confirm          Restart this Mac now

Config can be controlled with:
  sudo push-cli config set uptime.enabled true
  sudo push-cli config set uptime.warningThresholdDays 14
  sudo push-cli config set uptime.forceThresholdDays 20
  sudo push-cli config set uptime.maxDeferrals 3
  sudo push-cli config set uptime.promptIntervalDays 1
  sudo push-cli config set uptime.forceTimerSeconds 600
""")
    }

    private func status() {
        guard let config = try? loadConfig() else {
            cliError("Cannot load config"); exit(1)
        }
        let uptimeSeconds = UptimeCheck.currentUptimeSeconds()
        let uptimeDays = Int(uptimeSeconds / 86400)
        let state = loadState()
        let remaining = max(0, config.uptime.maxDeferrals - state.uptimeDeferralCount)

        cliSection("🔄 Reboot Policy")
        cliDivider()
        cliInfo("Enabled:", config.uptime.enabled ? "Yes" : "No")
        cliInfo("Current uptime:", "\(uptimeDays) days")
        cliInfo("Warning threshold:", "\(config.uptime.warningThresholdDays) days")
        cliInfo("Force threshold:", "\(config.uptime.forceThresholdDays) days")
        cliInfo("Deferrals:", "\(state.uptimeDeferralCount) / \(config.uptime.maxDeferrals)")
        cliInfo("Remaining deferrals:", "\(remaining)")
        cliInfo("Next prompt:", formatDateForCLI(state.uptimeNextPromptDate))
        cliInfo("Force timer:", "\(config.uptime.forceTimerSeconds) seconds")
        cliInfo("Skip during meeting:", config.uptime.skipDuringMeeting ? "Yes" : "No")
        cliInfo("Last boot stamp:", state.uptimeLastBootTimestamp == 0 ? "(not recorded)" : "\(Int(state.uptimeLastBootTimestamp))")
    }

    private func check() {
        guard let config = try? loadConfig() else {
            cliError("Cannot load config"); exit(2)
        }

        switch UptimeCheck(config: config).evaluate() {
        case .quiet:
            cliPrint("quiet")
            exit(0)
        case .showWarning(let days, let remaining):
            cliPrint("warning: uptime=\(days)d, deferralsRemaining=\(remaining)")
            exit(1)
        case .showForce(let days, let timer):
            cliPrint("force: uptime=\(days)d, timer=\(timer)s")
            exit(2)
        }
    }

    private func showNudge() {
        guard let config = try? loadConfig() else {
            cliError("Cannot load config"); exit(1)
        }
        let days = overrideDays() ?? Int(UptimeCheck.currentUptimeSeconds() / 86400)
        let remaining = overrideRemaining(config: config)
        let status = runRebootPopup(state: "rebootNudge",
                                    args: ["--uptime-days", "\(days)",
                                           "--deferrals-remaining", "\(remaining)"])

        switch Int(status) {
        case 0:
            cliSuccess("User chose Restart Now")
            if rest.contains("--restart") {
                UptimeCheck.performRestart()
            } else {
                cliPrint("Restart not triggered. Add --restart if you want this command to restart after user approval.")
            }
        case 1:
            UptimeCheck.recordDeferral(config: config)
            cliSuccess("Restart deferred")
        default:
            cliPrint("Popup exited with code \(status)")
        }
    }

    private func showForce() {
        guard let config = try? loadConfig() else {
            cliError("Cannot load config"); exit(1)
        }
        let days = overrideDays() ?? Int(UptimeCheck.currentUptimeSeconds() / 86400)
        let timer = Int(argValue("--timer", in: rest) ?? "") ?? config.uptime.forceTimerSeconds
        let status = runRebootPopup(state: "rebootForce",
                                    args: ["--uptime-days", "\(days)",
                                           "--timer-seconds", "\(timer)"])
        cliLog("[Reboot] Force popup exited with code \(status)")
        if rest.contains("--restart") {
            UptimeCheck.performRestart()
        } else {
            cliSuccess("Force popup completed")
            cliPrint("Restart not triggered. Add --restart if you want this command to restart after the countdown.")
        }
    }

    private func recordDeferral() {
        guard let config = try? loadConfig() else {
            cliError("Cannot load config"); exit(1)
        }
        UptimeCheck.recordDeferral(config: config)
        cliSuccess("Recorded reboot deferral")
    }

    private func resetState() {
        guard getuid() == 0 else {
            cliError("reboot reset requires root. Run: sudo push-cli reboot reset"); exit(1)
        }
        var state = loadState()
        state.uptimeDeferralCount = 0
        state.uptimeNextPromptDate = .distantPast
        state.uptimeLastBootTimestamp = 0
        do {
            try saveState(state)
            cliSuccess("Reboot state reset")
            cliLog("[Reboot] Uptime reboot state reset")
        } catch {
            cliError("Failed to save state: \(error.localizedDescription)")
            exit(1)
        }
    }

    private func restartNow() {
        guard getuid() == 0 else {
            cliError("reboot now requires root. Run: sudo push-cli reboot now --confirm"); exit(1)
        }
        guard rest.contains("--confirm") else {
            cliError("Refusing to restart without confirmation. Run: sudo push-cli reboot now --confirm")
            exit(1)
        }
        UptimeCheck.performRestart()
    }

    private func runRebootPopup(state: String, args popupArgs: [String]) -> Int32 {
        guard let user = consoleUser() else {
            cliError("No console user is logged in; cannot show reboot popup.")
            exit(1)
        }
        guard let cfgPath = resolvedConfigPath else {
            cliError("No config found at \(managedBase)/config.yaml")
            exit(1)
        }
        let uiPath = resolveUIBinary()
        guard FileManager.default.fileExists(atPath: uiPath) else {
            cliError("push-ui not found at \(uiPath)")
            exit(1)
        }

        shell("pkill -x push-ui 2>/dev/null || true")
        Thread.sleep(forTimeInterval: 0.3)
        let extra = popupArgs.joined(separator: " ")
        let cmd = "launchctl asuser \(user.uid) sudo -u \"\(user.name)\" \"\(uiPath)\" --state \(state) --config \"\(cfgPath)\" \(extra)"
        return runUIBlocking(cmd)
    }

    private func overrideDays() -> Int? {
        Int(argValue("--days", in: rest) ?? "")
    }

    private func overrideRemaining(config: CLIConfig) -> Int {
        if let val = Int(argValue("--remaining", in: rest) ?? "") { return val }
        let state = loadState()
        return max(0, config.uptime.maxDeferrals - state.uptimeDeferralCount)
    }

    private func formatDateForCLI(_ date: Date) -> String {
        if date == .distantPast { return "Now (due)" }
        if date == .distantFuture { return "Never" }
        return ISO8601DateFormatter().string(from: date)
    }
}
