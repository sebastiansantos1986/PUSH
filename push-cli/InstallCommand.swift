// ==============================================================================
// PUSH - Proactive Update Scheduling Helper
//
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
//
// Component: InstallCommand.swift
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
// ==============================================================================

// InstallCommand.swift — Full macOS install workflow
//
// Download chain:
//   1. Native pending update check (softwareupdate --list, Action: restart)
//   2. softwareupdate --fetch-full-installer
//   3. mist-cli fallback
//
// Restart flow: user-friendly prompt → preflight → download → install → reboot

import Foundation
import Darwin

/// Carries both the admin account name and its password through the install path.
/// For LAPS we use the managed admin account (e.g. CasperLocalAdmin); for keychain
/// or config-file auth we use the console user (pre-existing behavior).
struct InstallCredentials {
    let username: String
    let password: String
    /// True if these credentials came from the user-saved-password keychain
    /// path. If startosinstall rejects them anyway, the failure handler will
    /// delete the stale entry so the user gets re-prompted on the next attempt.
    let fromSavedUserPassword: Bool

    init(username: String, password: String, fromSavedUserPassword: Bool = false) {
        self.username = username
        self.password = password
        self.fromSavedUserPassword = fromSavedUserPassword
    }
}

struct InstallWorkflow {
    let config: CLIConfig
    // Set true when called from AutoCheck after user already clicked Install —
    // avoids showing a second confirmation popup.
    var skipInitialPrompt: Bool = false

    func run() {
        guard numericOSVersion(config.update.targetVersion) != nil else {
            cliError("A complete numeric macOS target version is required (for example 26.1).")
            return
        }
        // Dry run exits before UI, downloads, credentials, state writes, or installer execution.
        if config.debug.dryRun {
            cliPrint("Dry run: would install macOS \(config.update.targetVersion). No actions performed.")
            return
        }
        guard getuid() == 0 else { cliError("Installation requires root."); return }
        guard installationIsActive() == false else {
            cliError("Another installer/update is active, or activity cannot be verified. Installation was not started."); return
        }
        guard preparePushRuntime() else { cliError("Cannot prepare secure runtime directory."); return }
        // Kernel-held lock prevents concurrent workflows, and is released after a crash.
        try? FileManager.default.createDirectory(atPath: managedBase, withIntermediateDirectories: true)
        let lock = open(managedBase + "/install.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { cliError("Cannot open installation lock."); return }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { cliInfo("Installation:", "Already running"); return }
        defer { flock(lock, LOCK_UN) }
        guard let pending = try? loadStateForAction() else {
            cliError("Saved installation state is unreadable. No installation was started."); return
        }
        guard !pending.installStarted else {
            cliInfo("Installation:", "Awaiting reboot verification. Run auto-check after restarting.")
            return
        }
        if versionGTE(currentMacOSVersion(), config.update.targetVersion) {
            cliSuccess("This Mac already meets the requested macOS version.")
            return
        }
        cliLog("[Install] Starting for \(config.update.targetVersion)")

        // Prevent sleep for the entire install workflow — download + install can
        // take 20-30 min and we cannot have the machine sleep mid-way.
        // Redirect stdout/stderr to /dev/null so caffeinate doesn't inherit the
        // shell pipe file descriptors — otherwise shell() blocks indefinitely.
        let caffeinatePID = ProcessInfo.processInfo.processIdentifier
        shell("caffeinate -d -i -s -w \(caffeinatePID) >/dev/null 2>&1 &")
        cliLog("[Install] caffeinate started (attached to PID \(caffeinatePID)) — sleep prevented")

        let uiPath  = resolveUIBinary()
        let cfgPath = resolvedConfigPath ?? ""

        // ── Step 1: Native pending update? ─────────────────────────────────
        if config.update.releaseType != "major",
           let label = findPendingNativeUpdate(version: config.update.targetVersion) {
            cliLog("[Install] Native pending update found: '\(label)'")
            installNativePendingUpdate(label: label, uiPath: uiPath, cfgPath: cfgPath)
            return
        }

        // ── Step 2: Find or download installer ─────────────────────────────
        let installerPath: String?
        if let existing = findExistingInstaller() {
            cliLog("[Install] Using existing installer: \(existing)")
            installerPath = existing
        } else {
            installerPath = downloadInstaller(uiPath: uiPath, cfgPath: cfgPath)
        }

        guard let installer = installerPath else {
            let contact = config.ui.itContactEmail.isEmpty ? "IT support" : config.ui.itContactEmail
            showError("Could not download the macOS installer. Contact \(contact).",
                      uiPath: uiPath, cfgPath: cfgPath)
            exit(1)
        }

        // ── Step 3: Prompt restart ──────────────────────────────────────────
        // Skip if user already clicked Install in the AutoCheck nudge popup.
        if skipInitialPrompt {
            cliLog("[Install] Skipping restart prompt — user already accepted in nudge")
            beginInstall(installer: installer, uiPath: uiPath, cfgPath: cfgPath)
        } else {
            promptRestart(installer: installer, uiPath: uiPath, cfgPath: cfgPath)
        }
    }

    // MARK: - Native pending update

    private func findPendingNativeUpdate(version: String) -> String? {
        let (output, _) = shell("/usr/sbin/softwareupdate --list 2>&1")
        return nativeUpdateLabel(version: version, output: output, restartOnly: true)
    }

    private func installNativePendingUpdate(label: String, uiPath: String, cfgPath: String) {
        shell("pkill -x push-ui 2>/dev/null || true")
        Thread.sleep(forTimeInterval: 0.3)

        // Skip confirmation prompt if user already accepted (from nudge or forced install)
        if !skipInitialPrompt {
            let status = runUIBlocking("\"\(uiPath)\" --state softNudge --config \"\(cfgPath)\" --deferrals 0")
            guard Int(status) == 0 else {
                cliLog("[Install] User deferred native update")
                return
            }
        } else {
            cliLog("[Install] Skipping native update prompt — user already accepted or forced install")
        }

        // Resolve credentials before showing installing UI
        var creds: InstallCredentials? = nil
        if isAppleSilicon() {
            creds = resolveInstallCredentials(uiPath: uiPath, cfgPath: cfgPath,
                                              skipInitialPrompt: skipInitialPrompt,
                                              contextLabel: "native path")
        }

        guard credentialsAreUsable(creds, uiPath: uiPath, cfgPath: cfgPath) else { return }
        let checks = PreflightChecks(config: config)
        if let result = checks.checkBattery(), case .fail(let reason, _) = result {
            showError(reason, uiPath: uiPath, cfgPath: cfgPath); return
        }
        if let result = checks.checkDisk(PreflightChecks.availableDiskGB()), case .fail(let reason, _) = result {
            showError(reason, uiPath: uiPath, cfgPath: cfgPath); return
        }
        guard let user = consoleUser() else {
            cliLog("[Install] No console user found — cannot trigger native update")
            return
        }

        launchUIAsUser("\"\(uiPath)\" --state installing --config \"\(cfgPath)\" --quick-restart")
        Thread.sleep(forTimeInterval: 2.0)

        streamNativeInstall(label: label, creds: creds, user: user)
    }

    private func streamNativeInstall(label: String, creds: InstallCredentials?, user: (name: String, uid: Int)) {
        var arguments = ["asuser", String(user.uid), "/usr/bin/sudo", "-u", "root", "--",
            "/usr/sbin/softwareupdate", "--install", label, "--restart", "--force", "--no-scan", "--agree-to-license"]
        if let creds { arguments += ["--user", creds.username, "--stdinpass"] }
        performInstaller(executable: "/bin/launchctl", arguments: arguments, creds: creds,
                         uiPath: resolveUIBinary(), cfgPath: resolvedConfigPath ?? "")
    }

    private func parseNativeProgress(_ line: String) -> Double? {
        guard line.contains("%"),
              let regex = try? NSRegularExpression(pattern: #"(\d+\.?\d*)\s*%"#),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line),
              let value = Double(String(line[range]))
        else { return nil }
        return min(1.0, value / 100.0)
    }

    // MARK: - Restart prompt

    private func promptRestart(installer: String, uiPath: String, cfgPath: String) {
        var state = loadState()
        shell("pkill -x push-ui 2>/dev/null || true")
        Thread.sleep(forTimeInterval: 0.4)

        let noDeferrals = state.deferralCount >= config.update.maxDeferrals
        let uiState     = (config.isPastDeadline || noDeferrals) ? "hardBlock" : "softNudge"

        let status = runUIBlocking("\"\(uiPath)\" --state \(uiState) --config \"\(cfgPath)\" --deferrals \(state.deferralCount)")

        state.nextNudgeDate = Date().addingTimeInterval(config.nudgeIntervalSeconds)

        switch Int(status) {
        case 0:
            cliLog("[Install] User accepted — proceeding")
            try? saveState(state)
            beginInstall(installer: installer, uiPath: uiPath, cfgPath: cfgPath)
        case 1:
            guard !config.isPastDeadline && !noDeferrals else {
                showGraceCountdown(installer: installer, uiPath: uiPath, cfgPath: cfgPath)
                return
            }
            state.deferralCount += 1
            state.nextNudgeDate  = Date().addingTimeInterval(config.nudgeIntervalSeconds)
            try? saveState(state)
            cliLog("[Install] Deferred — count \(state.deferralCount)")
        default:
            try? saveState(state)
        }
    }

    private func showGraceCountdown(installer: String, uiPath: String, cfgPath: String) {
        shell("pkill -x push-ui 2>/dev/null || true")
        Thread.sleep(forTimeInterval: 0.3)
        let status = runUIBlocking("\"\(uiPath)\" --state rebooting --config \"\(cfgPath)\"")
        if Int(status) == 0 {
            beginInstall(installer: installer, uiPath: uiPath, cfgPath: cfgPath)
        } else {
            cliLog("[Install] Grace countdown dismissed — retrying in 30 minutes")
            Thread.sleep(forTimeInterval: 30 * 60)
            beginInstall(installer: installer, uiPath: uiPath, cfgPath: cfgPath)
        }
    }

    // MARK: - Install

    private func beginInstall(installer: String, uiPath: String, cfgPath: String) {
        let checks = PreflightChecks(config: config)

        // Battery preflight
        if let r = checks.checkBattery(), case .fail(let reason, _) = r {
            cliLog("[Install] Battery preflight failed: \(reason)")
            showError(reason, uiPath: uiPath, cfgPath: cfgPath)
            return
        }

        // Disk space preflight — check BEFORE running startosinstall.
        // The installer needs space to apply the upgrade, separate from the download.
        let availableGB = PreflightChecks.availableDiskGB()
        cliLog("[Preflight] Disk space: \(String(format: "%.1f", availableGB)) GB available")
        if let r = checks.checkDisk(availableGB), case .fail(let reason, _) = r {
            cliLog("[Install] Disk preflight failed: \(reason)")
            shell("pkill -x push-ui 2>/dev/null || true")
            Thread.sleep(forTimeInterval: 0.3)
            let needed = Double(config.preflight.minDiskSpaceGB)
            launchUIAsUser("\"\(uiPath)\" --state preflightDisk --config \"\(cfgPath)\" --disk-available \(String(format: "%.1f", availableGB)) --disk-required \(String(format: "%.0f", needed))")
            cliLog("[Install] Disk space popup shown — \(reason)")
            return
        }

        var creds: InstallCredentials? = nil
        if isAppleSilicon() {
            creds = resolveInstallCredentials(uiPath: uiPath, cfgPath: cfgPath,
                                              skipInitialPrompt: skipInitialPrompt,
                                              contextLabel: "startosinstall")
        }
        guard credentialsAreUsable(creds, uiPath: uiPath, cfgPath: cfgPath) else { return }

        shell("pkill -x push-ui 2>/dev/null || true")
        Thread.sleep(forTimeInterval: 0.3)
        launchUIAsUser("\"\(uiPath)\" --state installing --config \"\(cfgPath)\"")
        Thread.sleep(forTimeInterval: 2.0)

        runStartOSInstall(installer: installer, creds: creds,
                          uiPath: uiPath, cfgPath: cfgPath)
    }

    // MARK: - Download chain

    private func downloadInstaller(uiPath: String, cfgPath: String) -> String? {
        let version     = config.update.targetVersion
        let downloadDir = "\(managedBase)/downloads"
        let checks      = PreflightChecks(config: config)

        // Network reachability check before starting download
        if !checks.checkNetworkReachability() {
            cliLog("[Install] Network unreachable — cannot download")
            showError("Cannot reach Apple servers. Check your internet connection.",
                      uiPath: uiPath, cfgPath: cfgPath)
            exit(1)
        }

        try? FileManager.default.createDirectory(atPath: downloadDir,
                                                  withIntermediateDirectories: true)

        shell("pkill -x push-ui 2>/dev/null || true")
        Thread.sleep(forTimeInterval: 0.5)
        launchUIAsUser("\"\(uiPath)\" --state downloading --config \"\(cfgPath)\" --download-progress 0 --download-subtitle \"Preparing download…\"")
        Thread.sleep(forTimeInterval: 1.0)

        let isMajor = config.update.releaseType == "major"

        // ── Major upgrade: use mist-cli first (more reliable for full installers) ──
        // mist-cli downloads directly from Apple CDN with proper retry and progress.
        // softwareupdate --fetch-full-installer can fail on managed devices with MDM
        // restrictions and sometimes downloads a stub rather than the full installer.
        if isMajor, let mist = findMistCLI() {
            cliLog("[Install] Major upgrade — using mist-cli as primary download method")
            try? "0.01\nConnecting to Apple servers…"
                .write(toFile: "/private/var/run/com.push/download-progress", atomically: true, encoding: .utf8)

            let mistOK = streamDownload(
                executable: mist, arguments: ["download", "installer", version, "application", "--output-directory", "/Applications", "--compatible", "--force", "--no-ansi"],
                tool: "mist-cli"
            )
            if mistOK, let found = findInstallerInApplications() {
                cliLog("[Install] mist-cli succeeded: \(found)")
                finishDownloadUI()
                return found
            }
            cliLog("[Install] mist-cli failed — falling back to softwareupdate")
            try? "0.01\nSwitching to alternate download method…"
                .write(toFile: "/private/var/run/com.push/download-progress", atomically: true, encoding: .utf8)
            Thread.sleep(forTimeInterval: 1.5)
        } else if isMajor {
            cliLog("[Install] Major upgrade — mist-cli not found, using softwareupdate")
        }

        // ── Minor update / mist-cli fallback: softwareupdate --fetch-full-installer ──
        // softwareupdate resumes automatically if a .partial file exists in cache.
        let (cachedPartial, _) = shell("find /private/var/folders -maxdepth 12 -name 'InstallAssistant.pkg.partial' 2>/dev/null | head -1")
        let partial = cachedPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty {
            let (sizeOut, _) = shell("du -sh \"\(partial)\" 2>/dev/null | awk '{print $1}'")
            let sz = sizeOut.trimmingCharacters(in: .whitespaces)
            cliLog("[Install] Found partial download (\(sz)) — softwareupdate will resume")
            try? "0.01\nResuming previous download (\(sz) already downloaded)…"
                .write(toFile: "/private/var/run/com.push/download-progress", atomically: true, encoding: .utf8)
        }

        cliLog("[Install] Using softwareupdate --fetch-full-installer \(version)")
        let swuOK = streamDownload(
            executable: "/usr/sbin/softwareupdate", arguments: ["--fetch-full-installer", "--full-installer-version", version],
            tool: "softwareupdate"
        )
        if swuOK, let found = findInstallerInApplications() {
            cliLog("[Install] softwareupdate succeeded: \(found)")
            finishDownloadUI()
            return found
        }
        cliLog("[Install] softwareupdate failed — trying mist-cli as last resort")

        try? "0.01\nSwitching to alternate download method…"
            .write(toFile: "/private/var/run/com.push/download-progress", atomically: true, encoding: .utf8)
        Thread.sleep(forTimeInterval: 1.5)

        // Last resort: mist-cli for minor updates if softwareupdate also failed
        guard let mist = findMistCLI() else {
            cliLog("[Install] mist-cli not found — all methods exhausted")
            finishDownloadUI(success: false)
            return nil
        }
        cliLog("[Install] Last resort — mist-cli at \(mist)")
        let mistOK2 = streamDownload(
            executable: mist, arguments: ["download", "installer", version, "application", "--output-directory", "/Applications", "--compatible", "--force", "--no-ansi"],
            tool: "mist-cli"
        )
        if mistOK2, let found = findInstallerInApplications() {
            cliLog("[Install] mist-cli (last resort) succeeded: \(found)")
            finishDownloadUI()
            return found
        }

        cliLog("[Install] All download methods exhausted")
        finishDownloadUI(success: false)
        return nil
    }

    @discardableResult
    private func streamDownload(executable: String, arguments: [String], tool: String) -> Bool {
        let directory = URL(fileURLWithPath: "/private/var/run/com.push").appendingPathComponent(UUID().uuidString)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                     attributes: [.posixPermissions: 0o700]) } catch { return false }
        defer { try? FileManager.default.removeItem(at: directory) }
        let logFile = directory.appendingPathComponent("download.log").path
        guard FileManager.default.createFile(atPath: logFile, contents: nil, attributes: [.posixPermissions: 0o600]),
              let output = FileHandle(forWritingAtPath: logFile) else { return false }
        defer { try? output.close() }
        let expectedBytes = getExpectedInstallerSize(version: config.update.targetVersion)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        do { try process.run() }
        catch { cliLog("[Install] Cannot launch \(tool)"); return false }

        var lastProgress    = 0.0
        var processedLines  = 0
        var pulseTick       = 0
        var dynamicExpected = expectedBytes  // expands if file exceeds initial estimate
        var lastFileBytes   = Int64(0)
        var plateauTicks    = 0              // tracks how long progress is near the cap

        while process.isRunning {
            Thread.sleep(forTimeInterval: 3.0)

            // Parse stdout lines — used for mist-cli (outputs real %)
            // For softwareupdate we skip since its % is an internal stage counter
            if let raw = try? String(contentsOfFile: logFile, encoding: .utf8) {
                let lines    = raw.components(separatedBy: CharacterSet(charactersIn: "\r\n")).filter { !$0.isEmpty }
                let newLines = Array(lines.dropFirst(processedLines))
                processedLines = lines.count
                for line in newLines {
                    cliLog("[\(tool)] \(line)")
                    guard tool != "softwareupdate" else { continue }
                    guard let progress = parseProgress(line) else { continue }
                    guard abs(progress - lastProgress) > 0.005 else { continue }
                    lastProgress = progress
                    let subtitle = progressSubtitle(progress: progress, line: line, tool: tool)
                    try? "\(String(format: "%.3f", progress))\n\(subtitle)"
                        .write(toFile: "/private/var/run/com.push/download-progress", atomically: true, encoding: .utf8)
                }
            }

            // Disk-based tracking — works for both softwareupdate and mist-cli
            // (mist-cli buffers stdout when piped so we can't rely on its % output)
            if tool == "softwareupdate" || tool == "mist-cli" {
                let currentBytes = rawInstallerBytes()

                // KEY FIX: mdmclient DownloadSize is the network payload size.
                // The .partial file on disk is larger (verification + staging overhead).
                // Dynamically expand our expected size whenever the file exceeds it
                // so progress never freezes at a cap while download is still running.
                if currentBytes > dynamicExpected {
                    dynamicExpected = Int64(Double(currentBytes) * 1.20) // 20% headroom
                    cliLog("[Install] Expanded expected to \(dynamicExpected / 1_048_576) MB (file exceeded estimate)")
                }

                let fileProgress  = dynamicExpected > 0 ? Double(currentBytes) / Double(dynamicExpected) : 0.0
                let cappedProgress = min(0.96, fileProgress) // reserve last 4% for verification

                if currentBytes > 0 {
                    let growing = currentBytes > lastFileBytes
                    lastFileBytes = currentBytes

                    if cappedProgress > lastProgress + 0.003 {
                        lastProgress = cappedProgress
                        plateauTicks = 0
                    } else {
                        plateauTicks += 1
                    }

                    let pct = String(format: "%.1f", lastProgress * 100)
                    let mbDone = currentBytes / 1_048_576
                    let gbDone = mbDone / 1024
                    let gbExp  = dynamicExpected / 1_073_741_824

                    let subtitle: String
                    if plateauTicks > 4 && lastProgress > 0.88 {
                        // Progress has plateaued near the top — file still growing
                        subtitle = growing
                            ? "Downloading macOS… \(gbDone) of \(gbExp) GB"
                            : "Verifying download, please wait…"
                    } else {
                        subtitle = "Downloading macOS… \(pct)%"
                    }

                    try? "\(String(format: "%.3f", lastProgress))\n\(subtitle)"
                        .write(toFile: "/private/var/run/com.push/download-progress", atomically: true, encoding: .utf8)
                    cliLog("[Install] Progress: \(pct)% (\(mbDone) MB / \(dynamicExpected / 1_048_576) MB expected)")

                } else if lastProgress < 0.01 {
                    pulseTick += 1
                    let pulseVal = 0.02 + 0.02 * Double(pulseTick % 8)
                    let dots = String(repeating: ".", count: (pulseTick % 3) + 1)
                    try? "\(String(format: "%.3f", pulseVal))\nConnecting to Apple servers\(dots)"
                        .write(toFile: "/private/var/run/com.push/download-progress", atomically: true, encoding: .utf8)
                } else {
                    let pct = String(format: "%.1f", lastProgress * 100)
                    try? "\(String(format: "%.3f", lastProgress))\nDownloading macOS… \(pct)%"
                        .write(toFile: "/private/var/run/com.push/download-progress", atomically: true, encoding: .utf8)
                }
            }

        }
        process.waitUntilExit()
        let success = process.terminationStatus == 0
        if !success { cliLog("[Install] \(tool) failed with exit status \(process.terminationStatus)") }
        return success
    }

    /// Raw bytes written to the installer — checks softwareupdate, mist-cli temp dir, and lsof.
    private func rawInstallerBytes() -> Int64 {
        var largest = Int64(0)

        func checkPath(_ path: String) {
            let (sizeStr, _) = shell("du -sk \"\(path)\" 2>/dev/null | awk '{print $1}'")
            if let kb = Int64(sizeStr.trimmingCharacters(in: .whitespacesAndNewlines)), kb > 0 {
                let bytes = kb * 1024
                if bytes > largest { largest = bytes }
            }
        }

        // softwareupdate: find open .partial file via lsof
        let (lsofOut, _) = shell("lsof -c softwareupdate 2>/dev/null | awk '{print $NF}' | grep -E '.partial$|.pkg$|.dmg$' | head -5")
        for line in lsofOut.components(separatedBy: "\n") {
            let path = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, path.hasPrefix("/") else { continue }
            checkPath(path)
        }

        // mist-cli: check its temp download directory (buffered stdout = no real-time %)
        for dir in ["/private/tmp/com.ninxsoft.mist", "/tmp/com.ninxsoft.mist"] {
            if FileManager.default.fileExists(atPath: dir) { checkPath(dir) }
        }

        // mist-cli open files via lsof
        let (mistLsof, _) = shell("lsof -c mist 2>/dev/null | awk '{print $NF}' | grep -v DEL | grep -E '.pkg$|.dmg$|.app$' | head -3")
        for line in mistLsof.components(separatedBy: "\n") {
            let path = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, path.hasPrefix("/") else { continue }
            checkPath(path)
        }

        // Fallback: final .app in /Applications after extraction
        if largest == 0 {
            let (appOut, _) = shell("find /Applications -maxdepth 2 -name 'Install*.app' -type d 2>/dev/null | head -1")
            let appPath = appOut.trimmingCharacters(in: .whitespacesAndNewlines)
            if !appPath.isEmpty { checkPath(appPath) }
        }
        return largest
    }

    /// Track download progress using lsof to find the exact file softwareupdate
    /// is writing. The .partial file is buried 15+ levels deep in /private/var/folders
    /// so find with maxdepth never reaches it. lsof finds it instantly regardless of depth.
    private func installerDiskProgress(expectedBytes: Int64) -> Double? {
        guard expectedBytes > 0 else { return nil }

        var largestBytes: Int64 = 0

        // Primary: lsof to find the open .partial file, then du -sk for actual bytes
        // written (NOT stat -f%z which returns pre-allocated size immediately).
        // macOS pre-allocates the full file size on disk so stat shows 100% instantly.
        // du reports only actual blocks written — true download progress.
        let (lsofOut, _) = shell("lsof -c softwareupdate 2>/dev/null | awk '{print $NF}' | grep -E '.partial$|.pkg$|.dmg$' | head -5")
        for line in lsofOut.components(separatedBy: "\n") {
            let path = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, path.hasPrefix("/") else { continue }
            // Use du -sk (actual blocks written) not stat -f%z (pre-allocated size)
            let (sizeStr, _) = shell("du -sk \"\(path)\" 2>/dev/null | awk '{print $1}'")
            if let kb = Int64(sizeStr.trimmingCharacters(in: .whitespacesAndNewlines)), kb > 0 {
                let bytes = kb * 1024
                if bytes > largestBytes {
                    largestBytes = bytes
                    cliLog("[Install] Tracking \(kb / 1024) MB written at: \(path)")
                }
            }
        }

        // Fallback: check /Applications for the final .app after extraction completes
        if largestBytes == 0 {
            let (appOut, _) = shell("find /Applications -maxdepth 2 -name 'Install*.app' -type d 2>/dev/null | head -1")
            let appPath = appOut.trimmingCharacters(in: .whitespacesAndNewlines)
            if !appPath.isEmpty {
                let (sizeStr, _) = shell("du -sk \"\(appPath)\" 2>/dev/null | awk '{print $1}'")
                if let kb = Int64(sizeStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    largestBytes = kb * 1024
                }
            }
        }

        guard largestBytes > 0 else { return nil }
        return min(0.99, Double(largestBytes) / Double(expectedBytes))
    }

    /// Get expected download size from mdmclient AvailableOSUpdates output.
    private func getExpectedInstallerSize(version: String) -> Int64 {
        let (out, _) = shell("/usr/libexec/mdmclient AvailableOSUpdates 2>/dev/null")
        // Parse DownloadSize from the plist-style output for our target version
        var foundVersion = false
        for line in out.components(separatedBy: "\n") {
            if line.contains("Version = \"\(version)\"") || line.contains("Version = \(version)") {
                foundVersion = true
            }
            if foundVersion && line.contains("DownloadSize") {
                let nums = line.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .joined()
                if let size = Int64(nums), size > 1_000_000_000 {
                    cliLog("[Install] mdmclient reported DownloadSize: \(size)")
                    return size
                }
            }
            // Reset if we hit the next item
            if foundVersion && line.contains("ProductKey") && !line.contains(version) {
                foundVersion = false
            }
        }
        // Fallback: major upgrade is ~10GB, minor is ~2GB
        let major = Int(version.split(separator: ".").first ?? "0") ?? 0
        let current = Int(currentMacOSVersion().split(separator: ".").first ?? "0") ?? 0
        return major > current ? 10_737_418_240 : 2_684_354_560  // 10GB or 2.5GB
    }

    private func parseProgress(_ line: String) -> Double? {
        guard line.contains("%"),
              let regex = try? NSRegularExpression(pattern: #"(\d+\.?\d*)\s*%"#),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line),
              let value = Double(String(line[range]))
        else { return nil }
        return min(1.0, value / 100.0)
    }

    private func progressSubtitle(progress: Double, line: String, tool: String) -> String {
        let pct = String(format: "%.1f", progress * 100)
        let low = line.lowercased()

        // softwareupdate --fetch-full-installer outputs "Installing: 6.0%" (misleadingly named)
        // This is actually the download+prepare phase, not the OS install
        if low.contains("installing:") || low.contains("scanning") {
            return "Downloading macOS… \(pct)%"
        }
        if let regex = try? NSRegularExpression(pattern: #"([\d.]+\s*(?:GB|MB|KB))\s*\["#),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let r = Range(match.range(at: 1), in: line) {
            return "Downloading macOS… \(pct)% of \(String(line[r]).trimmingCharacters(in: .whitespaces))"
        }
        if low.contains("verif")  { return "Verifying… \(pct)%" }
        if low.contains("search") { return "Searching Apple servers…" }
        if pct == "0.0"           { return "Connecting to Apple servers…" }
        return "Downloading macOS… \(pct)%"
    }

    private func finishDownloadUI(success: Bool = true) {
        if success {
            try? "1.0\nDownload complete!"
                .write(toFile: "/private/var/run/com.push/download-progress", atomically: true, encoding: .utf8)
            Thread.sleep(forTimeInterval: 2.5)
        }
        shell("pkill -x push-ui 2>/dev/null || true")
        Thread.sleep(forTimeInterval: 0.3)
        try? FileManager.default.removeItem(atPath: "/private/var/run/com.push/download-progress")
    }

    // MARK: - startosinstall

    private func runStartOSInstall(installer: String, creds: InstallCredentials?,
                                    uiPath: String, cfgPath: String) {
        guard InstallerValidation.matches(installer, target: config.update.targetVersion) else {
            showError("Installer product version could not be verified for the requested macOS target.", uiPath: uiPath, cfgPath: cfgPath)
            return
        }
        // Assess the app before executing any code it contains; --usage is not a signature check.
        let (_, trusted) = runDirect("/usr/sbin/spctl", ["--assess", "--type", "execute", installer])
        guard trusted == 0 else {
            showError("The macOS installer did not pass Gatekeeper verification.", uiPath: uiPath, cfgPath: cfgPath)
            return
        }
        var arguments = ["--agreetolicense", "--forcequitapps"]
        if let creds { arguments += ["--user", creds.username, "--stdinpass"] }
        performInstaller(executable: installer + "/Contents/Resources/startosinstall", arguments: arguments,
                         creds: creds, uiPath: uiPath, cfgPath: cfgPath)
    }

    private func credentialsAreUsable(_ creds: InstallCredentials?, uiPath: String, cfgPath: String) -> Bool {
        guard isAppleSilicon() else { return true }
        guard let creds, !creds.username.isEmpty, !creds.password.isEmpty,
              creds.password.utf8.count <= 4096, !creds.password.contains("\n"), !creds.password.contains("\r"),
              verifyLocalPassword(account: creds.username, password: creds.password) else {
            showError("Valid authorization is required before installing macOS.", uiPath: uiPath, cfgPath: cfgPath); return false
        }
        let (status, code) = runDirect("/usr/sbin/sysadminctl", ["-secureTokenStatus", creds.username])
        guard code == 0, status.lowercased().contains("enabled") else {
            showError("The authorizing account needs Secure Token. Please contact IT.", uiPath: uiPath, cfgPath: cfgPath); return false
        }
        return true
    }

    private func performInstaller(executable: String, arguments: [String], creds: InstallCredentials?,
                                  uiPath: String, cfgPath: String) {
        var state = loadState()
        state.beginInstallation(target: config.update.targetVersion, running: currentMacOSVersion(), boot: currentBootTimestamp())
        do { try saveState(state) } catch {
            showError("Could not save installation state. Installation has not started.", uiPath: uiPath, cfgPath: cfgPath); return
        }
        let progressFile = "/private/var/run/com.push/install-progress"
        defer { try? FileManager.default.removeItem(atPath: progressFile) }
        var pendingOutput = ""
        let (_, exitCode) = runDirect(executable, arguments, input: creds.map { $0.password + "\n" }) { chunk in
            pendingOutput += chunk.replacingOccurrences(of: "\r", with: "\n")
            while let newline = pendingOutput.firstIndex(of: "\n") {
                let line = String(pendingOutput[..<newline])
                pendingOutput.removeSubrange(...newline)
                // Never log raw installer output, which may echo authorization details.
                if let progress = parseNativeProgress(line) {
                    try? "\(String(format: "%.3f", min(0.99, progress)))\nPreparing macOS installation…"
                        .write(toFile: progressFile, atomically: true, encoding: .utf8)
                }
            }
            if pendingOutput.count > 16384 { pendingOutput = String(pendingOutput.suffix(16384)) }
        }
        if exitCode == 0 {
            InstallRecoveryStore.staged(target:config.update.targetVersion)
            cliLog("[Install] Staging succeeded; awaiting post-reboot verification")
        } else {
            state.failInstallation()
            do { try saveState(state) } catch { cliLog("[Install] Failed to save retry state") }
            cliLog("[Install] Installer failed with exit status \(exitCode)")
            showError("macOS installation failed (exit \(exitCode)). Please retry or contact IT.", uiPath: uiPath, cfgPath: cfgPath)
        }
    }

    // MARK: - Helpers
    private func findExistingInstaller() -> String? {
        InstallerValidation.find(in: [managedBase + "/downloads", "/Applications"], target: config.update.targetVersion)
    }
    private func findInstallerInApplications() -> String? {
        InstallerValidation.find(in: ["/Applications"], target: config.update.targetVersion)
    }

    private func findMistCLI() -> String? {
        ["/usr/local/bin/mist", "/opt/homebrew/bin/mist"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Unified credential resolution for every install path.
    ///
    /// Runs selectAuthMethod, handles each case, and returns InstallCredentials
    /// carrying both the admin username (which may differ from console user when
    /// LAPS or a separate admin is used) and the password.
    ///
    /// LAPS fetch failures fall back through keychain → config; otherwise defer to IT instead
    /// of aborting — a transient Jamf outage should not brick the install.
    private func resolveInstallCredentials(uiPath: String, cfgPath: String,
                                           skipInitialPrompt: Bool,
                                           contextLabel: String) -> InstallCredentials? {
        let method = selectAuthMethod(config: config)
        cliLog("[Install] Auth method selected: \(method.rawValue) (\(contextLabel))")

        switch method {
        case .bootstrapToken:
            // Not reachable from install paths (allowBootstrapToken=false default),
            // but log it for completeness if it ever is.
            cliLog("[Install] Bootstrap Token branch hit from install path — unexpected")
            return nil

        case .laps:
            do {
                let result = try JamfLAPSClient(config: config).fetchPassword()
                cliLog("[Install] LAPS fetch succeeded for account: \(result.username)")
                return InstallCredentials(username: result.username, password: result.password)
            } catch {
                cliLog("[Install] LAPS fetch failed: \(error) — falling back to keychain/config")
                return resolveInstallCredentialsFallback(uiPath: uiPath, cfgPath: cfgPath,
                                                         skipInitialPrompt: skipInitialPrompt)
            }

        case .keychain:
            guard let pwd = keychainPassword(), !pwd.isEmpty else {
                cliLog("[Install] Keychain reported present but empty — falling back")
                return resolveInstallCredentialsFallback(uiPath: uiPath, cfgPath: cfgPath,
                                                         skipInitialPrompt: skipInitialPrompt)
            }
            let account = credentialAccountName()
            cliLog("[Install] Using System Keychain password for account: \(account)")
            return InstallCredentials(username: account, password: pwd)

        case .config:
            let account = credentialAccountName()
            cliLog("[Install] Using config file password for account: \(account) (plain text — consider keychain or LAPS)")
            return InstallCredentials(username: account, password: config.auth.localPassword)

        case .unavailable:
            cliLog("[Install] No unattended authorization is available; leaving installation unstarted for IT")
            return nil
        }
    }

    /// Runs the remaining chain (keychain → config; otherwise defer to IT) when LAPS fails.
    private func resolveInstallCredentialsFallback(uiPath: String, cfgPath: String,
                                                    skipInitialPrompt: Bool) -> InstallCredentials? {
        let account = credentialAccountName()
        if !account.isEmpty, let pwd = keychainPassword(), !pwd.isEmpty {
            cliLog("[Install] Fallback: using System Keychain password for \(account)")
            return InstallCredentials(username: account, password: pwd)
        }
        if !account.isEmpty && !config.auth.localPassword.isEmpty {
            cliLog("[Install] Fallback: using config file password for \(account)")
            return InstallCredentials(username: account, password: config.auth.localPassword)
        }
        cliLog("[Install] No managed credentials are available; user password prompts are disabled")
        return nil
    }

    /// Picks the admin account name for non-LAPS paths.
    /// Requires an IT-configured account; never assumes the console user.
    private func credentialAccountName() -> String {
        if !config.auth.localAccount.isEmpty { return config.auth.localAccount }
        return ""
    }

    private func showError(_ message: String, uiPath: String, cfgPath: String) {
        RuntimeHealthScope.note(message,error:true)
        InstallRecoveryStore.failure(config:config,message:message)
        cliLog("[Install] Error: \(message)")
        shell("pkill -x push-ui 2>/dev/null || true"); Thread.sleep(forTimeInterval: 0.3)
        launchUIAsUser("\"\(uiPath)\" --state error --config \"\(cfgPath)\" --error \(shellArgument(message))")
    }
}
