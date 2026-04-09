// AutoCheckCommand.swift — Update detection and nudge scheduling
//
// Schedule:
//   First detection  → softNudge immediately
//   Every hour       → toast (never counts deferral)
//   Every 24h        → softNudge or hardBlock (Later = +1 deferral)
//
// Alert window: schedule.alertStartHour–alertEndHour, skips weekends if configured.
// Test overrides: debug.testToastIntervalMinutes / testNudgeIntervalMinutes

import Foundation

struct AutoCheckCommand {
    let args: [String]
    var isDryRun: Bool { args.contains("--dry-run") }
    var isForced: Bool { args.contains("--force") }

    struct DetectedUpdate {
        let version: String
        let name:    String
        let isMajor: Bool
        let isBeta:  Bool
    }

    func run() {
        cliLog("[AutoCheck] Starting (dry-run:\(isDryRun) force:\(isForced))")

        // Rotate log if needed
        if let cfg = try? loadConfig() {
            LogRotation.rotateIfNeeded(config: cfg)
        }

        guard let config = try? loadConfig() else {
            cliError("Cannot load config. Run: push-cli config show")
            exit(1)
        }

        guard config.auto.enabled else {
            cliPrint("Auto-detection disabled (auto.enabled: false).")
            exit(0)
        }

        // Guard: if no user is logged in and targetVersion is already set,
        // skip entirely — cannot show UI and no detection needed
        if !userIsLoggedIn() && !config.update.targetVersion.isEmpty {
            cliLog("[AutoCheck] No console user — skipping nudge schedule (install started: \(loadState().installStarted))")
            // Still run silent install if past deadline and configured
            if config.isPastDeadline && config.update.silentInstallAfterDeadline {
                cliLog("[AutoCheck] Silent install triggered (no user, past deadline)")
                InstallWorkflow(config: config, skipInitialPrompt: true).run()
            }
            exit(0)
        }

        // Alert window check — skip outside business hours / weekends
        if !isDryRun && !isForced && !isWithinAlertWindow(config: config) {
            cliLog("[AutoCheck] Outside alert window — skipping nudge")
            cliPrint("Outside alert window (\(config.schedule.alertStartHour):00–\(config.schedule.alertEndHour):00). Will retry next run.")
            exit(0)
        }

        let current = currentMacOSVersion()
        cliSection("🔍 Checking for macOS updates")
        cliInfo("Current macOS:", current)
        cliInfo("Config target:", config.update.targetVersion.isEmpty ? "(not set)" : config.update.targetVersion)

        // Step aside if DDM is managing this
        if config.ddm.enabled, let ddmVer = detectDDMVersion() {
            cliInfo("DDM detected:", ddmVer)
            cliPrint("Apple DDM is managing this update. PUSH will step aside.")
            cliLog("[AutoCheck] DDM active for \(ddmVer) — exiting")
            exit(0)
        }

        // ── Enforcement logic ──────────────────────────────────────────────────
        // If enforceMinimumMajorVersion is set (e.g. 26), check the current
        // machine's major version against it. This handles two scenarios:
        //
        //   Machine on 15.x → needs major upgrade to 26 → releaseType = major
        //   Machine on 26.x → may need a minor security update → releaseType = minor
        //
        // This means you set one config and PUSH does the right thing on every Mac.

        let currentMajorInt = Int(current.split(separator: ".").first ?? "0") ?? 0
        let enforcedMajor   = config.auto.enforceMinimumMajorVersion

        // Already compliant check
        if !config.update.targetVersion.isEmpty &&
            versionGTE(current, config.update.targetVersion) {
            // Also verify major version enforcement
            if enforcedMajor > 0 && currentMajorInt < enforcedMajor {
                cliInfo("Major version enforcement:", "Running \(current) but need major \(enforcedMajor).x")
                // Fall through to detection below
            } else {
                cliSuccess("Already compliant — running \(current), target \(config.update.targetVersion)")
                cliLog("[AutoCheck] Already compliant")

                // If install was previously started (pre-reboot state), this is the
                // first run after a successful upgrade. Mark complete + run recon.
                var state = loadState()
                if state.installStarted && !state.installCompleted {
                    state.installCompleted = true
                    state.installStarted   = false
                    try? saveState(state)
                    cliLog("[AutoCheck] Post-upgrade first run — marking install complete")
                    NotificationManager(config: config).notifyInstallComplete(
                        version: current,
                        previousVersion: state.lastSeenVersion
                    )
                    // Trigger recon so Jamf EA updates immediately instead of waiting
                    if !config.jamf.binaryPath.isEmpty,
                       FileManager.default.fileExists(atPath: config.jamf.binaryPath) {
                        cliLog("[AutoCheck] Running jamf recon post-upgrade")
                        shell("\"\(config.jamf.binaryPath)\" recon 2>/dev/null")
                        cliSuccess("Jamf inventory updated")
                    }
                }
                exit(0)
            }
        }

        // Poll softwareupdate
        cliPrint("\nPolling Apple Software Update…")
        let available = detectAvailableUpdates(config: config)

        // If enforceMinimumMajorVersion is set and the machine is below that major,
        // synthesize a major upgrade target even if softwareupdate doesn't list it yet.
        if enforcedMajor > 0 && currentMajorInt < enforcedMajor {
            cliInfo("Enforcement:", "Machine on \(current) — major upgrade to \(enforcedMajor).x required")
            // If softwareupdate found the major upgrade, use it.
            // Otherwise use the manually configured targetVersion.
            let majorCandidate = available.first(where: {
                (Int($0.version.split(separator: ".").first ?? "0") ?? 0) >= enforcedMajor
            })
            if let candidate = majorCandidate {
                cliInfo("Major upgrade found:", "\(candidate.name) \(candidate.version)")
                handleDetectedUpdate(candidate, config: config, current: current)
            } else if !config.update.targetVersion.isEmpty {
                cliInfo("Using configured target:", config.update.targetVersion)
                runNudgeSchedule(config: config)
            } else {
                cliWarning("enforceMinimumMajorVersion = \(enforcedMajor) but macOS \(enforcedMajor) not yet available via softwareupdate.")
                cliPrint("Set update.targetVersion manually when the upgrade becomes available.")
            }
            exit(0)
        }

        if available.isEmpty {
            if !config.update.targetVersion.isEmpty {
                cliLog("[AutoCheck] No new update found but targetVersion set — running nudge schedule")
                runNudgeSchedule(config: config)
            } else {
                cliSuccess("No updates found. \(current) is current.")
                cliLog("[AutoCheck] No updates found")
            }
            exit(0)
        }

        guard let best = pickBestUpdate(from: available, config: config, current: current) else {
            cliPrint("Updates found but all filtered (beta/minorOnly).")
            exit(0)
        }

        cliInfo("Update found:", "\(best.name) \(best.version)")
        cliInfo("Release type:", best.isMajor ? "Major upgrade" : "Minor update")

        if DetectionLog.firstSeen(version: best.version) == nil {
            DetectionLog.record(version: best.version, date: Date())
        }

        handleDetectedUpdate(best, config: config, current: current)
    }

    private func handleDetectedUpdate(_ best: DetectedUpdate, config: CLIConfig, current: String) {
        // isNewVersion is ONLY true when the version actually changed.
        // --force overrides the schedule (fires nudge regardless of window/timing)
        // but should NOT reset the deferral/toast schedule if version is unchanged.
        let versionChanged = config.update.targetVersion != best.version
        let isNewVersion   = versionChanged

        if isNewVersion {
            // ── New version: configure and show first softNudge ──
            let deadlineDays = best.isMajor ? config.auto.majorDeadlineDays : config.auto.minorDeadlineDays
            let maxDeferrals = best.isMajor ? config.auto.majorMaxDeferrals : config.auto.minorMaxDeferrals
            let firstSeen    = DetectionLog.firstSeen(version: best.version) ?? Date()
            let deadline     = Calendar.current.date(byAdding: .day, value: deadlineDays, to: firstSeen) ?? Date()
            let deadlineStr  = ISO8601DateFormatter().string(from: deadline)
            let daysLeft     = Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0

            cliSection("📝 Configuring")
            cliInfo("Target version:", best.version)
            cliInfo("Release type:",  best.isMajor ? "major" : "minor")
            cliInfo("Deadline:",      "\(deadlineStr) (\(daysLeft) days)")
            cliInfo("Max deferrals:", "\(maxDeferrals)")

            if isDryRun {
                cliWarning("DRY RUN — nothing written.")
                exit(0)
            }

            guard getuid() == 0 else {
                cliError("Writing config requires root. Run: sudo push-cli auto-check")
                exit(1)
            }

            guard var cfg = try? loadConfig(), let cfgPath = resolvedConfigPath else {
                cliError("Cannot load config for update."); exit(1)
            }

            let prevVersion = cfg.update.targetVersion
            cfg.update.targetVersion = best.version
            cfg.update.macOSName     = best.name
            cfg.update.releaseType   = best.isMajor ? "major" : "minor"
            cfg.update.deadline      = deadlineStr
            cfg.update.maxDeferrals  = maxDeferrals

            guard let yamlData = cfg.toYAML().data(using: .utf8) else {
                cliError("Failed to generate YAML"); exit(1)
            }
            do {
                try yamlData.write(to: URL(fileURLWithPath: cfgPath), options: .atomic)
                cliSuccess("Config updated")
            } catch {
                cliError("Failed to write config: \(error.localizedDescription)"); exit(1)
            }

            // Reset deferrals for new version
            if prevVersion != best.version {
                var state = loadState()
                state.deferralCount    = 0
                state.nextNudgeDate    = .distantPast   // fire immediately on first detection
                state.nextToastDate    = Date.distantFuture  // set properly after nudge closes
                state.lastSeenVersion  = best.version
                state.installStarted   = false
                state.installCompleted = false
                try? saveState(state)
                cliSuccess("Deferrals reset for \(best.version)")
            }

            if config.auto.notifyAdminOnDetection && !config.auto.adminWebhookURL.isEmpty {
                sendWebhook(config: cfg, update: best, deadline: deadlineStr)
            }

            cliSection("✅ Done")
            cliPrint("Showing initial softNudge…")

            // Lock nextNudgeDate BEFORE showing so concurrent runs don't also fire
            var lockState = loadState()
            lockState.nextNudgeDate = Date().addingTimeInterval(cfg.nudgeIntervalSeconds)
            lockState.nextToastDate = Date.distantFuture
            try? saveState(lockState)

            showNudge(config: cfg)

            // After nudge closes, set toast to +1h from now
            var s = loadState()
            s.nextToastDate = Date().addingTimeInterval(cfg.toastIntervalSeconds)
            try? saveState(s)
            cliLog("[AutoCheck] Initial nudge done. Toast in \(formatInterval(Int(cfg.toastIntervalSeconds))), next nudge in \(formatInterval(Int(cfg.nudgeIntervalSeconds)))")

        } else {
            // ── Already configured: run nudge schedule ──
            // If --force, bypass alert window/meeting checks and fire nudge directly
            if isForced {
                cliLog("[AutoCheck] --force with same version — running nudge schedule (force mode)")
                showNudge(config: config)
            } else {
                runNudgeSchedule(config: config)
            }
        }
    }

    // MARK: - Nudge schedule

    private func runNudgeSchedule(config: CLIConfig) {
        let state = loadState()

        cliLog("[AutoCheck] Checking schedule — nextNudge: \(state.nextNudgeDate), nextToast: \(state.nextToastDate)")

        // Silent install: if deadline has passed AND the config flag is set,
        // skip all UI and go straight to install. This was configured but never
        // triggered — the check was missing entirely.
        if config.isPastDeadline && config.update.silentInstallAfterDeadline {
            cliLog("[AutoCheck] Deadline passed + silentInstallAfterDeadline=true — starting silent install")
            cliPrint("Deadline passed. Running silent install (no UI prompt).")
            InstallWorkflow(config: config, skipInitialPrompt: true).run()
            return
        }

        if state.nextNudgeDate <= Date() {
            // Lock nextNudgeDate to tomorrow BEFORE showing the nudge.
            // This prevents concurrent daemon runs from also firing the nudge
            // while this run is blocking on the popup.
            var lockState = loadState()
            lockState.nextNudgeDate = Date().addingTimeInterval(config.nudgeIntervalSeconds)
            lockState.nextToastDate = Date.distantFuture // will be set after nudge closes
            try? saveState(lockState)
            cliLog("[AutoCheck] Daily nudge due — locked nextNudge to tomorrow")

            showNudge(config: config)

            // After nudge closes, set toast to fire 1 hour from now
            var s = loadState()
            s.nextToastDate = Date().addingTimeInterval(config.toastIntervalSeconds)
            try? saveState(s)
            cliLog("[AutoCheck] Toast reset to fire in \(formatInterval(Int(config.toastIntervalSeconds)))")
        } else if state.nextToastDate <= Date() {
            cliLog("[AutoCheck] Hourly toast due")
            showToast(config: config)
        } else {
            let nextEvent = min(state.nextNudgeDate, state.nextToastDate)
            let label     = state.nextToastDate < state.nextNudgeDate ? "toast" : "nudge"
            cliSuccess("Nothing due. Next \(label): \(RelativeDateTimeFormatter().localizedString(for: nextEvent, relativeTo: Date()))")
        }
    }

    // MARK: - Show toast (never counts deferral)

    private func showToast(config: CLIConfig) {
        // Skip if user is in a meeting or presenting (configurable)
        if config.schedule.skipDuringMeetings && isUserInMeeting() {
            cliLog("[AutoCheck] Meeting/presentation detected — skipping toast, will retry next run")
            cliPrint("Skipped: user appears to be in a meeting.")
            return
        }

        let uiPath = resolveUIBinary()
        guard FileManager.default.fileExists(atPath: uiPath) else {
            cliLog("[AutoCheck] push-ui not found — skipping toast"); return
        }
        guard let cfgPath = resolvedConfigPath else { return }

        let state = loadState()
        shell("pkill -x push-ui 2>/dev/null || true")
        Thread.sleep(forTimeInterval: 0.4)

        // Toast is non-blocking — fire and forget
        launchUIAsUser("\"\(uiPath)\" --state toast --config \"\(cfgPath)\" --deferrals \(state.deferralCount)")

        // Toast NEVER counts a deferral — just update next toast date.
        // If user dismisses without acting, retry in 30 min instead of full interval
        // so they don't wait a full hour after accidentally closing it.
        var s = loadState()
        s.nextToastDate = Date().addingTimeInterval(config.toastIntervalSeconds)
        try? saveState(s)
        cliLog("[AutoCheck] Toast launched. Next toast in \(formatInterval(Int(config.toastIntervalSeconds)))")

        // Poll briefly to see if user clicked Install — toast is non-blocking
        // If they did, the install command exits with 0 and we pick it up here
        Thread.sleep(forTimeInterval: 2.0)
        let exitFile = "/tmp/push-toast-action"
        if let action = try? String(contentsOfFile: exitFile, encoding: .utf8) {
            try? FileManager.default.removeItem(atPath: exitFile)
            if action.trimmingCharacters(in: .whitespaces) == "install" {
                cliLog("[AutoCheck] User clicked Install from toast — starting install workflow")
                InstallWorkflow(config: config, skipInitialPrompt: true).run()
            }
        }

        // If user clicks Install Now from toast, handle it via a temp file
        // check on next run — toast is non-blocking so we can't wait here
    }

    // MARK: - Show softNudge or hardBlock (Later counts deferral)

    private func showNudge(config: CLIConfig) {
        // Skip if no user is logged in — cannot show UI at login window.
        // Log clearly so IT knows why the nudge was skipped.
        guard userIsLoggedIn() else {
            cliLog("[AutoCheck] No console user logged in — skipping nudge, will retry next run")
            cliPrint("No user logged in. Will retry when a user is at the console.")
            return
        }

        // Skip if user is in a meeting — but NOT if deadline has passed and
        // no deferrals remain (hardBlock still fires in that case)
        let state0        = loadState()
        let noDeferrals0  = state0.deferralCount >= config.update.maxDeferrals
        let isHardBlock   = config.isPastDeadline || noDeferrals0

        if !isHardBlock && config.schedule.skipDuringMeetings && isUserInMeeting() {
            cliLog("[AutoCheck] Meeting/presentation detected — skipping nudge, will retry next run")
            cliPrint("Skipped: user appears to be in a meeting.")
            return
        }

        let uiPath = resolveUIBinary()
        guard FileManager.default.fileExists(atPath: uiPath) else {
            cliLog("[AutoCheck] push-ui not found — skipping nudge"); return
        }
        guard let cfgPath = resolvedConfigPath else { return }

        var state = loadState()
        shell("pkill -x push-ui 2>/dev/null || true")
        Thread.sleep(forTimeInterval: 0.4)

        let noDeferrals = state.deferralCount >= config.update.maxDeferrals
        let uiState     = (config.isPastDeadline || noDeferrals) ? "hardBlock" : "softNudge"

        cliLog("[AutoCheck] Showing \(uiState) (deferrals: \(state.deferralCount)/\(config.update.maxDeferrals), pastDeadline: \(config.isPastDeadline))")

        let status = runUIBlocking("\"\(uiPath)\" --state \(uiState) --config \"\(cfgPath)\" --deferrals \(state.deferralCount)")

        // Always push next nudge date forward
        state.nextNudgeDate = Date().addingTimeInterval(config.nudgeIntervalSeconds)

        let notifier = NotificationManager(config: config)

        switch Int(status) {
        case 0:
            // User clicked Install Now
            cliLog("[AutoCheck] User accepted — starting install workflow")
            try? saveState(state)
            // skipInitialPrompt=true because user already confirmed in this nudge popup
            InstallWorkflow(config: config, skipInitialPrompt: true).run()
            return
        case 1:
            // User clicked Later — ONLY action that costs a deferral
            state.deferralCount += 1

            // Capture deferral reason if user provided one
            let reasonFile = "/tmp/push-deferral-reason"
            if let reason = try? String(contentsOfFile: reasonFile, encoding: .utf8),
               !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.deferralReasons.append(reason.trimmingCharacters(in: .whitespacesAndNewlines))
                try? FileManager.default.removeItem(atPath: reasonFile)
                cliLog("[AutoCheck] Deferral reason: \(reason)")
            }

            cliLog("[AutoCheck] Deferred — count \(state.deferralCount)/\(config.update.maxDeferrals)")
            cliPrint("Deferral recorded (\(state.deferralCount)/\(config.update.maxDeferrals)). Next nudge in \(formatInterval(Int(config.nudgeIntervalSeconds)))")

            // Notify if deferrals just exhausted
            if state.deferralCount >= config.update.maxDeferrals {
                notifier.notifyDeferralsExhausted(version: config.update.targetVersion,
                                                   deferrals: state.deferralCount)
            }
        default:
            // Dismiss (X/ESC) — no deferral cost
            cliLog("[AutoCheck] Dismissed (exit \(status)) — no deferral counted")
        }

        // Notify if deadline just passed
        if config.isPastDeadline && state.deadlineNotifiedAt == nil {
            notifier.notifyDeadlineHit(version: config.update.targetVersion)
            state.deadlineNotifiedAt = Date()
        }

        // Jamf EA report
        let current = currentMacOSVersion()
        notifier.reportJamfEA(
            compliant:  versionGTE(current, config.update.targetVersion),
            current:    current,
            target:     config.update.targetVersion,
            deferrals:  state.deferralCount
        )

        try? saveState(state)
    }

    // MARK: - Alert window

    private func isWithinAlertWindow(config: CLIConfig) -> Bool {
        let cal     = Calendar.current
        let now     = Date()
        let hour    = cal.component(.hour,    from: now)
        let weekday = cal.component(.weekday, from: now)

        if config.schedule.skipWeekends && (weekday == 1 || weekday == 7) {
            return false
        }

        // Use schedule.skipOnVPN — suppresses nudge/toast popups on VPN.
        // preflight.skipOnVPN is a separate flag that blocks downloads/installs
        // and must not be conflated with the alert-window decision.
        if config.schedule.skipOnVPN && PreflightChecks(config: config).isOnVPN() {
            cliLog("[AutoCheck] VPN detected and schedule.skipOnVPN: true — skipping alert window")
            return false
        }

        return hour >= config.schedule.alertStartHour &&
               hour <  config.schedule.alertEndHour
    }

    // MARK: - Update detection

    private func detectAvailableUpdates(config: CLIConfig) -> [DetectedUpdate] {
        // Step 1: Check mdmclient for MDM-pushed updates
        let (mdmOut, _) = shell("/usr/libexec/mdmclient AvailableOSUpdates 2>/dev/null")
        if !mdmOut.trimmingCharacters(in: .whitespaces).isEmpty {
            cliLog("[AutoCheck] mdmclient output:\n\(mdmOut)")
        }

        // Step 2: softwareupdate --list (primary source)
        let (swuOut, _) = shell("/usr/sbin/softwareupdate --list 2>&1")
        var updates = parseUpdates(output: swuOut, config: config)

        // Step 3: SOFA feed for zero-day release date awareness (non-blocking)
        fetchSOFAFeed()

        return updates
    }

    private func fetchSOFAFeed() {
        let sofaPath = "/tmp/push-sofa-macos-feed.json"
        let etagPath = "/tmp/push-sofa-etag.txt"
        // Non-blocking fire-and-forget — used for future release date awareness
        let etagArg = FileManager.default.fileExists(atPath: etagPath) ? "--etag-save \"\(etagPath)\"" : "--etag-save \"\(etagPath)\""
        shell("curl -s --max-time 10 --location \"https://sofafeed.macadmins.io/v1/macos_data_feed.json\" \(etagArg) --output \"\(sofaPath)\" 2>/dev/null &")
        cliLog("[AutoCheck] SOFA feed check dispatched")
    }

    private func parseUpdates(output: String, config: CLIConfig) -> [DetectedUpdate] {
        var updates: [DetectedUpdate] = []
        let current      = currentMacOSVersion()
        let currentMajor = Int(current.split(separator: ".").first ?? "0") ?? 0
        let lines        = output.components(separatedBy: "\n")

        for line in lines {
            guard line.contains("Title:") && line.contains("Version:") else { continue }
            let title   = field("Title",   from: line)
            let version = field("Version", from: line)
            guard !version.isEmpty, isValidVersion(version),
                  !versionGTE(current, version) else { continue }

            let targetMajor = Int(version.split(separator: ".").first ?? "0") ?? 0
            let isMajor     = targetMajor != currentMajor
            let isBeta      = line.lowercased().contains("beta") || line.lowercased().contains("rc")
            let name        = cleanName(title: title, version: version)
            updates.append(DetectedUpdate(version: version, name: name,
                                          isMajor: isMajor, isBeta: isBeta))
        }

        // Fallback: scan bare version patterns
        if updates.isEmpty {
            let vReg = try? NSRegularExpression(pattern: #"\b(\d{1,3}\.\d+(?:\.\d+)?)\b"#)
            let nReg = try? NSRegularExpression(pattern: #"macOS\s+([A-Za-z]+)"#)
            for line in lines {
                guard line.contains("macOS") else { continue }
                let range = NSRange(line.startIndex..., in: line)
                guard let vm = vReg?.firstMatch(in: line, range: range),
                      let vr = Range(vm.range(at: 1), in: line) else { continue }
                let version = String(line[vr])
                guard isValidVersion(version), !versionGTE(current, version) else { continue }
                let tMajor = Int(version.split(separator: ".").first ?? "0") ?? 0
                var name = "macOS"
                if let nm = nReg?.firstMatch(in: line, range: range),
                   let nr = Range(nm.range(at: 1), in: line) {
                    name = "macOS \(String(line[nr]))"
                }
                updates.append(DetectedUpdate(version: version, name: name,
                                              isMajor: tMajor != currentMajor, isBeta: false))
            }
        }
        return updates
    }

    private func field(_ name: String, from line: String) -> String {
        guard let r = line.range(of: "\(name): ") else { return "" }
        return String(line[r.upperBound...]).components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func cleanName(title: String, version: String) -> String {
        let stripped = title.replacingOccurrences(of: version, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? "macOS" : stripped
    }

    private func pickBestUpdate(from updates: [DetectedUpdate],
                                config: CLIConfig, current: String) -> DetectedUpdate? {
        updates
            .filter { u in
                !(config.auto.skipBetas && u.isBeta)
                && !config.auto.skipVersions.contains(u.version)
                && !(config.auto.minorOnly && u.isMajor)
            }
            .sorted { !versionGTE($0.version, $1.version) }
            .last
    }

    private func detectDDMVersion() -> String? {
        let path = "/Library/Updates/declarative/softwareupdate.plist"
        guard FileManager.default.fileExists(atPath: path),
              let data  = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(
                              from: data, format: nil) as? [String: Any],
              let ver   = plist["TargetOSVersion"] as? String
        else { return nil }
        return ver
    }

    private func sendWebhook(config: CLIConfig, update: DetectedUpdate, deadline: String) {
        guard let url = URL(string: config.auto.adminWebhookURL) else { return }
        let type = update.isMajor ? "Major Upgrade" : "Minor Update"
        let body = try? JSONSerialization.data(withJSONObject: [
            "text": "🔔 *PUSH Auto-Detection*\n*Host:* \(ProcessInfo.processInfo.hostName)\n*Update:* \(update.name) \(update.version) (\(type))\n*Deadline:* \(deadline)"
        ])
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let sema = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _,_,_ in sema.signal() }.resume()
        sema.wait()
    }
}

// MARK: - CLIConfig YAML serializer (minimal, only fields we need to update)

extension CLIConfig {
    func toYAML() -> String {
        // Read the existing file and update only the changed values
        // to preserve comments and formatting
        guard let cfgPath = resolvedConfigPath,
              var yaml = try? String(contentsOfFile: cfgPath, encoding: .utf8)
        else {
            return generateMinimalYAML()
        }

        func setField(_ key: String, _ value: String, in yaml: inout String) {
            let pattern = "^(\\s*\(NSRegularExpression.escapedPattern(for: key)):).*$"
            guard let regex = try? NSRegularExpression(pattern: pattern,
                                                        options: .anchorsMatchLines)
            else { return }
            let range = NSRange(yaml.startIndex..., in: yaml)
            yaml = regex.stringByReplacingMatches(in: yaml, range: range,
                                                   withTemplate: "$1 \(value)")
        }

        setField("targetVersion", "\"\(update.targetVersion)\"", in: &yaml)
        setField("macOSName",     "\"\(update.macOSName)\"",     in: &yaml)
        setField("releaseType",   "\"\(update.releaseType)\"",   in: &yaml)
        setField("deadline",      "\"\(update.deadline)\"",      in: &yaml)
        setField("maxDeferrals",  "\(update.maxDeferrals)",      in: &yaml)

        return yaml
    }

    private func generateMinimalYAML() -> String {
        """
update:
  targetVersion: "\(update.targetVersion)"
  macOSName: "\(update.macOSName)"
  releaseType: "\(update.releaseType)"
  deadline: "\(update.deadline)"
  maxDeferrals: \(update.maxDeferrals)
  nudgeIntervalSeconds: \(update.nudgeIntervalSeconds)
ui:
  appName: "\(ui.appName)"
  orgName: "\(ui.orgName)"
  accentColorHex: "\(ui.accentColorHex)"
  itContactEmail: "\(ui.itContactEmail)"
  itContactPhone: "\(ui.itContactPhone)"
  hardBlockFullscreen: \(ui.hardBlockFullscreen)
auto:
  enabled: \(auto.enabled)
  minorOnly: \(auto.minorOnly)
  minorDeadlineDays: \(auto.minorDeadlineDays)
  majorDeadlineDays: \(auto.majorDeadlineDays)
schedule:
  alertStartHour: \(schedule.alertStartHour)
  alertEndHour: \(schedule.alertEndHour)
  skipWeekends: \(schedule.skipWeekends)
debug:
  dryRun: \(debug.dryRun)
  testToastIntervalMinutes: \(debug.testToastIntervalMinutes)
  testNudgeIntervalMinutes: \(debug.testNudgeIntervalMinutes)
"""
    }
}

// MARK: - Meeting / presentation detection

extension AutoCheckCommand {

    /// Returns true if the user appears to be in a meeting or presenting.
    /// Checks running conferencing apps, active camera/mic, and screen sharing.
    func isUserInMeeting() -> Bool {

        // Check 1: Screen sharing — screensharingd ONLY runs during active screen share.
        // This is 100% accurate, no false positives possible.
        let (screenshared, _) = shell("pgrep -x screensharingd 2>/dev/null")
        if !screenshared.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cliLog("[MeetingCheck] screensharingd active — skipping popup")
            return true
        }

        // Check 2: Microphone actively capturing.
        // ioreg IOAudioEngine only reports "running" when audio is ACTUALLY flowing
        // through an input engine. Returns nothing when mic is idle.
        // Verified accurate on your machine — returned empty when not in a call.
        if isMicrophoneActivelyCapturing() {
            cliLog("[MeetingCheck] Microphone actively capturing — skipping popup")
            return true
        }

        // NOTE: Camera checks removed — every method (lsof, ioreg, avconferenced)
        // produces false positives because Teams/Slack/Zoom keep camera-related
        // background processes running at all times even when not in a call.
        // Screenshare + mic are the reliable signals.

        return false
    }

    /// Returns true only when audio is actively flowing through a mic input engine.
    private func isMicrophoneActivelyCapturing() -> Bool {
        let (result, _) = shell("ioreg -r -c IOAudioEngine -d 4 2>/dev/null | grep -iE 'input.*running|capturing'")
        return !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
