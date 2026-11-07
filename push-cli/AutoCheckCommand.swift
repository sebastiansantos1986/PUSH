// ==============================================================================
// PUSH - Proactive Update Scheduling Helper
//
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
//
// Component: AutoCheckCommand.swift
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
// ==============================================================================

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
import Darwin

struct AutoCheckCommand {
    let args: [String]
    var isDryRun: Bool { args.contains("--dry-run") }
    var checkOnly: Bool { args.contains("--check-only") }
    var notifyOnly: Bool { args.contains("--notify-only") }
    var installNow: Bool { args.contains("--install-now") }
    var isForced: Bool { args.contains("--force") || checkOnly || notifyOnly || installNow }

    struct DetectedUpdate {
        let version: String
        let name:    String
        let isMajor: Bool
        let isBeta:  Bool
    }

    func run() {
        if isDryRun {
            cliPrint("Dry run: would discover updates and evaluate policy. No state changes, prompts, downloads, installation, or restart.")
            return
        }
        guard let config = try? loadConfig() else { cliError("Cannot load config. Run: push-cli config show"); return }
        if config.debug.dryRun {
            cliPrint("Dry run: would discover updates and evaluate policy. No state changes, prompts, downloads, installation, or restart.")
            return
        }
        guard [checkOnly, notifyOnly, installNow].filter({ $0 }).count <= 1 else {
            cliError("Choose exactly one action: check, notify, or install."); return
        }
        guard getuid() == 0 else { cliError("Run this command with sudo to save discovery results."); return }
        guard config.auto.enabled || isForced else { cliPrint("Auto-detection is disabled."); return }
        let audit = RuntimeHealthScope(module:"macos",scheduled:args.contains("--scheduled"))
        defer { audit.finish() }
        guard config.update.deadline.isEmpty || ISO8601DateFormatter().date(from: config.effectiveDeadline) != nil else {
            cliError("update.deadline must include an ISO 8601 date, time, and time zone."); return
        }
        try? FileManager.default.createDirectory(atPath: managedBase, withIntermediateDirectories: true)
        let lock = open(managedBase + "/auto-check.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { cliError("Cannot open discovery lock."); return }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { cliPrint("Another PUSH check is running; no duplicate action started."); return }
        defer { flock(lock, LOCK_UN) }
        LogRotation.rotateIfNeeded(config: config)
        cliLog("[AutoCheck] Starting checkOnly:\(checkOnly) notifyOnly:\(notifyOnly) installNow:\(installNow) force:\(isForced)")

        let current = currentMacOSVersion()
        guard var health = try? loadStateForAction() else {
            cliError("Saved installation state is unreadable. Restore its backup before running update actions."); return
        }
        let oldState = health
        let activity = installationIsActive()
        if let recovery = health.recoverInstallation(running: current, boot: currentBootTimestamp(),
            target: config.update.targetVersion, active: activity) {
            do { try saveState(health); cliPrint(recovery) }
            catch { cliError("Could not save recovered installation state; no new action started."); return }
            if !checkOnly && health.installCompleted && !oldState.installCompleted {
                NotificationManager(config: config).notifyInstallComplete(version: current, previousVersion: oldState.lastSeenVersion)
                if FileManager.default.isExecutableFile(atPath: config.jamf.binaryPath) {
                    _ = runDirect(config.jamf.binaryPath, ["recon"])
                }
            }
        }
        guard activity == false else {
            cliPrint("An installer or update process is active, or its activity cannot be verified. No competing action was started."); return
        }
        guard !health.installStarted else {
            cliPrint("An installation is awaiting reboot verification; no duplicate installation or new target will be scheduled."); return
        }
        if config.ddm.enabled, let version = detectDDMVersion(), !checkOnly {
            cliPrint("Apple DDM is managing macOS \(version). PUSH will step aside."); return
        }
        cliSection("Checking for macOS updates")
        cliInfo("Current macOS:", current)
        let available = detectAvailableUpdates(config: config)
        let best: DetectedUpdate?
        let currentMajor = Int(current.split(separator: ".").first ?? "0") ?? 0
        let minimumMajorRequired = config.auto.enforceMinimumMajorVersion > currentMajor
        if !config.auto.trackLatest && !config.update.targetVersion.isEmpty && !minimumMajorRequired {
            // Keep legacy deployments on their explicitly configured target until tracking is enabled.
            if versionGTE(current, config.update.targetVersion) {
                cliSuccess("Already compliant with configured target \(config.update.targetVersion). Enable auto.trackLatest to follow new releases.")
                if !checkOnly && !notifyOnly && !installNow {
                    if config.auto.autoInstallNonSystemUpdates && (isForced || isWithinAlertWindow(config: config)) { installNonSystemUpdatesQuietly() }
                    performUptimeCheck(config: config)
                }
                return
            }
            best = available.first { sameOSVersion($0.version, config.update.targetVersion) }
                ?? DetectedUpdate(version: config.update.targetVersion, name: config.update.macOSName,
                    isMajor: config.isMajor, isBeta: false)
        } else { best = pickBestUpdate(from: available, config: config, current: current) }
        guard let best else {
            if let issue = loadState().lastDiscoveryError, !issue.isEmpty { cliWarning("Discovery incomplete: \(issue)") }
            else { cliSuccess("No newer eligible macOS update was found for this Mac and policy.") }
            if !checkOnly && !notifyOnly && !installNow {
                if config.auto.autoInstallNonSystemUpdates && (isForced || isWithinAlertWindow(config: config)) { installNonSystemUpdatesQuietly() }
                performUptimeCheck(config: config)
            }
            return
        }
        DetectionLog.record(version: best.version)
        handleDetectedUpdate(best, config: config, current: current)
    }

    private func handleDetectedUpdate(_ best: DetectedUpdate, config: CLIConfig, current: String) {
        guard let cfgPath = resolvedConfigPath, let original = try? String(contentsOfFile: cfgPath, encoding: .utf8) else {
            cliError("Cannot reload config; no changes were made."); return
        }
        var cfg = CLIConfig.parse(yaml: original)
        guard cfg.update.deadline.isEmpty || ISO8601DateFormatter().date(from: cfg.update.deadline) != nil else {
            cliError("The YAML deadline override is invalid; no changes were made."); return
        }
        guard DiscoveryPolicy.eligible(version: best.version, beta: best.isBeta, current: current, config: cfg) else {
            cliPrint("The selected target is excluded by the current update policy."); return
        }
        let changed = !sameOSVersion(cfg.update.targetVersion, best.version)
        var automatic = cfg
        automatic.update.deadline = ""
        let generated = DiscoveryPolicy.deadline(config: automatic, target: best.version,
            isMajor: best.isMajor, firstSeen: DetectionLog.firstSeen(version: best.version) ?? Date())
        cfg.update.targetVersion = best.version
        cfg.update.macOSName = best.name
        cfg.update.releaseType = best.isMajor ? "major" : "minor"
        cfg.update.automaticDeadline = generated
        cfg.update.automaticDeadlineTarget = best.version
        if changed { cfg.update.maxDeferrals = best.isMajor ? cfg.auto.majorMaxDeferrals : cfg.auto.minorMaxDeferrals }
        guard (try? String(contentsOfFile: cfgPath, encoding: .utf8)) == original else {
            cliError("Configuration changed during discovery; retry to use the new policy."); return
        }
        do { try cfg.updatingDetectionYAML(original).write(toFile: cfgPath, atomically: true, encoding: .utf8) }
        catch { cliError("Could not save detected update; no action started."); return }
        if changed {
            var state = loadState()
            state.deferralCount = 0
            state.nextNudgeDate = .distantPast
            state.nextToastDate = Date().addingTimeInterval(cfg.toastIntervalSeconds)
            state.lastSeenVersion = best.version
            state.installCompleted = false
            do { try saveState(state) } catch { cliError("Could not save discovery state; no action started."); return }
            if !checkOnly && cfg.auto.notifyAdminOnDetection && !cfg.auto.adminWebhookURL.isEmpty {
                sendWebhook(config: cfg, update: best, deadline: cfg.effectiveDeadline)
            }
        }
        cliInfo("Target:", best.version)
        cliInfo("Deadline:", cfg.effectiveDeadline)
        cliInfo("Deadline source:", cfg.update.deadline.isEmpty ? "Automatic, anchored to first detection" : "Explicit YAML override")
        if checkOnly { cliPrint("Check complete. No popup, download, or installation was started."); return }
        if installNow {
            RuntimeHealthScope.phase("updating","A macOS installation was requested; authorization and preflight checks still apply")
            InstallWorkflow(config: cfg, skipInitialPrompt: true).run()
            return
        }
        if notifyOnly {
            showNudge(config: cfg)
            return
        }
        if !isForced && !isWithinAlertWindow(config: cfg) {
            cliPrint("Discovery saved. Outside the alert window; notifications will resume during working hours."); return
        }
        if cfg.auto.autoInstallNonSystemUpdates { installNonSystemUpdatesQuietly() }
        runNudgeSchedule(config: cfg)
    }

    // MARK: - Nudge schedule

    private func runNudgeSchedule(config: CLIConfig) {
        // Re-read config from disk in case OS detection above wrote new
        // target/deadline values. Fall back to the parameter if reload fails.
        let config = (try? loadConfig()) ?? config
        let state = loadState()

        cliLog("[AutoCheck] Checking schedule — nextNudge: \(state.nextNudgeDate), nextToast: \(state.nextToastDate)")

        // Uptime check — runs HERE (not earlier in the flow) because we need
        // the post-detection target version to know whether to skip. If an
        // OS update is pending, the uptime evaluator will return .quiet.
        if !isDryRun {
            performUptimeCheck(config: config)
        }

        // ── Deadline enforcement — always checked first ───────────────────────────
        if config.isPastDeadline {
            // Don't start a new install if one is already in progress
            guard !state.installStarted else {
                cliLog("[AutoCheck] Deadline passed but install already in progress — skipping")
                return
            }

            // Defer post-deadline install during active screen share or live meeting.
            // Detection only fires for genuinely-live signals (screensharingd
            // running, mic actively capturing audio) — not for "Zoom is open."
            // This protects users in customer demos / presentations from a
            // forced install at the worst possible moment. Costs at most one
            // hour of enforcement delay (next daemon run will retry).
            if config.schedule.skipInstallDuringScreenShare && isUserInMeeting() {
                cliLog("[AutoCheck] Deadline passed but user is in a meeting/screen share — deferring install one cycle")
                cliPrint("Deadline passed, but a meeting or screen share is active. Will retry next run.")
                return
            }

            if config.update.silentInstallAfterDeadline {
                cliLog("[AutoCheck] Deadline passed + silentInstallAfterDeadline=true — silent install")
                cliPrint("Deadline passed. Running silent install (no UI prompt).")
                RuntimeHealthScope.phase("updating","A macOS installation was requested; authorization and preflight checks still apply")
                InstallWorkflow(config: config, skipInitialPrompt: true).run()
                return
            }

            if config.update.autoInstallAfterDeadline {
                cliLog("[AutoCheck] Deadline passed + autoInstallAfterDeadline=true — forced install with UI")
                cliPrint("Deadline passed. Starting forced install with UI.")

                let uiPath = resolveUIBinary()
                if FileManager.default.fileExists(atPath: uiPath),
                   let cfgPath = resolvedConfigPath {
                    // Kill existing push-ui and wait for it to fully exit
                    // before launching new instance — open -a reuses running
                    // instances and ignores new --args, so we must launch directly
                    shell("pkill -x push-ui 2>/dev/null || true")
                    Thread.sleep(forTimeInterval: 1.0)
                    // Launch directly (not via open -a) so --forced flag is always received
                    if let user = consoleUser() {
                        let launchCmd = "launchctl asuser \(user.uid) sudo -u \"\(user.name)\" \"\(uiPath)\" --state hardBlock --config \"\(cfgPath)\" --deferrals \(state.deferralCount) --forced > /dev/null 2>&1 &"
                        shell(launchCmd)
                        cliLog("[AutoCheck] Forced hardBlock launched directly (uid \(user.uid))")
                    }
                    Thread.sleep(forTimeInterval: 2.0)
                }

                RuntimeHealthScope.phase("updating","A macOS installation was requested; authorization and preflight checks still apply")
                InstallWorkflow(config: config, skipInitialPrompt: true).run()
                return
            }

            // Default: show hardBlock and wait for user to click
        }

        if isForced || state.nextNudgeDate <= Date() {
            // Lock nextNudgeDate to tomorrow BEFORE showing the nudge.
            // This prevents concurrent daemon runs from also firing the nudge
            // while this run is blocking on the popup.
            var lockState = loadState()
            lockState.nextNudgeDate = Date().addingTimeInterval(config.nudgeIntervalSeconds)
            // Schedule next toast for one toast-interval out. Don't use
            // distantFuture — there's no reliable "nudge closed" hook to reset it.
            lockState.nextToastDate = Date().addingTimeInterval(config.toastIntervalSeconds)
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
            RuntimeHealthScope.note("The PUSH popup app is missing",error:true); cliLog("[AutoCheck] push-ui not found — skipping toast"); return
        }
        guard let cfgPath = resolvedConfigPath else { return }

        let state = loadState()
        shell("pkill -x push-ui 2>/dev/null || true")
        Thread.sleep(forTimeInterval: 0.4)

        // Schedule first, then wait for this specific toast's response.
        // No shared temporary file can turn a manual test into an install request.
        var next = loadState()
        next.nextToastDate = Date().addingTimeInterval(config.toastIntervalSeconds)
        try? saveState(next)
        let status = runUIBlocking("\"\(uiPath)\" --state toast --config \"\(cfgPath)\" --deferrals \(state.deferralCount)")
        cliLog("[AutoCheck] " + popupResultMessage(state: "toast", exitCode: status))
        if toastRequestedInstall(exitCode: status) {
            RuntimeHealthScope.phase("updating","A macOS installation was requested; authorization and preflight checks still apply")
            InstallWorkflow(config: config, skipInitialPrompt: true).run()
        }
        // Later, close, timeout, and failure do not install or consume a deferral.
    }

    // MARK: - Show softNudge or hardBlock (Later counts deferral)

    private func showNudge(config: CLIConfig) {
        // Skip if no user is logged in — cannot show UI at login window.
        // Log clearly so IT knows why the nudge was skipped.
        guard userIsLoggedIn() else {
            RuntimeHealthScope.note("No console user is available for the update prompt")
            cliLog("[AutoCheck] No console user logged in — skipping nudge, will retry next run")
            cliPrint("No user logged in. Will retry when a user is at the console.")
            return
        }

        // Skip if user is in a meeting — but NOT if deadline has passed and
        // no deferrals remain (hardBlock still fires in that case)
        let state0        = loadState()
        let noDeferrals0  = state0.deferralCount >= config.update.maxDeferrals
        let isHardBlock   = config.isPastDeadline || noDeferrals0

        if !isForced && !isHardBlock && config.schedule.skipDuringMeetings && isUserInMeeting() {
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

        // Default: push next nudge date forward by one nudge interval.
        // The scheduledDefer case below overrides this with the user-chosen date.
        state.nextNudgeDate = Date().addingTimeInterval(config.nudgeIntervalSeconds)

        let notifier = NotificationManager(config: config)

        switch Int(status) {
        case 0:
            // User clicked Install Now
            cliLog("[AutoCheck] User accepted — starting install workflow")
            try? saveState(state)
            // skipInitialPrompt=true because user already confirmed in this nudge popup
            RuntimeHealthScope.phase("updating","A macOS installation was requested; authorization and preflight checks still apply")
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
        case 3:
            // User picked a specific date/time — no deferral cost.
            // push-ui wrote the chosen ISO date to /tmp/push-scheduled-until.
            let scheduledFile = "/tmp/push-scheduled-until"
            if let iso = try? String(contentsOfFile: scheduledFile, encoding: .utf8)
                                .trimmingCharacters(in: .whitespacesAndNewlines),
               let scheduledDate = ISO8601DateFormatter().date(from: iso) {
                // Cap to deadline as a safety net (UI also caps, this is defense-in-depth)
                let cappedDate: Date
                if let deadlineDate = ISO8601DateFormatter().date(from: config.effectiveDeadline),
                   scheduledDate > deadlineDate {
                    cappedDate = deadlineDate.addingTimeInterval(-3600)
                    cliLog("[AutoCheck] User picked \(iso) but capped to deadline-1h")
                } else {
                    cappedDate = scheduledDate
                }
                state.nextNudgeDate = cappedDate
                // Don't touch nextToastDate — toasts should keep firing on their
                // normal interval until the scheduled nudge time arrives. The user
                // asked for the *nudge* to be silenced until then, not all activity.
                try? FileManager.default.removeItem(atPath: scheduledFile)

                let f = DateFormatter()
                f.dateStyle = .medium
                f.timeStyle = .short
                cliLog("[AutoCheck] User scheduled reminder for \(f.string(from: cappedDate)) — no deferral counted")
                cliPrint("Reminder scheduled for \(f.string(from: cappedDate)).")
            } else {
                // Couldn't parse the date file — fall back to standard nudge interval
                cliLog("[AutoCheck] Schedule exit code 3 but no valid date found at \(scheduledFile)")
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

    func isWithinAlertWindow(config: CLIConfig) -> Bool {
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
        var updates: [DetectedUpdate] = []
        var issues: [String] = []
        var succeeded = false
        do {
            let output = try discoveryOutput("/usr/sbin/softwareupdate", ["--list"], timeout: 180)
            updates = parseUpdates(output: output, config: config)
            succeeded = true
        } catch { issues.append("Apple Software Update: \(error.localizedDescription)") }
        if config.auto.useMist {
            let candidates = ["/usr/local/bin/mist", "/opt/homebrew/bin/mist"]
            if let binary = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                do {
                    updates += try compatibleMistUpdates(binary: binary, current: currentMacOSVersion())
                    succeeded = true
                } catch { issues.append("Mist: \(error.localizedDescription)") }
            } else { issues.append("Optional mist-cli is missing; only Apple Software Update was checked.") }
        }
        var state = loadState()
        if succeeded { state.lastDiscoveryDate = Date() }
        state.lastDiscoveryError = issues.isEmpty ? nil : issues.joined(separator: " ")
        do { try saveState(state) } catch { cliError("Could not save discovery health.") }
        for issue in issues { cliLog("[Discovery] \(issue)") }
        return updates
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
            guard title.lowercased().hasPrefix("macos"), !version.isEmpty, isValidVersion(version),
                  !versionGTE(current, version) else { continue }

            let targetMajor = Int(version.split(separator: ".").first ?? "0") ?? 0
            let isMajor     = targetMajor != currentMajor
            let isBeta      = line.lowercased().contains("beta") || line.lowercased().contains("rc")
            let name        = cleanName(title: title, version: version)
            updates.append(DetectedUpdate(version: version, name: name,
                                          isMajor: isMajor, isBeta: isBeta))
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
        updates.filter { DiscoveryPolicy.eligible(version: $0.version, beta: $0.isBeta, current: current, config: config) }
            .sorted { !versionGTE($0.version, $1.version) }.last
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
    func updatingDetectionYAML(_ source: String) -> String {
        var yaml = source
        for (key, value) in [
            ("targetVersion", update.targetVersion), ("macOSName", update.macOSName),
            ("releaseType", update.releaseType), ("deadline", update.deadline),
            ("automaticDeadline", update.automaticDeadline), ("automaticDeadlineTarget", update.automaticDeadlineTarget),
            ("maxDeferrals", String(update.maxDeferrals))
        ] { yaml = updatingYAMLString(yaml, section: ["update"], field: key, value: value) }

        return yaml
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

    /// Run the uptime monitoring check. May launch a popup; never blocks the
    /// rest of auto-check. The popup runs in the user's session via launchctl
    /// asuser so we don't gate on its result here — user's response is handled
    /// by a small follow-up exit-code switch below.
    private func performUptimeCheck(config: CLIConfig) {
        let decision = UptimeCheck(config: config).evaluate()
        switch decision {
        case .quiet:
            return

        case .showWarning(let days, let remaining):
            // Need a console user to show UI to
            guard let user = consoleUser() else {
                cliLog("[Uptime] Warning needed but no console user — will retry next run")
                return
            }
            guard let cfgPath = resolvedConfigPath else { return }
            let uiPath = resolveUIBinary()
            guard FileManager.default.fileExists(atPath: uiPath) else { return }

            cliLog("[Uptime] Showing warning popup (uptime=\(days)d, deferrals remaining=\(remaining))")
            // Block on the popup — exit code 0 = restart now, 1 = later
            let cmd = "launchctl asuser \(user.uid) sudo -u \"\(user.name)\" \"\(uiPath)\" --state rebootNudge --config \"\(cfgPath)\" --uptime-days \(days) --deferrals-remaining \(remaining)"
            let status = runUIBlocking(cmd)

            switch Int(status) {
            case 0:  // Restart Now
                cliLog("[Uptime] User chose Restart Now from warning popup")
                UptimeCheck.performRestart()
            case 1:  // Later
                UptimeCheck.recordDeferral(config: config)
            default: // Dismissed (no Esc/X allowed but defensive)
                cliLog("[Uptime] Warning popup exited with code \(status) — treating as dismissal")
            }

        case .showForce(let days, let timer):
            guard let user = consoleUser() else {
                cliLog("[Uptime] Force needed but no console user — will retry next run")
                return
            }
            guard let cfgPath = resolvedConfigPath else { return }
            let uiPath = resolveUIBinary()
            guard FileManager.default.fileExists(atPath: uiPath) else { return }

            cliLog("[Uptime] Showing FORCE popup (uptime=\(days)d, timer=\(timer)s)")
            let cmd = "launchctl asuser \(user.uid) sudo -u \"\(user.name)\" \"\(uiPath)\" --state rebootForce --config \"\(cfgPath)\" --uptime-days \(days) --timer-seconds \(timer)"
            let status = runUIBlocking(cmd)

            // Force popup either: returns 0 when user clicked Restart Now,
            // OR returns when the countdown reaches zero (also exit 0).
            // Either way, we trigger restart.
            cliLog("[Uptime] Force popup completed (exit \(status)) — triggering restart")
            UptimeCheck.performRestart()
        }
    }

    /// Install all non-system updates silently in the background.
    ///
    /// "Non-system" here means anything `softwareupdate --list` flags as NOT
    /// requiring a restart — typically Safari, XProtect, MRT, command-line
    /// tools, Gatekeeper config updates. These can install at any time
    /// without disrupting the user.
    ///
    /// We log all activity but never surface UI for these — they should be
    /// invisible. If install fails, we log it; the next auto-check run will
    /// retry. We never block the rest of auto-check on this — bad failure
    /// mode would be "non-system update fails → user never sees nudges."
    private func installNonSystemUpdatesQuietly() {
        let (listOut, _) = shell("/usr/sbin/softwareupdate --list 2>&1 | head -200")
        let labels = parseNonSystemLabels(listOut)
        guard !labels.isEmpty else { return }

        cliLog("[AutoCheck] Non-system updates available: \(labels.count) — installing silently")
        for label in labels {
            // Re-quote single quotes for shell safety
            let safe = label.replacingOccurrences(of: "'", with: "'\\''")
            let cmd  = "/usr/sbin/softwareupdate --install '\(safe)' --no-scan --agree-to-license 2>&1"
            let (out, status) = shell(cmd)
            if status == 0 {
                cliLog("[AutoCheck] Installed non-system update: \(label)")
            } else {
                // Log first 200 chars of output for diagnostics, no popup
                let snippet = out.prefix(200).replacingOccurrences(of: "\n", with: " ")
                cliLog("[AutoCheck] Non-system update '\(label)' failed (exit \(status)): \(snippet)")
            }
        }
    }

    /// Mirror of ExtrasCommand.parseNonSystemLabels — duplicated here to keep
    /// AutoCheck self-contained. If we ever refactor, fold these together.
    private func parseNonSystemLabels(_ output: String) -> [String] {
        var labels: [String] = []
        var current = ""
        var requiresRestart = false
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("* Label:") {
                // Flush previous candidate
                if !current.isEmpty && !requiresRestart { labels.append(current) }
                current = trimmed
                    .replacingOccurrences(of: "* Label:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                requiresRestart = false
            } else if trimmed.lowercased().contains("action: restart") {
                requiresRestart = true
            }
        }
        // Final candidate
        if !current.isEmpty && !requiresRestart { labels.append(current) }
        return labels
    }
}


// MARK: - Read-only catalog access (no download or install commands)
// Developer: Sebastian Santos
struct DiscoveryError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func discoveryOutput(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> String {
    let fm = FileManager.default
    let folder = fm.temporaryDirectory.appendingPathComponent("push-discovery-" + UUID().uuidString)
    try fm.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? fm.removeItem(at: folder) }
    let file = folder.appendingPathComponent("output")
    guard fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]),
          let output = FileHandle(forWritingAtPath: file.path) else { throw DiscoveryError(message: "Cannot prepare catalog output.") }
    defer { try? output.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output; process.standardError = output
    try process.run()
    let end = Date().addingTimeInterval(timeout)
    while process.isRunning {
        let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        if Date() >= end || size > 8_388_608 {
            process.terminate(); kill(process.processIdentifier, SIGKILL); process.waitUntilExit()
            throw DiscoveryError(message: "Catalog query timed out or exceeded the output limit.")
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    process.waitUntilExit()
    guard process.terminationReason == .exit && process.terminationStatus == 0 else {
        throw DiscoveryError(message: "Catalog query failed (exit \(process.terminationStatus)).")
    }
    guard let size = try fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber, size.intValue <= 8_388_608 else {
        throw DiscoveryError(message: "Catalog output exceeded the size limit.")
    }
    return String(decoding: try Data(contentsOf: file), as: UTF8.self)
}

func parseMistUpdates(_ data: Data, current: String) throws -> [AutoCheckCommand.DetectedUpdate] {
    let object = try JSONSerialization.jsonObject(with: data)
    let items: [[String: Any]]
    if let list = object as? [[String: Any]] { items = list }
    else if let dict = object as? [String: Any], let list = (dict["installers"] ?? dict["items"]) as? [[String: Any]] { items = list }
    else { throw DiscoveryError(message: "Unrecognized catalog format.") }
    return items.compactMap { item in
        let dict = Dictionary(item.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        func text(_ key: String) -> String { dict[key].map { String(describing: $0) } ?? "" }
        let version = text("version"), name = text("name")
        guard numericOSVersion(version) != nil, !versionGTE(current, version) else { return nil }
        if ["false", "no", "0"].contains(text("compatible").lowercased()) { return nil }
        let beta = name.lowercased().contains("beta") || name.lowercased().contains("release candidate")
            || name.lowercased().contains("developer preview") || ["beta", "isbeta"].contains { ["true", "yes", "1"].contains(text($0).lowercased()) }
        return AutoCheckCommand.DetectedUpdate(version: version, name: name.isEmpty ? "macOS" : name,
            isMajor: version.split(separator: ".").first != current.split(separator: ".").first, isBeta: beta)
    }
}

func compatibleMistUpdates(binary: String, current: String) throws -> [AutoCheckCommand.DetectedUpdate] {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("push-mist-list-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: folder) }
    let export = folder.appendingPathComponent("catalog.json")
    _ = try discoveryOutput(binary, ["list", "installer", "--compatible", "--export", export.path], timeout: 180)
    let values = try export.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 16_777_216 else {
        throw DiscoveryError(message: "Invalid or oversized catalog export.")
    }
    return try parseMistUpdates(Data(contentsOf: export), current: current)
}
