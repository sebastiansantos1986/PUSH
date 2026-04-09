// ReportCommand.swift — Compliance report, grace period, log rotation

import Foundation

// MARK: - Report command

struct ReportCommand {
    let args: [String]

    var formatJSON: Bool { args.contains("--json") }
    var formatCSV:  Bool { args.contains("--csv")  }

    func run() {
        let config    = (try? loadConfig()) ?? CLIConfig()
        let state     = loadState()
        let current   = currentMacOSVersion()
        let target    = config.update.targetVersion
        let compliant = target.isEmpty ? true : versionGTE(current, target)
        let host      = friendlyHostname()
        let serial    = machineSerial()

        // Grace period active?
        let graceActive = state.gracePeriodUntil.map { $0 > Date() } ?? false

        let report: [String: Any] = [
            "hostname":        host,
            "serial":          serial,
            "currentOS":       current,
            "targetOS":        target,
            "compliant":       compliant,
            "releaseType":     config.update.releaseType,
            "deferralCount":   state.deferralCount,
            "maxDeferrals":    config.update.maxDeferrals,
            "deadline":        config.update.deadline,
            "pastDeadline":    config.isPastDeadline,
            "gracePeriodActive": graceActive,
            "gracePeriodUntil":  state.gracePeriodUntil.map {
                ISO8601DateFormatter().string(from: $0) } ?? "",
            "installStarted":    state.installStarted,
            "installCompleted":  state.installCompleted,
            "deferralReasons":   state.deferralReasons,
            "lastSeenVersion":   state.lastSeenVersion,
            "reportGeneratedAt": ISO8601DateFormatter().string(from: Date()),
        ]

        if formatJSON {
            if let data   = try? JSONSerialization.data(withJSONObject: report,
                                                         options: .prettyPrinted),
               let output = String(data: data, encoding: .utf8) {
                print(output)
            }
            return
        }

        if formatCSV {
            let headers = "hostname,serial,currentOS,targetOS,compliant,deferralCount,maxDeferrals,deadline,pastDeadline,gracePeriodActive"
            let values  = "\(host),\(serial),\(current),\(target),\(compliant),\(state.deferralCount),\(config.update.maxDeferrals),\(config.update.deadline),\(config.isPastDeadline),\(graceActive)"
            print(headers)
            print(values)
            return
        }

        // Default: human-readable
        cliSection("PUSH Compliance Report")
        cliDivider()
        cliInfo("Hostname:",      host)
        cliInfo("Serial:",        serial)
        cliInfo("Current macOS:", current)
        cliInfo("Target macOS:",  target.isEmpty ? "(not set)" : target)
        cliInfo("Compliant:",     compliant
            ? "\u{001B}[32mYES ✓\u{001B}[0m"
            : "\u{001B}[31mNO ✗\u{001B}[0m")
        cliInfo("Release type:",  config.update.releaseType)
        cliInfo("Deferrals:",     "\(state.deferralCount)/\(config.update.maxDeferrals)")
        cliInfo("Deadline:",      config.update.deadline.isEmpty ? "(none)" : config.update.deadline)
        cliInfo("Past deadline:", config.isPastDeadline ? "\u{001B}[31mYES\u{001B}[0m" : "No")
        if graceActive, let until = state.gracePeriodUntil {
            cliInfo("Grace period:", "Active until \(ISO8601DateFormatter().string(from: until))")
        }
        if !state.deferralReasons.isEmpty {
            cliInfo("Deferral reasons:", state.deferralReasons.joined(separator: ", "))
        }
        cliInfo("Install started:",   state.installStarted   ? "Yes" : "No")
        cliInfo("Install completed:", state.installCompleted ? "Yes" : "No")
        cliInfo("Generated:",         ISO8601DateFormatter().string(from: Date()))
        cliPrint("")
    }

    private func friendlyHostname() -> String {
        let (name, _) = shell("scutil --get ComputerName 2>/dev/null")
        if !name.isEmpty { return name }
        let (local, _) = shell("scutil --get LocalHostName 2>/dev/null")
        if !local.isEmpty { return local }
        return ProcessInfo.processInfo.hostName
    }

    private func machineSerial() -> String {
        let (out, _) = shell("system_profiler SPHardwareDataType 2>/dev/null | awk '/Serial Number/{print $NF}'")
        return out.isEmpty ? "unknown" : out
    }
}

// MARK: - Grace period command

struct GraceCommand {
    let args: [String]

    func run() {
        guard let sub = args.first else {
            printHelp(); exit(1)
        }
        switch sub {
        case "grant":   grantGrace()
        case "revoke":  revokeGrace()
        case "status":  graceStatus()
        default: printHelp(); exit(1)
        }
    }

    private func grantGrace() {
        guard getuid() == 0 else {
            cliError("grace grant requires root. Run: sudo push-cli grace grant --days 7"); exit(1)
        }
        let days = Int(argValue("--days", in: args) ?? "7") ?? 7
        guard days > 0 && days <= 90 else {
            cliError("--days must be between 1 and 90"); exit(1)
        }

        var state = loadState()
        let until = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        state.gracePeriodUntil = until

        do {
            try saveState(state)
            let untilStr = ISO8601DateFormatter().string(from: until)
            cliSuccess("Grace period granted — \(days) days until \(untilStr)")
            cliLog("[Grace] Granted \(days) days until \(untilStr)")

            // Notify via webhook
            let cfg = (try? loadConfig()) ?? CLIConfig()
            NotificationManager(config: cfg).notifyGracePeriodGranted(days: days)
        } catch {
            cliError("Failed to save state: \(error.localizedDescription)"); exit(1)
        }
    }

    private func revokeGrace() {
        guard getuid() == 0 else {
            cliError("grace revoke requires root. Run: sudo push-cli grace revoke"); exit(1)
        }
        var state = loadState()
        state.gracePeriodUntil = nil
        do {
            try saveState(state)
            cliSuccess("Grace period revoked")
            cliLog("[Grace] Revoked")
        } catch {
            cliError("Failed to save state: \(error.localizedDescription)"); exit(1)
        }
    }

    private func graceStatus() {
        let state = loadState()
        if let until = state.gracePeriodUntil, until > Date() {
            let remaining = Calendar.current.dateComponents([.day, .hour],
                from: Date(), to: until)
            cliSuccess("Grace period active — \(remaining.day ?? 0)d \(remaining.hour ?? 0)h remaining")
            cliInfo("Expires:", ISO8601DateFormatter().string(from: until))
        } else {
            cliPrint("No active grace period")
        }
    }

    private func printHelp() {
        cliPrint("""

push-cli grace — IT grace period management

USAGE
  sudo push-cli grace grant --days 7    Grant a 7-day extension
  sudo push-cli grace grant --days 14   Grant a 14-day extension (max 90)
       push-cli grace status            Check if grace period is active
  sudo push-cli grace revoke            Remove active grace period

""")
    }
}

// MARK: - Log rotation

struct LogRotation {

    static func rotateIfNeeded(config: CLIConfig) {
        let maxBytes = Int64(config.logging.maxLogSizeMB) * 1_048_576
        guard maxBytes > 0 else { return }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
              let size  = attrs[.size] as? Int64,
              size > maxBytes
        else { return }

        rotate(keepMax: config.logging.maxRotatedLogs)
    }

    static func rotate(keepMax: Int) {
        let fm = FileManager.default

        // Shift existing rotated logs: push.log.4 → push.log.5 etc.
        for i in stride(from: keepMax - 1, through: 1, by: -1) {
            let old = "\(logPath).\(i)"
            let new = "\(logPath).\(i + 1)"
            if fm.fileExists(atPath: old) {
                try? fm.moveItem(atPath: old, toPath: new)
            }
        }

        // Remove oldest if over limit
        let oldest = "\(logPath).\(keepMax + 1)"
        if fm.fileExists(atPath: oldest) { try? fm.removeItem(atPath: oldest) }

        // Rotate current log → .1
        if fm.fileExists(atPath: logPath) {
            try? fm.moveItem(atPath: logPath, toPath: "\(logPath).1")
        }

        // Create fresh log
        fm.createFile(atPath: logPath, contents: nil)
        cliLog("[LogRotation] Rotated log (keeping \(keepMax) archives)")
    }
}
