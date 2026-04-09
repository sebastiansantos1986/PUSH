// InstallCommand.swift — Full macOS install workflow
//
// Download chain:
//   1. Native pending update check (softwareupdate --list, Action: restart)
//   2. softwareupdate --fetch-full-installer
//   3. mist-cli fallback
//
// Restart flow: user-friendly prompt → preflight → download → install → reboot

import Foundation

struct InstallWorkflow {
    let config: CLIConfig
    // Set true when called from AutoCheck after user already clicked Install —
    // avoids showing a second confirmation popup.
    var skipInitialPrompt: Bool = false

    func run() {
        let isDebug = config.debug.dryRun
        cliLog("[Install] Starting for \(config.update.targetVersion)\(isDebug ? " (dry-run)" : "")")

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

        if isDebug {
            cliSuccess("DEBUG — installer ready: \(installer). Skipping install.")
            return
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
        var currentLabel = ""
        for line in output.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("* Label:") {
                currentLabel = t.replacingOccurrences(of: "* Label:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if t.contains("Version: \(version)")
                       && t.lowercased().contains("action: restart")
                       && !currentLabel.isEmpty {
                return currentLabel
            }
        }
        return nil
    }

    private func installNativePendingUpdate(label: String, uiPath: String, cfgPath: String) {
        shell("pkill -x push-ui 2>/dev/null || true")
        Thread.sleep(forTimeInterval: 0.3)

        let status = runUIBlocking("\"\(uiPath)\" --state softNudge --config \"\(cfgPath)\" --deferrals 0")
        guard Int(status) == 0 else {
            cliLog("[Install] User deferred native update")
            return
        }

        // Prompt for password before showing installing UI
        var password: String? = nil
        if isAppleSilicon() && config.update.requirePasswordOnAppleSilicon {
            if let kwdPwd = keychainPassword(), !kwdPwd.isEmpty {
                cliLog("[Install] Using password from System Keychain (native path)")
                password = kwdPwd
            } else if !config.auth.localPassword.isEmpty {
                password = config.auth.localPassword
            } else {
                password = promptPassword(uiPath: uiPath, cfgPath: cfgPath)
                if password == nil { cliLog("[Install] Password cancelled (native path)"); exit(2) }
            }
        }

        guard let user = consoleUser() else {
            cliLog("[Install] No console user found — cannot trigger native update")
            return
        }

        launchUIAsUser("\"\(uiPath)\" --state installing --config \"\(cfgPath)\" --quick-restart")
        Thread.sleep(forTimeInterval: 2.0)

        var state = loadState(); state.installStarted = true; try? saveState(state)

        // Stream softwareupdate output so the UI can show real download progress.
        // Uses super's exact pattern for macOS 13+ Apple Silicon:
        //   echo pwd | launchctl asuser <uid> sudo -u root softwareupdate --install ... --user <acct> --stdinpass
        // --force is required — without it softwareupdate ignores queued updates.
        streamNativeInstall(label: label, password: password, user: user)
    }

    private func streamNativeInstall(label: String, password: String?, user: (name: String, uid: Int)) {
        let progressFile = "/tmp/push-install-progress"
        let logFile      = "/tmp/push-native-install.log"
        let doneFile     = "/tmp/push-native-done.flag"
        let wrapperPath  = "/tmp/push-native-wrapper.sh"

        shell("rm -f \"\(logFile)\" \"\(doneFile)\" \"\(wrapperPath)\" 2>/dev/null; true")
        shell("touch \"\(logFile)\"; chmod 666 \"\(logFile)\"")

        // Build the install command matching super's macOS 13+ Apple Silicon pattern
        let installCmd: String
        if let pwd = password {
            cliLog("[Install] Passing credentials for user: \(user.name) (native path)")
            installCmd = "echo \"\(pwd)\" | launchctl asuser \(user.uid) sudo -u root softwareupdate --install \"\(label)\" --restart --force --no-scan --agree-to-license --user \"\(user.name)\" --stdinpass"
        } else {
            // Intel or password not required
            installCmd = "launchctl asuser \(user.uid) sudo -u root softwareupdate --install \"\(label)\" --restart --force --no-scan --agree-to-license"
        }

        let wrapper = """
#!/bin/bash
\(installCmd) 2>&1 | tr '\\r' '\\n' | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "$line" >> "\(logFile)"
done
TOOL_EXIT=${PIPESTATUS[0]}
echo "EXIT_CODE:$TOOL_EXIT" >> "\(logFile)"
echo "DONE" > "\(doneFile)"
"""
        do { try wrapper.write(toFile: wrapperPath, atomically: true, encoding: .utf8) }
        catch { cliLog("[Install] Cannot write wrapper: \(error)"); return }
        shell("chmod +x \"\(wrapperPath)\"")

        let process = Process()
        process.launchPath          = "/bin/zsh"
        process.arguments           = ["-c", wrapperPath]
        process.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
        do { try process.run() }
        catch { cliLog("[Install] Cannot launch native install: \(error)"); return }

        var processedLines = 0
        while process.isRunning || !FileManager.default.fileExists(atPath: doneFile) {
            Thread.sleep(forTimeInterval: 1.5)
            guard let raw = try? String(contentsOfFile: logFile, encoding: .utf8) else { continue }
            let lines    = raw.components(separatedBy: "\n").filter { !$0.isEmpty }
            let newLines = Array(lines.dropFirst(processedLines))
            processedLines = lines.count

            for line in newLines {
                cliLog("[softwareupdate] \(line)")
                // Parse "Downloading macOS Tahoe 26.4: 50.65%" or "Downloading: 50.65%"
                if let pct = parseNativeProgress(line) {
                    let subtitle: String
                    if line.lowercased().contains("download") {
                        subtitle = "Downloading macOS… \(String(format: "%.1f", pct * 100))%"
                    } else if line.lowercased().contains("install") || line.lowercased().contains("preparing") {
                        subtitle = "Preparing installation…"
                    } else {
                        subtitle = "\(String(format: "%.1f", pct * 100))% complete"
                    }
                    try? "\(String(format: "%.3f", pct))\n\(subtitle)"
                        .write(toFile: progressFile, atomically: true, encoding: .utf8)
                }
            }
            if FileManager.default.fileExists(atPath: doneFile) { break }
        }
        process.waitUntilExit()

        let finalLog = (try? String(contentsOfFile: logFile, encoding: .utf8)) ?? ""
        if finalLog.contains("EXIT_CODE:0") {
            cliLog("[Install] Native softwareupdate completed — restart initiated")
        } else {
            cliLog("[Install] Native softwareupdate may have failed. Last lines:\n\(finalLog.components(separatedBy: "\n").suffix(10).joined(separator: "\n"))")
        }
        shell("rm -f \"\(wrapperPath)\" \"\(doneFile)\" 2>/dev/null; true")
        try? FileManager.default.removeItem(atPath: progressFile)
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

        var password: String? = nil
        cliLog("[Install] isAppleSilicon=\(isAppleSilicon()) requirePasswordOnAppleSilicon=\(config.update.requirePasswordOnAppleSilicon)")
        if isAppleSilicon() && config.update.requirePasswordOnAppleSilicon {
            // Priority: 1) System Keychain  2) config.yaml auth.localPassword  3) prompt user
            if let kwdPwd = keychainPassword(), !kwdPwd.isEmpty {
                cliLog("[Install] Using password from System Keychain")
                password = kwdPwd
            } else if !config.auth.localPassword.isEmpty {
                cliLog("[Install] Using password from config (warning: stored in plain text)")
                password = config.auth.localPassword
            } else {
                cliLog("[Install] No stored credentials — prompting user")
                password = promptPassword(uiPath: uiPath, cfgPath: cfgPath)
                if password == nil { cliLog("[Install] Password cancelled"); exit(2) }
            }
        }

        shell("pkill -x push-ui 2>/dev/null || true")
        Thread.sleep(forTimeInterval: 0.3)
        launchUIAsUser("\"\(uiPath)\" --state installing --config \"\(cfgPath)\"")
        Thread.sleep(forTimeInterval: 2.0)

        runStartOSInstall(installer: installer, password: password,
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
                .write(toFile: "/tmp/push-download-progress", atomically: true, encoding: .utf8)

            let mistOK = streamDownload(
                cmd:  "\"\(mist)\" download installer \"\(version)\" application --output-directory \"/Applications\" --compatible --force --no-ansi",
                tool: "mist-cli"
            )
            if mistOK, let found = findInstallerInApplications() {
                cliLog("[Install] mist-cli succeeded: \(found)")
                finishDownloadUI()
                return found
            }
            cliLog("[Install] mist-cli failed — falling back to softwareupdate")
            try? "0.01\nSwitching to alternate download method…"
                .write(toFile: "/tmp/push-download-progress", atomically: true, encoding: .utf8)
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
                .write(toFile: "/tmp/push-download-progress", atomically: true, encoding: .utf8)
        }

        cliLog("[Install] Using softwareupdate --fetch-full-installer \(version)")
        let swuOK = streamDownload(
            cmd:  "softwareupdate --fetch-full-installer --full-installer-version \"\(version)\"",
            tool: "softwareupdate"
        )
        if swuOK, let found = findInstallerInApplications() {
            cliLog("[Install] softwareupdate succeeded: \(found)")
            finishDownloadUI()
            return found
        }
        cliLog("[Install] softwareupdate failed — trying mist-cli as last resort")

        try? "0.01\nSwitching to alternate download method…"
            .write(toFile: "/tmp/push-download-progress", atomically: true, encoding: .utf8)
        Thread.sleep(forTimeInterval: 1.5)

        // Last resort: mist-cli for minor updates if softwareupdate also failed
        guard let mist = findMistCLI() else {
            cliLog("[Install] mist-cli not found — all methods exhausted")
            finishDownloadUI(success: false)
            return nil
        }
        cliLog("[Install] Last resort — mist-cli at \(mist)")
        let mistOK2 = streamDownload(
            cmd:  "\"\(mist)\" download installer \"\(version)\" application --output-directory \"/Applications\" --compatible --force --no-ansi",
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
    private func streamDownload(cmd: String, tool: String) -> Bool {
        let logFile     = "/tmp/push-dl-progress.log"
        let doneFile    = "/tmp/push-dl-done.flag"
        let wrapperPath = "/tmp/push-dl-wrapper.sh"

        shell("rm -f \"\(logFile)\" \"\(doneFile)\" \"\(wrapperPath)\" 2>/dev/null; true")
        shell("touch \"\(logFile)\"; chmod 666 \"\(logFile)\"")

        // For softwareupdate --fetch-full-installer: run directly without a pipe.
        // It needs a TTY to output progress, and piping destroys that.
        // We track progress via disk polling instead (installerDiskProgress).
        // For mist-cli: pipe works fine since mist outputs progress without a TTY.
        let isSWU = tool == "softwareupdate"
        let wrapper: String
        if isSWU {
            // softwareupdate outputs "Installing: X%" only when stdout is a file, not a pipe.
            // Redirecting directly to logFile preserves that output.
            // sed converts \r to \n so percentages appear on separate lines for parsing.
            wrapper = """
#!/bin/bash
\(cmd) >> "\(logFile)" 2>&1
# Convert carriage returns to newlines so parser can read individual % lines
sed -i \'\' \'s/\\r/\\n/g\' "\(logFile)" 2>/dev/null || true
TOOL_EXIT=$?
echo "EXIT_CODE:$TOOL_EXIT" >> "\(logFile)"
echo "DONE" > "\(doneFile)"
"""
        } else {
            wrapper = """
#!/bin/bash
\(cmd) 2>&1 | tr '\r' '\n' | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "$line" >> "\(logFile)"
done
TOOL_EXIT=${PIPESTATUS[0]}
echo "EXIT_CODE:$TOOL_EXIT" >> "\(logFile)"
echo "DONE" > "\(doneFile)"
"""
        }
        do { try wrapper.write(toFile: wrapperPath, atomically: true, encoding: .utf8) }
        catch { cliLog("[Install] Cannot write wrapper: \(error)"); return false }
        shell("chmod +x \"\(wrapperPath)\"")

        // Get expected installer size from mdmclient so we can show disk-based progress.
        // softwareupdate --fetch-full-installer outputs nothing to stdout during download,
        // so we track the growing .app bundle on disk instead.
        let expectedBytes = getExpectedInstallerSize(version: config.update.targetVersion)
        cliLog("[Install] Expected installer size: \(expectedBytes > 0 ? "\(expectedBytes / 1_073_741_824) GB" : "unknown")")

        let process = Process()
        process.launchPath          = "/bin/bash"
        process.arguments           = [wrapperPath]
        process.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
        do { try process.run() }
        catch { cliLog("[Install] Cannot launch \(tool): \(error)"); return false }

        var lastProgress    = 0.0
        var processedLines  = 0
        var pulseTick       = 0
        var dynamicExpected = expectedBytes  // expands if file exceeds initial estimate
        var lastFileBytes   = Int64(0)
        var plateauTicks    = 0              // tracks how long progress is near the cap

        while process.isRunning || !FileManager.default.fileExists(atPath: doneFile) {
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
                        .write(toFile: "/tmp/push-download-progress", atomically: true, encoding: .utf8)
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
                        .write(toFile: "/tmp/push-download-progress", atomically: true, encoding: .utf8)
                    cliLog("[Install] Progress: \(pct)% (\(mbDone) MB / \(dynamicExpected / 1_048_576) MB expected)")

                } else if lastProgress < 0.01 {
                    pulseTick += 1
                    let pulseVal = 0.02 + 0.02 * Double(pulseTick % 8)
                    let dots = String(repeating: ".", count: (pulseTick % 3) + 1)
                    try? "\(String(format: "%.3f", pulseVal))\nConnecting to Apple servers\(dots)"
                        .write(toFile: "/tmp/push-download-progress", atomically: true, encoding: .utf8)
                } else {
                    let pct = String(format: "%.1f", lastProgress * 100)
                    try? "\(String(format: "%.3f", lastProgress))\nDownloading macOS… \(pct)%"
                        .write(toFile: "/tmp/push-download-progress", atomically: true, encoding: .utf8)
                }
            }

            if FileManager.default.fileExists(atPath: doneFile) { break }
        }
        process.waitUntilExit()
        shell("rm -f \"\(wrapperPath)\" \"\(doneFile)\" 2>/dev/null; true")

        let finalLog = (try? String(contentsOfFile: logFile, encoding: .utf8)) ?? ""
        let success  = finalLog.contains("EXIT_CODE:0")
        if !success {
            cliLog("[Install] \(tool) FAILED. Last lines:\n\(finalLog.components(separatedBy: "\n").suffix(10).joined(separator: "\n"))")
        }
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
                .write(toFile: "/tmp/push-download-progress", atomically: true, encoding: .utf8)
            Thread.sleep(forTimeInterval: 2.5)
        }
        shell("pkill -x push-ui 2>/dev/null || true")
        Thread.sleep(forTimeInterval: 0.3)
        try? FileManager.default.removeItem(atPath: "/tmp/push-download-progress")
    }

    // MARK: - startosinstall

    private func runStartOSInstall(installer: String, password: String?,
                                    uiPath: String, cfgPath: String) {
        let startosinstall = "\(installer)/Contents/Resources/startosinstall"
        guard FileManager.default.fileExists(atPath: startosinstall) else {
            showError("startosinstall not found inside \(installer).",
                      uiPath: uiPath, cfgPath: cfgPath)
            exit(1)
        }

        // Validate the installer with Gatekeeper before prompting for password.
        // Catches corrupt downloads before we commit to the install.
        cliLog("[Install] Validating installer with Gatekeeper...")
        let (usageOut, usageStatus) = shell("\"\(startosinstall)\" --usage 2>&1")
        guard usageStatus == 0 || usageOut.lowercased().contains("usage: startosinstall") else {
            cliLog("[Install] Installer validation failed: \(usageOut)")
            showError("The macOS installer appears to be corrupt. It will be removed so it can be re-downloaded next time.",
                      uiPath: uiPath, cfgPath: cfgPath)
            // Remove corrupt installer so next run re-downloads
            shell("rm -rf \"\(installer)\" 2>/dev/null; true")
            exit(1)
        }
        cliLog("[Install] Installer validated OK")

        // --forcequitapps forces open apps to quit so the install isn't stalled.
        var cmd = "\"\(startosinstall)\" --agreetolicense --forcequitapps"
        // Apple Silicon requires --user + --stdinpass together; without --user the
        // password is silently ignored and startosinstall exits without installing.
        if let pwd = password, let user = consoleUser() {
            cliLog("[Install] Passing credentials for user: \(user.name)")
            // Use double-quote herestring — single quotes break on passwords containing '
            cmd += " --user \"\(user.name)\" --stdinpass <<<\"\(pwd)\""
        } else if password != nil {
            cliLog("[Install] Warning: password collected but no console user found — skipping --stdinpass")
        }

        var state = loadState(); state.installStarted = true; try? saveState(state)
        cliLog("[Install] Running startosinstall — machine will reboot when done")

        // Write initial value immediately so UI bar starts near 0, not at fake 55%
        let progressFile = "/tmp/push-install-progress"
        try? "0.01\nPreparing macOS upgrade…"
            .write(toFile: progressFile, atomically: true, encoding: .utf8)

        // Combine time-based simulated progress + real startosinstall "Preparing: X%".
        // startosinstall stalls at ~1% for most of the run so we simulate smooth
        // progress over 15 min and use real data when it exceeds the simulation.
        let logFile        = "/tmp/push-startosinstall.log"
        let doneFlag       = "/tmp/push-startosinstall-done.flag"
        let wrapper        = "/tmp/push-startosinstall-wrapper.sh"
        let expectedSecs   = 15.0 * 60.0  // 15 minutes expected
        let startTime      = Date()

        let script = """
#!/bin/bash
\(cmd) 2>&1 | tr '\r' '\n' | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "$line" >> "\(logFile)"
done
TOOL_EXIT=${PIPESTATUS[0]}
echo "EXIT_CODE:$TOOL_EXIT" >> "\(logFile)"
echo "DONE" > "\(doneFlag)"
"""
        shell("rm -f \"\(logFile)\" \"\(doneFlag)\" \"\(wrapper)\" 2>/dev/null; true")
        do { try script.write(toFile: wrapper, atomically: true, encoding: .utf8) } catch {}
        shell("chmod +x \"\(wrapper)\"")

        let proc = Process()
        proc.launchPath = "/bin/zsh"
        proc.arguments  = ["-c", wrapper]
        try? proc.run()

        var lastPct = 0.0
        while proc.isRunning || !FileManager.default.fileExists(atPath: doneFlag) {
            Thread.sleep(forTimeInterval: 3.0)

            // Time-based simulation: 0→92% over 15 min, eased so it feels natural
            let elapsed  = Date().timeIntervalSince(startTime)
            let timePct  = min(0.92, elapsed / expectedSecs)

            // Real progress from startosinstall output
            var realPct = 0.0
            if let raw = try? String(contentsOfFile: logFile, encoding: .utf8) {
                for line in raw.components(separatedBy: CharacterSet(charactersIn: "\r\n")) {
                    let t = line.trimmingCharacters(in: .whitespaces).lowercased()
                    if (t.contains("preparing") || t.contains("percent")) && t.contains("%") {
                        if let regex = try? NSRegularExpression(pattern: #"(\d+\.?\d*)\s*%"#),
                           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                           let r = Range(match.range(at: 1), in: line),
                           let pct = Double(String(line[r])) {
                            realPct = max(realPct, min(0.99, pct / 100.0))
                        }
                    }
                    if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                        cliLog("[startosinstall] \(line)")
                    }
                }
            }

            // Use highest of: simulated time, real data, or last known value
            let progress = max(timePct, realPct, lastPct)
            lastPct = progress

            // Countdown subtitle
            let minsLeft = max(1, Int(ceil((expectedSecs - elapsed) / 60.0)))
            let subtitle: String
            if elapsed < expectedSecs {
                subtitle = "Your Mac will restart in ~\(minsLeft) minute\(minsLeft == 1 ? "" : "s")"
            } else {
                subtitle = "Almost done — do not shut down your Mac"
            }

            try? "\(String(format: "%.3f", lastPct))\n\(subtitle)"
                .write(toFile: progressFile, atomically: true, encoding: .utf8)
        }
        proc.waitUntilExit()
        shell("rm -f \"\(wrapper)\" \"\(doneFlag)\" 2>/dev/null; true")
        try? FileManager.default.removeItem(atPath: progressFile)

        // Check exit code — if startosinstall failed, show error instead of freezing
        let finalLog = (try? String(contentsOfFile: logFile, encoding: .utf8)) ?? ""
        let succeeded = finalLog.contains("EXIT_CODE:0")
            || finalLog.lowercased().contains("install finished successfully")
            || finalLog.lowercased().contains("preparing reboot")

        if succeeded {
            state.installCompleted = true; try? saveState(state)
            NotificationManager(config: config).notifyInstallComplete(
                version: config.update.targetVersion,
                previousVersion: currentMacOSVersion()
            )
            // Trigger Jamf recon post-install so EA updates immediately after reboot
            if !config.jamf.binaryPath.isEmpty,
               FileManager.default.fileExists(atPath: config.jamf.binaryPath) {
                cliLog("[Install] Triggering jamf recon post-install")
                shell("\"\(config.jamf.binaryPath)\" recon 2>/dev/null")
            }
        } else {
            cliLog("[Install] startosinstall may have failed. Log tail:\n\(finalLog.components(separatedBy: "\n").suffix(15).joined(separator: "\n"))")
            shell("pkill -x push-ui 2>/dev/null || true")
            Thread.sleep(forTimeInterval: 0.3)

            // Parse a useful error from the log
            var reason = "Installation failed. Please try again or contact IT support."
            for line in finalLog.components(separatedBy: "\n").reversed() {
                let t = line.trimmingCharacters(in: .whitespaces).lowercased()
                if t.contains("error") || t.contains("fail") || t.contains("denied") {
                    reason = line.trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            showError(reason, uiPath: uiPath, cfgPath: cfgPath)
            // Reset installStarted so user can try again
            state.installStarted = false; try? saveState(state)
        }
        shell("rm -f \"\(logFile)\" 2>/dev/null; true")
    }

    // MARK: - Helpers

    private func findExistingInstaller() -> String? {
        for dir in ["\(managedBase)/downloads", "/Applications"] {
            let (f, _) = shell("find \"\(dir)\" -maxdepth 3 -name 'Install*.app' -type d 2>/dev/null | grep -i 'macos\\|os x' | head -1")
            if !f.isEmpty && FileManager.default.fileExists(atPath: f) { return f }
        }
        return nil
    }

    private func findInstallerInApplications() -> String? {
        let (a, _) = shell("find /Applications -maxdepth 2 -name 'Install macOS*.app' -type d 2>/dev/null | head -1")
        if !a.isEmpty { return a }
        let (b, _) = shell("find /Applications -maxdepth 2 -name 'Install*.app' -type d 2>/dev/null | grep -i macos | head -1")
        return b.isEmpty ? nil : b
    }

    private func findMistCLI() -> String? {
        ["/usr/local/bin/mist", "/opt/homebrew/bin/mist"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    private func promptPassword(uiPath: String, cfgPath: String) -> String? {
        shell("pkill -x push-ui 2>/dev/null || true"); Thread.sleep(forTimeInterval: 0.3)
        let status = runUIBlocking("\"\(uiPath)\" --state passwordPrompt --config \"\(cfgPath)\"")
        guard status == 0 else { return nil }
        let pwdPath = "/tmp/push-password"
        // Use defer so the plaintext file is always removed — even if reading fails.
        defer { try? FileManager.default.removeItem(atPath: pwdPath) }
        guard let pwd = try? String(contentsOfFile: pwdPath, encoding: .utf8) else { return nil }
        return pwd.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func showError(_ message: String, uiPath: String, cfgPath: String) {
        cliLog("[Install] Error: \(message)")
        shell("pkill -x push-ui 2>/dev/null || true"); Thread.sleep(forTimeInterval: 0.3)
        launchUIAsUser("\"\(uiPath)\" --state error --config \"\(cfgPath)\" --error \"\(message)\"")
    }
}
