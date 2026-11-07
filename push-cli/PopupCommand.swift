// ==============================================================================
// PUSH - Proactive Update Scheduling Helper
//
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
//
// Component: PopupCommand.swift
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
// ==============================================================================

// PopupCommand.swift — Manually trigger any push-ui popup state

import Foundation

struct PopupCommand {
    let args: [String]

    static let validStates = [
        "toast", "appUpdates", "entraRegistration", "softNudge", "hardBlock", "preflightPower", "preflightDisk",
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

        guard state != "passwordPrompt" || allowsUserPasswordPrompts else {
            cliPrint("User password prompts are disabled. IT must provide managed authorization.")
            return
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
        cmd += " --deferrals \(deferralCount) --manual-test"
        if let style = argValue("--background-style", in:args) {
            guard ["solid","frosted"].contains(style) else { cliError("Background style must be solid or frosted"); return }
            cmd += " --background-style " + style
        }
        if let text = argValue("--background-opacity", in:args) {
            guard let percent = Int(text), (55...100).contains(percent) else { cliError("Background opacity must be 55–100"); return }
            cmd += " --background-opacity " + String(percent)
        }

        if state == "entraRegistration", let text = argValue("--entra-stage",in:args) {
            guard let stage = Int(text), (1...4).contains(stage) else { cliError("Entra preview stage must be 1–4."); return }
            cmd += " --entra-stage " + String(stage)
        }
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

        // Manual tests wait for the actual button result. They never invoke an install.
        cliPrint("Opening \(state) preview… Waiting for the window, then your button choice. Control+C cancels this Terminal command.")
        let exitCode = runUIBlocking(cmd)
        let message = popupResultMessage(state: state, exitCode: exitCode)
        if exitCode == 3, state != "toast",
           let date = try? String(contentsOfFile:"/tmp/push-scheduled-until",encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines), !date.isEmpty {
            cliSuccess("User scheduled a reminder for \(date)")
        } else if exitCode == 0 { cliSuccess(message) }
        else if exitCode == 5 && state != "toast" { cliError(message) }
        else if [1, 2, 3, 4, 5, 6].contains(exitCode) { cliPrint(message) }
        else { cliError(message) }
    }
}
