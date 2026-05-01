// PopupCommand.swift — Manually trigger any push-ui popup state

import Foundation

struct PopupCommand {
    let args: [String]

    static let validStates = [
        "toast", "softNudge", "hardBlock", "preflightPower", "preflightDisk",
        "passwordPrompt", "downloading", "installing", "rebooting", "compliant", "error",
        "rebootNudge", "rebootForce"
    ]

    func run() {
        guard let state = args.first else {
            cliError("Usage: push-cli popup <state> [options]")
            cliPrint("Valid states: \(Self.validStates.joined(separator: ", "))")
            exit(1)
        }

        guard Self.validStates.contains(state) else {
            cliError("Unknown state: '\(state)'")
            cliPrint("Valid states: \(Self.validStates.joined(separator: ", "))")
            exit(1)
        }

        let uiPath = resolveUIBinary()
        guard FileManager.default.fileExists(atPath: uiPath) else {
            cliError("push-ui not found at \(uiPath)")
            cliPrint("Deploy push-ui.app to \(managedBase)/")
            exit(1)
        }

        let cfgPath       = resolvedConfigPath ?? ""
        let deferralCount = loadState().deferralCount

        var cmd = "\"\(uiPath)\" --state \"\(state)\""
        if !cfgPath.isEmpty { cmd += " --config \"\(cfgPath)\"" }
        cmd += " --deferrals \(deferralCount)"

        // State-specific options
        if state == "downloading" {
            if let p = argValue("--download-progress", in: args) { cmd += " --download-progress \(p)" }
            if let s = argValue("--download-subtitle", in: args) { cmd += " --download-subtitle \"\(s)\"" }
        }
        if state == "preflightDisk" {
            if let a = argValue("--disk-available", in: args) { cmd += " --disk-available \(a)" }
            if let r = argValue("--disk-required",  in: args) { cmd += " --disk-required \(r)" }
        }
        if state == "error" {
            if let e = argValue("--error", in: args) { cmd += " --error \"\(e)\"" }
        }

        shell("pkill -x push-ui 2>/dev/null || true")
        Thread.sleep(forTimeInterval: 0.3)

        // Use launchUIAsUser/runUIBlocking so window appears on the user's screen.
        // Toast is non-blocking (fire and forget).
        // All other states are blocking (wait for user action).
        let exitCode: Int
        if state == "toast" {
            launchUIAsUser(cmd)
            exitCode = 0
        } else {
            exitCode = Int(runUIBlocking(cmd))
        }

        let isRebootState = (state == "rebootNudge" || state == "rebootForce")

        switch exitCode {
        case 0:
            if isRebootState {
                cliSuccess("User chose Restart")
            } else {
                cliSuccess("User chose Install")
            }
        case 1:
            if isRebootState {
                cliSuccess("User deferred restart")
            } else {
                cliSuccess("User deferred")
            }
        case 2: cliPrint("User dismissed")
        case 3:
            // User scheduled a specific reminder time (only possible from softNudge)
            // OR a toast auto-dismissed (toasts use this code on timeout)
            if state == "toast" {
                cliPrint("Toast auto-dismissed")
            } else {
                let scheduledFile = "/tmp/push-scheduled-until"
                if let iso = try? String(contentsOfFile: scheduledFile, encoding: .utf8)
                                    .trimmingCharacters(in: .whitespacesAndNewlines) {
                    cliSuccess("User scheduled reminder for \(iso)")
                } else {
                    cliPrint("User scheduled reminder (no timestamp recorded)")
                }
            }
        case 4: cliPrint("Power timeout")
        default: cliLog("[Popup] Exited with code \(exitCode)")
        }
    }
}
