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
