// NotificationManager.swift — Webhook notifications and Jamf EA reporting for PUSH

import Foundation

// MARK: - Notification manager

struct NotificationManager {
    let config: CLIConfig

    // MARK: - Jamf EA

    /// Submit compliance status as a Jamf Extension Attribute.
    func reportJamfEA(compliant: Bool, current: String, target: String, deferrals: Int) {
        guard !config.jamf.binaryPath.isEmpty,
              FileManager.default.fileExists(atPath: config.jamf.binaryPath),
              config.jamf.reportEAAfterCheck
        else { return }

        let status   = compliant ? "Compliant" : "Non-Compliant"
        let eaValue  = "\(status) | Current: \(current) | Target: \(target) | Deferrals: \(deferrals)/\(config.update.maxDeferrals)"
        let (_, rc)  = shell("\"\(config.jamf.binaryPath)\" recon 2>/dev/null")

        if rc == 0 {
            cliLog("[Jamf] EA reported: \(eaValue)")
        } else {
            cliLog("[Jamf] EA report failed (exit \(rc))")
        }
    }

    // MARK: - Webhooks

    func notifyDetection(version: String, isMajor: Bool, deadline: String) {
        guard config.auto.notifyAdminOnDetection else { return }
        let type = isMajor ? "Major Upgrade" : "Minor Update"
        let (computerName, _) = shell("scutil --get ComputerName 2>/dev/null")
        let host = computerName.isEmpty ? ProcessInfo.processInfo.hostName : computerName
        send(text: """
            🔔 *PUSH — Update Detected*
            *Host:* \(host)
            *Update:* macOS \(version) (\(type))
            *Deadline:* \(deadline)
            """)
    }

    func notifyDeadlineHit(version: String, host: String? = nil) {
        guard config.auto.notifyOnDeadlineHit else { return }
        let h = host ?? ProcessInfo.processInfo.hostName
        send(text: """
            🚨 *PUSH — Deadline Passed*
            *Host:* \(h)
            *Update:* macOS \(version)
            *Status:* Hard block now active — user must install immediately
            """)
    }

    func notifyDeferralsExhausted(version: String, deferrals: Int) {
        guard config.auto.notifyOnDeferralExhausted else { return }
        let (computerName, _) = shell("scutil --get ComputerName 2>/dev/null")
        let host = computerName.isEmpty ? ProcessInfo.processInfo.hostName : computerName
        send(text: """
            ⚠️ *PUSH — Deferrals Exhausted*
            *Host:* \(host)
            *Update:* macOS \(version)
            *Deferrals used:* \(deferrals)/\(deferrals)
            *Status:* Hard block now active
            """)
    }

    func notifyInstallComplete(version: String, previousVersion: String) {
        guard config.auto.notifyOnInstallComplete else { return }
        let (computerName, _) = shell("scutil --get ComputerName 2>/dev/null")
        let host = computerName.isEmpty ? ProcessInfo.processInfo.hostName : computerName
        send(text: """
            ✅ *PUSH — Install Complete*
            *Host:* \(host)
            *Upgraded:* macOS \(previousVersion) → \(version)
            *Status:* Compliant
            """)
    }

    func notifyGracePeriodGranted(days: Int) {
        guard !config.auto.adminWebhookURL.isEmpty else { return }
        let (computerName, _) = shell("scutil --get ComputerName 2>/dev/null")
        let host = computerName.isEmpty ? ProcessInfo.processInfo.hostName : computerName
        send(text: """
            🕐 *PUSH — Grace Period Granted*
            *Host:* \(host)
            *Extension:* \(days) days
            """)
    }

    // MARK: - Send

    private func send(text: String) {
        guard !config.auto.adminWebhookURL.isEmpty,
              let url = URL(string: config.auto.adminWebhookURL)
        else {
            cliLog("[Webhook] No URL configured — skipping notification")
            return
        }

        let isTeams = config.auto.adminWebhookURL.contains("webhook.office.com") ||
                      config.auto.adminWebhookURL.contains("office365.com") ||
                      config.auto.adminWebhookURL.contains("webhook.office365.com")

        let payload: [String: Any]

        if isTeams {
            // Teams Adaptive Card format (works with both old and new webhook URLs)
            let plainText = text
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: "_", with: "")
            payload = [
                "type":    "message",
                "attachments": [[
                    "contentType": "application/vnd.microsoft.card.adaptive",
                    "content": [
                        "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                        "type":    "AdaptiveCard",
                        "version": "1.4",
                        "body": [[
                            "type": "TextBlock",
                            "text": plainText,
                            "wrap": true,
                            "fontType": "Monospace"
                        ]]
                    ]
                ]]
            ]
        } else {
            // Slack format
            payload = ["text": text]
        }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        cliLog("[Webhook] Sending to \(isTeams ? "Teams" : "Slack")…")

        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let sema = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err {
                cliLog("[Webhook] Send failed: \(err.localizedDescription)")
            } else if let http = resp as? HTTPURLResponse {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                if http.statusCode == 200 || http.statusCode == 202 {
                    cliLog("[Webhook] Sent successfully (HTTP \(http.statusCode))")
                } else {
                    cliLog("[Webhook] HTTP \(http.statusCode) — \(body)")
                }
            }
            sema.signal()
        }.resume()
        sema.wait()
    }
}
