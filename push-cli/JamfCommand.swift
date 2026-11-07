// ==============================================================================
// PUSH - Proactive Update Scheduling Helper
//
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
//
// Component: JamfCommand.swift
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
// ==============================================================================

// JamfCommand.swift — `push-cli jamf …` subcommands
//
// Currently manages the Jamf LAPS API client secret in the System Keychain.
//
// Usage:
//   sudo push-cli jamf set-laps-secret           # prompts securely
//   sudo push-cli jamf show-laps                 # shows non-secret LAPS status
//   sudo push-cli jamf clear-laps-secret         # removes from keychain
//   sudo push-cli jamf test-laps                 # attempts a real fetch, prints nothing

import Foundation

struct JamfCommand {
    let args: [String]
    var subcommand: String { args.first ?? "" }
    var rest: [String]    { args.isEmpty ? [] : Array(args.dropFirst()) }

    func run() {
        switch subcommand {
        case "set-laps-secret":    JamfSetLapsSecretCommand(args: rest).run()
        case "show-laps":          JamfShowLapsCommand(args: rest).run()
        case "clear-laps-secret":  JamfClearLapsSecretCommand(args: rest).run()
        case "test-laps":          JamfTestLapsCommand(args: rest).run()
        default:
            cliError("Unknown jamf subcommand '\(subcommand)'.")
            cliPrint("Usage: push-cli jamf <set-laps-secret|show-laps|clear-laps-secret|test-laps>")
            exit(1)
        }
    }
}

// MARK: - Set LAPS secret

struct JamfSetLapsSecretCommand {
    let args: [String]

    func run() {
        guard getuid() == 0 else {
            cliError("jamf set-laps-secret requires root. Run: sudo push-cli jamf set-laps-secret")
            exit(1)
        }

        guard let rawSecret = getpass("Jamf LAPS API client secret (input hidden): ") else {
            cliError("Could not read secret"); exit(1)
        }
        let secret = String(cString: rawSecret)
        guard !secret.isEmpty else {
            cliError("Secret cannot be empty"); exit(1)
        }

        let addStatus: Int32 = PushKeychain.save(service: kJamfLapsKeychainService,
            account: kJamfLapsKeychainAccount, password: secret, system: true) ? 0 : 1

        if addStatus == 0 {
            cliSuccess("Jamf LAPS client secret stored in System Keychain")
            cliLog("[Jamf] Stored LAPS client secret in System Keychain")

            if let cfgPath = resolvedConfigPath {
                do {
                    let yaml = try String(contentsOfFile: cfgPath, encoding: .utf8)
                    let updated = updatingYAMLString(yaml, section: ["jamf", "laps"], field: "clientSecret", value: "")
                    try updated.write(toFile: cfgPath, atomically: true, encoding: .utf8)
                    cliSuccess("Plaintext LAPS secret removed from config")
                } catch { cliError("Secret stored, but plaintext config cleanup failed."); exit(1) }
            }
            cliPrint("")
            cliPrint("Verify:       sudo push-cli jamf show-laps")
            cliPrint("Test fetch:   sudo push-cli jamf test-laps")
        } else {
            cliError("Failed to store secret in System Keychain (exit \(addStatus))")
            exit(1)
        }
    }
}

// MARK: - Show LAPS status (non-secret)

struct JamfShowLapsCommand {
    let args: [String]

    func run() {
        let cfg = try? loadConfig()
        cliSection("🔐 Jamf LAPS Status")
        cliDivider()

        guard let c = cfg else {
            cliError("Could not load config")
            return
        }

        cliInfo("Enabled:",      c.jamf.laps.enabled ? "✅ Yes" : "No")
        cliInfo("Jamf URL:",     c.jamf.url.isEmpty ? "(not set)" : c.jamf.url)
        cliInfo("Account name:", c.jamf.laps.accountName.isEmpty ? "(not set)" : c.jamf.laps.accountName)
        cliInfo("Client ID:",    c.jamf.laps.clientId.isEmpty ? "(not set)" : c.jamf.laps.clientId)

        let kcHas     = jamfLapsKeychainSecretExists()
        let yamlHas   = !c.jamf.laps.clientSecret.isEmpty
        if kcHas {
            cliInfo("Secret:", "✅ Stored in System Keychain")
        } else if yamlHas {
            cliInfo("Secret:", "⚠️  Plain text in config.yaml (migrate: sudo push-cli jamf set-laps-secret)")
        } else {
            cliInfo("Secret:", "❌ Not set")
        }

        let serial = machineSerialNumber()
        cliInfo("Serial #:",     serial.isEmpty ? "(could not detect)" : serial)
    }
}

// MARK: - Clear LAPS secret

struct JamfClearLapsSecretCommand {
    let args: [String]

    func run() {
        guard getuid() == 0 else {
            cliError("jamf clear-laps-secret requires root. Run: sudo push-cli jamf clear-laps-secret")
            exit(1)
        }
        let status: Int32 = PushKeychain.delete(service: kJamfLapsKeychainService,
            account: kJamfLapsKeychainAccount, system: true) ? 0 : 1
        if status == 0 || status == 44 {
            cliSuccess("Jamf LAPS client secret cleared from keychain")
            cliLog("[Jamf] LAPS client secret removed from keychain")
        } else {
            cliError("Failed to clear secret from keychain (exit \(status))")
            exit(1)
        }
    }
}

// MARK: - Test LAPS fetch (diagnosis)

struct JamfTestLapsCommand {
    let args: [String]

    func run() {
        guard getuid() == 0 else {
            cliError("jamf test-laps requires root. Run: sudo push-cli jamf test-laps")
            exit(1)
        }
        guard let cfg = try? loadConfig() else {
            cliError("Could not load config"); exit(1)
        }

        cliSection("🧪 Testing Jamf LAPS fetch")
        cliDivider()
        cliInfo("Jamf URL:",   cfg.jamf.url)
        cliInfo("Account:",    cfg.jamf.laps.accountName)
        cliInfo("Serial:",     machineSerialNumber())
        cliPrint("")

        do {
            let result = try JamfLAPSClient(config: cfg).fetchPassword()
            cliSuccess("Fetched LAPS password for '\(result.username)' (\(result.password.count) characters)")
            cliPrint("")
            cliPrint("Password is NOT printed here for security.")
            cliPrint("If this succeeded, push-cli install will succeed on this machine.")
        } catch {
            cliError("LAPS fetch failed: \(error)")
            exit(1)
        }
    }
}
