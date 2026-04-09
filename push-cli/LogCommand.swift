// LogCommand.swift — Log management, LaunchDaemon install/uninstall

import Foundation

// MARK: - Log

struct LogCommand {
    let args: [String]

    func run() {
        guard let sub = args.first else {
            cliError("Usage: push-cli log <show|tail|clear>"); exit(1)
        }
        switch sub {
        case "show":  showLog()
        case "tail":  tailLog()
        case "clear": clearLog()
        default:
            cliError("Unknown log subcommand '\(sub)'"); exit(1)
        }
    }

    private func showLog() {
        let lines = Int(argValue("--lines", in: args) ?? "50") ?? 50
        guard FileManager.default.fileExists(atPath: logPath) else {
            cliPrint("(no log file found at \(logPath))"); return
        }
        let (output, _) = shell("tail -n \(lines) \"\(logPath)\"")
        cliPrint(output)
    }

    private func tailLog() {
        if !FileManager.default.fileExists(atPath: logPath) {
            cliPrint("(no log file yet — waiting for first run)")
        }
        cliPrint("Tailing \(logPath)… (Ctrl+C to stop)\n")
        shell("tail -f \"\(logPath)\"")
    }

    private func clearLog() {
        guard getuid() == 0 else {
            cliError("log clear requires root. Run: sudo push-cli log clear"); exit(1)
        }
        do {
            try "".write(toFile: logPath, atomically: true, encoding: .utf8)
            cliSuccess("Log cleared: \(logPath)")
        } catch {
            cliError("Failed to clear log: \(error.localizedDescription)"); exit(1)
        }
    }
}

// MARK: - Install daemon

struct InstallDaemonCommand {
    let args: [String]

    let plistPath = "/Library/LaunchDaemons/com.push.autoupdate.plist"
    let label     = "com.push.autoupdate"

    func run() {
        guard getuid() == 0 else {
            cliError("install-daemon requires root. Run: sudo push-cli install-daemon"); exit(1)
        }

        let intervalStr = argValue("--interval", in: args) ?? "1h"
        let interval    = parseInterval(intervalStr)
        let binary      = resolvedBinaryPath()

        // Create managed directory structure
        let dirs = [
            managedBase,
            "\(managedBase)/logs",
            "\(managedBase)/downloads",
        ]
        for dir in dirs {
            try? FileManager.default.createDirectory(atPath: dir,
                                                      withIntermediateDirectories: true)
        }

        let plist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>\(label)</string>
    <key>ProgramArguments</key>
    <array>
        <string>\(binary)</string>
        <string>auto-check</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>\(interval)</integer>
    <key>StandardOutPath</key>
    <string>\(managedBase)/logs/push-cli.log</string>
    <key>StandardErrorPath</key>
    <string>\(managedBase)/logs/push-cli.log</string>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
"""
        do {
            try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
            shell("chown root:wheel \"\(plistPath)\"")
            shell("chmod 644 \"\(plistPath)\"")
            // Use bootstrap (replaces deprecated launchctl load)
            shell("launchctl bootout system \"\(plistPath)\" 2>/dev/null || true")
            let (_, status) = shell("launchctl bootstrap system \"\(plistPath)\"")

            // Create symlink in /usr/local/bin for convenience
            shell("ln -sf \"\(binary)\" /usr/local/bin/push-cli 2>/dev/null || true")

            if status == 0 {
                cliSuccess("LaunchDaemon installed — runs every \(formatInterval(interval))")
                cliPrint("")
                cliInfo("Label:",    label)
                cliInfo("Binary:",   binary)
                cliInfo("Interval:", formatInterval(interval))
                cliInfo("Plist:",    plistPath)
                cliInfo("Symlink:",  "/usr/local/bin/push-cli")
                cliPrint("")
                cliPrint("Run 'push-cli status' to verify.")
                cliPrint("Run 'sudo push-cli uninstall-daemon' to remove.")
            } else {
                cliError("launchctl load failed. Check: sudo launchctl error \(status)")
                exit(1)
            }
        } catch {
            cliError("Failed to write plist: \(error.localizedDescription)"); exit(1)
        }
    }

    private func resolvedBinaryPath() -> String {
        // Always use the canonical managed path in the plist.
        // Never use the symlink (/usr/local/bin/push-cli) — the LaunchDaemon
        // runs with a restricted PATH that doesn't include /usr/local/bin.
        let canonical = "\(managedBase)/push-cli"
        if FileManager.default.fileExists(atPath: canonical) { return canonical }
        // Fallback: use argv[0] if it's a full absolute path and not a symlink
        let arg0 = CommandLine.arguments[0]
        if arg0.hasPrefix("/") && !arg0.contains("/usr/local/bin") { return arg0 }
        return canonical
    }

    private func parseInterval(_ s: String) -> Int {
        let validHours = [1, 2, 4, 8, 12, 24]
        if s.hasSuffix("h"), let n = Int(s.dropLast()) {
            guard validHours.contains(n) else {
                cliError("Invalid interval '\(s)'. Valid options: 1h, 2h, 4h, 8h, 12h, 24h")
                exit(1)
            }
            return n * 3600
        }
        // Minutes — allowed for testing only (minimum 1m)
        if s.hasSuffix("m"), let n = Int(s.dropLast()), n >= 1 {
            if n < 5 { cliWarning("Interval \(n)m is very short — remember to reset before fleet deployment") }
            return n * 60
        }
        if s.hasSuffix("d"), let n = Int(s.dropLast()), n >= 1 { return n * 86400 }
        if let n = Int(s), n >= 60 { return n }
        cliError("Invalid interval '\(s)'. Use: 1m, 5m, 30m, 1h, 2h, 4h, 8h, 12h, 24h")
        exit(1)
    }
}

// MARK: - Uninstall daemon

struct UninstallDaemonCommand {
    let args: [String]
    let plistPath = "/Library/LaunchDaemons/com.push.autoupdate.plist"

    func run() {
        guard getuid() == 0 else {
            cliError("uninstall-daemon requires root. Run: sudo push-cli uninstall-daemon"); exit(1)
        }

        shell("launchctl bootout system \"\(plistPath)\" 2>/dev/null || true")

        var removed: [String] = []
        if FileManager.default.fileExists(atPath: plistPath) {
            try? FileManager.default.removeItem(atPath: plistPath)
            removed.append("LaunchDaemon plist")
        }

        // Remove symlink if it points to push-cli
        let symlink = "/usr/local/bin/push-cli"
        if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: symlink),
           dest.contains("push-cli") {
            try? FileManager.default.removeItem(atPath: symlink)
            removed.append("/usr/local/bin/push-cli symlink")
        }

        if removed.isEmpty {
            cliPrint("Nothing to remove — LaunchDaemon was not installed.")
        } else {
            cliSuccess("Removed: \(removed.joined(separator: ", "))")
            cliPrint("PUSH will no longer run automatically.")
            cliPrint("Config and state files in \(managedBase) are preserved.")
        }
    }
}

// MARK: - Debug command

struct DebugCommand {
    let args: [String]

    func run() {
        guard let sub = args.first else {
            cliError("Usage: push-cli debug <on|off|status>"); exit(1)
        }
        switch sub {
        case "on":     setDryRun(true)
        case "off":    setDryRun(false)
        case "status": showDebugStatus()
        default:
            cliError("Unknown debug subcommand '\(sub)'"); exit(1)
        }
    }

    private func setDryRun(_ on: Bool) {
        guard getuid() == 0 else {
            cliError("Requires root: sudo push-cli debug \(on ? "on" : "off")"); exit(1)
        }
        guard let cfgPath = resolvedConfigPath,
              var yaml = try? String(contentsOfFile: cfgPath, encoding: .utf8) else {
            cliError("Cannot load config"); exit(1)
        }

        let pattern = "^(\\s*dryRun:).*$"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) {
            yaml = regex.stringByReplacingMatches(
                in: yaml, range: NSRange(yaml.startIndex..., in: yaml),
                withTemplate: "$1 \(on)")
        }

        do {
            try yaml.write(toFile: cfgPath, atomically: true, encoding: .utf8)
            if on {
                cliSuccess("Debug mode ON — Install will download but NOT run startosinstall")
                cliWarning("Remember to run 'sudo push-cli debug off' before production deployment")
            } else {
                cliSuccess("Debug mode OFF — Install will run startosinstall and reboot")
            }
        } catch {
            cliError("Failed: \(error.localizedDescription)"); exit(1)
        }
    }

    private func showDebugStatus() {
        guard let config = try? loadConfig() else {
            cliError("Cannot load config"); exit(1)
        }
        cliSection("Debug Status")
        cliDivider()
        cliInfo("dryRun:", config.debug.dryRun
            ? "\u{001B}[33mON — download only\u{001B}[0m"
            : "\u{001B}[32mOFF — full install\u{001B}[0m")
        if config.debug.testToastIntervalMinutes > 0 {
            cliInfo("Toast interval:", "\(config.debug.testToastIntervalMinutes) min (test mode)")
        }
        if config.debug.testNudgeIntervalMinutes > 0 {
            cliInfo("Nudge interval:", "\(config.debug.testNudgeIntervalMinutes) min (test mode)")
        }
        cliPrint("")
    }
}
