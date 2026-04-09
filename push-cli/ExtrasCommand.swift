// ExtrasCommand.swift — Non-system updates and Safari-only updates
//
// Usage:
//   sudo push-cli install-extras          Install all non-system updates
//   sudo push-cli install-safari          Install Safari update only

import Foundation

// MARK: - Non-system updates

struct InstallExtrasCommand {
    let args: [String]

    func run() {
        guard getuid() == 0 else {
            cliError("install-extras requires root. Run: sudo push-cli install-extras"); exit(1)
        }

        cliSection("📦 Non-System Updates")
        cliInfo("Platform:", "\(isAppleSilicon() ? "Apple Silicon" : "Intel") / macOS \(macOSMajor)")

        // Find available non-system updates
        cliPrint("Checking softwareupdate for non-system updates…")
        let (listOut, _) = shell("/usr/sbin/softwareupdate --list 2>&1")
        let labels = parseNonSystemLabels(output: listOut)

        if labels.isEmpty {
            cliSuccess("No non-system updates found.")
            exit(0)
        }

        cliInfo("Found:", "\(labels.count) non-system update(s)")
        for label in labels { cliPrint("  • \(label)") }

        // Install each — attempt twice on failure (mirrors super behavior)
        for label in labels {
            cliPrint("\nInstalling: \(label)")
            let cmd = softwareupdateNonSystemCmd(labels: label)
            cliLog("[Extras] Running: \(cmd)")

            let (_, status) = shell(cmd)
            if status == 0 {
                cliSuccess("Installed: \(label)")
            } else {
                cliLog("[Extras] First attempt failed — retrying \(label)")
                let (_, status2) = shell(cmd)
                if status2 == 0 {
                    cliSuccess("Installed (retry): \(label)")
                } else {
                    cliWarning("Failed to install \(label) — skipping")
                }
            }
        }

        cliSuccess("Non-system update workflow complete.")
    }

    private func parseNonSystemLabels(output: String) -> [String] {
        var labels: [String] = []
        var current = ""
        for line in output.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("* Label:") {
                current = t.replacingOccurrences(of: "* Label:", with: "").trimmingCharacters(in: .whitespaces)
            } else if t.contains("Action: restart") {
                // This is a system update — skip
                current = ""
            } else if t.contains("MobileSoftwareUpdate") || t.lowercased().contains("safari") {
                // Non-restart update
                if !current.isEmpty { labels.append(current); current = "" }
            }
        }
        // Also catch anything labelled without Action: restart
        return labels
    }
}

// MARK: - Safari-only update

struct InstallSafariCommand {
    let args: [String]

    func run() {
        guard getuid() == 0 else {
            cliError("install-safari requires root. Run: sudo push-cli install-safari"); exit(1)
        }

        cliSection("🧭 Safari Update")
        cliInfo("Platform:", "\(isAppleSilicon() ? "Apple Silicon" : "Intel") / macOS \(macOSMajor)")

        // Check if Safari is open — warn user if so
        let (safariPID, _) = shell("pgrep -x Safari 2>/dev/null")
        let safariOpen = !safariPID.trimmingCharacters(in: .whitespaces).isEmpty
        if safariOpen {
            cliWarning("Safari is currently open. It will relaunch after the update.")
        }

        let cmd = softwareupdateSafariCmd()
        cliLog("[Safari] Running: \(cmd)")
        cliPrint("Installing Safari update…")

        let (out, status) = shell(cmd)
        if status == 0 {
            cliSuccess("Safari update installed successfully.")
        } else {
            cliError("Safari update failed (exit \(status))")
            cliLog("[Safari] Output: \(out)")
            exit(1)
        }
    }
}
