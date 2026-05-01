// MDMCommand.swift — MDM/Jamf managed software update push workflow
//
// Usage:
//   sudo push-cli mdm push                Push install for configured target version
//   sudo push-cli mdm push --minor        Push latest minor update
//   sudo push-cli mdm push --major        Push latest major upgrade
//   sudo push-cli mdm push --version 26.4 Push specific version
//   sudo push-cli mdm download            Push download-only
//   sudo push-cli mdm check               Check MDM enrollment + bootstrap token
//   sudo push-cli mdm recon               Submit Jamf inventory
//   sudo push-cli mdm fix-swu             Restart softwareupdate daemons

import Foundation

struct MDMCommand {
    let args: [String]
    var subcommand: String { args.first ?? "" }
    var rest: [String]    { args.isEmpty ? [] : Array(args.dropFirst()) }

    func run() {
        switch subcommand {
        case "push":     MDMPushCommand(args: rest).run()
        case "download": MDMPushCommand(args: rest + ["--download-only"]).run()
        case "check":    MDMCheckCommand(args: rest).run()
        case "recon":    MDMReconCommand(args: rest).run()
        case "fix-swu":  MDMFixSWUCommand(args: rest).run()
        default:
            cliError("Unknown mdm subcommand '\(subcommand)'.")
            cliPrint("Usage: push-cli mdm <push|download|check|recon|fix-swu>")
            exit(1)
        }
    }
}

// MARK: - MDM Push

struct MDMPushCommand {
    let args: [String]
    var downloadOnly: Bool { args.contains("--download-only") }
    var forceMinor:   Bool { args.contains("--minor") }
    var forceMajor:   Bool { args.contains("--major") }
    var forceVersion: String? { argValue("--version", in: args) }

    func run() {
        guard getuid() == 0 else {
            cliError("mdm push requires root. Run: sudo push-cli mdm push"); exit(1)
        }
        guard let config = try? loadConfig() else {
            cliError("Cannot load config"); exit(1)
        }
        guard !config.jamf.url.isEmpty else {
            cliError("jamf.url not set in config. Run: sudo push-cli config set jamf.url https://yourjamf.com/")
            exit(1)
        }

        let action = downloadOnly ? "DOWNLOAD_ONLY" : "DOWNLOAD_INSTALL_RESTART"
        cliSection("📡 MDM Update Push")
        cliInfo("Jamf URL:", config.jamf.url)
        cliInfo("Action:",   action)

        // Get API token
        cliPrint("Authenticating with Jamf Pro…")
        guard let token = getAPIToken(config: config) else {
            cliError("Failed to get Jamf Pro API token. Check jamf.clientId/clientSecret or jamf.accountName/accountPassword in config.")
            exit(1)
        }
        cliSuccess("Authenticated")

        // Get computer ID
        guard let computerId = getComputerID(config: config, token: token) else {
            cliError("Failed to get computer ID from Jamf Pro.")
            exit(1)
        }
        cliInfo("Computer ID:", computerId)

        // Determine version type
        let versionType: String
        let specificVersion: String?

        if let v = forceVersion {
            versionType = "SPECIFIC_VERSION"
            specificVersion = v
            cliInfo("Version:", v)
        } else if forceMinor {
            versionType = "LATEST_MINOR"
            specificVersion = nil
            cliInfo("Version type:", "Latest minor")
        } else if forceMajor {
            versionType = "LATEST_MAJOR"
            specificVersion = nil
            cliInfo("Version type:", "Latest major")
        } else if !config.update.targetVersion.isEmpty {
            versionType = "SPECIFIC_VERSION"
            specificVersion = config.update.targetVersion
            cliInfo("Version:", config.update.targetVersion)
        } else {
            versionType = "LATEST_MINOR"
            specificVersion = nil
            cliInfo("Version type:", "Latest minor (default)")
        }

        // Try new API first (Jamf Pro 10.48+), fall back to legacy
        let success = pushNewAPI(config: config, token: token, computerId: computerId,
                                  action: action, versionType: versionType, specificVersion: specificVersion)
            ?? pushLegacyAPI(config: config, token: token, computerId: computerId,
                              action: action, version: specificVersion ?? config.update.targetVersion)

        // Invalidate token
        invalidateToken(config: config, token: token)

        if success {
            cliSuccess("MDM update push sent successfully.")
            cliPrint("Note: Jamf Pro has a mandatory ~5 minute delay before sending the MDM command.")
        } else {
            cliError("MDM push failed. Check jamf.url and credentials in config.")
            exit(1)
        }
    }

    // MARK: - New API (Jamf Pro 10.48+)

    private func pushNewAPI(config: CLIConfig, token: String, computerId: String,
                             action: String, versionType: String, specificVersion: String?) -> Bool? {
        var payload: [String: Any] = [
            "devices": [["objectType": "COMPUTER", "deviceId": computerId]],
            "config":  ["updateAction": action, "versionType": versionType]
        ]
        if let v = specificVersion, versionType == "SPECIFIC_VERSION" {
            var cfg = payload["config"] as! [String: Any]
            cfg["specificVersion"] = v
            payload["config"] = cfg
        }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        let url = "\(config.jamf.url.trimmingCharacters(in: CharacterSet(charactersIn: "/")))//api/v1/managed-software-updates/plans"

        let (resp, status) = curlPost(url: url, token: token, body: body)
        cliLog("[MDM] New API response (\(status)): \(resp)")

        if status == 200 || status == 201 { return true }
        if status == 404 { return nil } // Jamf version doesn't support new API — fall back
        return false
    }

    // MARK: - Legacy API

    private func pushLegacyAPI(config: CLIConfig, token: String, computerId: String,
                                action: String, version: String) -> Bool {
        cliLog("[MDM] Falling back to legacy API")
        let updateAction = action == "DOWNLOAD_ONLY" ? "DOWNLOAD_ONLY" : "DOWNLOAD_AND_INSTALL"
        var payload: [String: Any] = [
            "deviceIds":             [computerId],
            "version":               version,
            "skipVersionVerification": true,
            "updateAction":          updateAction
        ]
        if updateAction == "DOWNLOAD_AND_INSTALL" {
            // forceRestart only for minor updates
            payload["forceRestart"] = true
        }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        let url = "\(config.jamf.url.trimmingCharacters(in: CharacterSet(charactersIn: "/")))//api/v1/macos-managed-software-updates/send-updates"

        let (resp, status) = curlPost(url: url, token: token, body: body)
        cliLog("[MDM] Legacy API response (\(status)): \(resp)")
        return status == 200 || status == 201
    }

    // MARK: - Auth

    private func getAPIToken(config: CLIConfig) -> String? {
        let base = config.jamf.url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // OAuth (client credentials) — preferred
        if !config.jamf.clientId.isEmpty && !config.jamf.clientSecret.isEmpty {
            let (out, status) = shell("""
                curl -s -w '\\n%{http_code}' --request POST '\(base)/api/oauth/token' \
                  --header 'Content-Type: application/x-www-form-urlencoded' \
                  --data-urlencode 'client_id=\(config.jamf.clientId)' \
                  --data-urlencode 'grant_type=client_credentials' \
                  --data-urlencode 'client_secret=\(config.jamf.clientSecret)'
                """)
            return parseToken(response: out, field: "access_token")
        }

        // Legacy account/password
        if !config.jamf.accountName.isEmpty && !config.jamf.accountPassword.isEmpty {
            let creds = "\(config.jamf.accountName):\(config.jamf.accountPassword)"
            let (out, _) = shell("curl -s --request POST '\(base)/api/v1/auth/token' --user '\(creds)'")
            return parseToken(response: out, field: "token")
        }

        return nil
    }

    private func invalidateToken(config: CLIConfig, token: String) {
        let base = config.jamf.url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        shell("curl -s --request POST '\(base)/api/v1/auth/invalidate-token' --header 'Authorization: Bearer \(token)' > /dev/null 2>&1")
    }

    private func getComputerID(config: CLIConfig, token: String) -> String? {
        // Use serial number to look up computer ID
        let (serial, _) = shell("system_profiler SPHardwareDataType 2>/dev/null | awk '/Serial Number/{print $NF}'")
        let sn = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sn.isEmpty else { return nil }

        let base = config.jamf.url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let (out, _) = shell("curl -s --request GET '\(base)/api/v1/computers-preview?filter=hardware.serialNumber==\(sn)' --header 'Authorization: Bearer \(token)' --header 'Accept: application/json'")

        if let data = out.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let results = json["results"] as? [[String: Any]],
           let first = results.first,
           let id = first["id"] as? Int {
            return "\(id)"
        }
        // Fall back to configured computer ID
        return config.jamf.computerId.isEmpty ? nil : config.jamf.computerId
    }

    private func parseToken(response: String, field: String) -> String? {
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json[field] as? String else { return nil }
        return token
    }

    private func curlPost(url: String, token: String, body: Data) -> (String, Int) {
        let bodyStr = String(data: body, encoding: .utf8) ?? "{}"
        let (out, _) = shell("""
            curl -s -o /tmp/push-mdm-resp.json -w '%{http_code}' \
              --request POST '\(url)' \
              --header 'Authorization: Bearer \(token)' \
              --header 'content-type: application/json' \
              --data '\(bodyStr.replacingOccurrences(of: "'", with: "'\\''"))'
            """)
        let respBody = (try? String(contentsOfFile: "/tmp/push-mdm-resp.json", encoding: .utf8)) ?? ""
        let code = Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        shell("rm -f /tmp/push-mdm-resp.json 2>/dev/null; true")
        return (respBody, code)
    }
}

// MARK: - MDM Check (enrollment + bootstrap token)

struct MDMCheckCommand {
    let args: [String]

    func run() {
        cliSection("🔐 MDM & Auth Validation")

        // Enrollment
        let (enrollment, _) = shell("profiles status -type enrollment 2>/dev/null")
        let enrolled = enrollment.lowercased().contains("enrolled via dep") ||
                       enrollment.lowercased().contains("mdm enrolled")
        cliInfo("MDM Enrolled:", enrolled ? "✅ Yes" : "❌ No")

        // Bootstrap token
        let (bootstrap, _) = shell("profiles status -type bootstraptoken 2>/dev/null")
        let hasToken = bootstrap.lowercased().contains("escrowed")
        cliInfo("Bootstrap Token:", hasToken ? "✅ Escrowed" : "❌ Not escrowed")

        // Bootstrap token validation (macOS 13.3+)
        if versionGTE(currentMacOSVersion(), "13.3") {
            let (eacs, _) = shell("/usr/libexec/mdmclient QueryDeviceInformation 2>/dev/null | grep EACSPreflight")
            let eacsOK = eacs.lowercased().contains("success") || eacs.lowercased().contains("true")
            cliInfo("Bootstrap Token Valid:", eacsOK ? "✅ Yes" : "⚠️  Unknown")
        }

        // Beta program
        if versionGTE(currentMacOSVersion(), "13.4") {
            let (beta, _) = shell("/usr/libexec/mdmclient QueryDeviceInformation 2>/dev/null | grep IsDefaultCatalog")
            cliInfo("Beta Program:", beta.lowercased().contains("true") ? "No (production)" : "⚠️  Enrolled in beta")
        }

        // Console user checks
        if let user = consoleUser() {
            cliPrint("")
            cliInfo("Console user:", user.name)
            cliInfo("Secure Token:", userHasSecureToken(user.name) ? "✅ Yes" : "❌ No")
            cliInfo("Volume Owner:", userIsVolumeOwner(user.name) ? "✅ Yes" : "❌ No")

            // Admin check
            let (groups, _) = shell("groups \"\(user.name)\" 2>/dev/null")
            cliInfo("Admin:", groups.contains("admin") ? "✅ Yes" : "No")
        }
    }
}

// MARK: - MDM Recon

struct MDMReconCommand {
    let args: [String]

    func run() {
        guard getuid() == 0 else {
            cliError("mdm recon requires root. Run: sudo push-cli mdm recon"); exit(1)
        }
        guard let config = try? loadConfig(),
              !config.jamf.binaryPath.isEmpty,
              FileManager.default.fileExists(atPath: config.jamf.binaryPath) else {
            cliError("Jamf binary not found. Set jamf.binaryPath in config.")
            exit(1)
        }
        cliSection("📋 Jamf Inventory")
        cliPrint("Submitting inventory (recon)…")
        let (_, status) = shell("\"\(((try? loadConfig()) ?? CLIConfig()).jamf.binaryPath)\" recon 2>/dev/null")
        if status == 0 {
            cliSuccess("Inventory submitted successfully.")
        } else {
            cliError("Recon failed (exit \(status))")
            exit(1)
        }
    }
}

// MARK: - Fix softwareupdate daemons

struct MDMFixSWUCommand {
    let args: [String]

    func run() {
        guard getuid() == 0 else {
            cliError("mdm fix-swu requires root. Run: sudo push-cli mdm fix-swu"); exit(1)
        }

        cliSection("🔧 Restart softwareupdate Daemons")

        let daemons = [
            "system/com.apple.mobile.softwareupdated",
            "system/com.apple.softwareupdated"
        ]

        for daemon in daemons {
            cliPrint("Restarting \(daemon)…")
            let (_, status) = shell("launchctl kickstart -k \"\(daemon)\" 2>/dev/null")
            if status == 0 {
                cliSuccess("Restarted: \(daemon)")
            } else {
                cliWarning("Could not restart \(daemon) (may not be running)")
            }
        }

        // Restart notification manager if user is logged in
        if let user = consoleUser() {
            let notifDaemon = "gui/\(user.uid)/com.apple.SoftwareUpdateNotificationManager"
            cliPrint("Restarting \(notifDaemon)…")
            let (_, status) = shell("launchctl kickstart -k \"\(notifDaemon)\" 2>/dev/null")
            if status == 0 {
                cliSuccess("Restarted notification manager")
            } else {
                cliWarning("Could not restart notification manager")
            }
        }

        cliSuccess("softwareupdate daemon restart complete.")
    }
}
