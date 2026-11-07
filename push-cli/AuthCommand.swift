// ==============================================================================
// PUSH - Proactive Update Scheduling Helper
//
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
//
// Component: AuthCommand.swift
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
// ==============================================================================

// AuthCommand.swift — Keychain-based credential management for push-cli
//
// Stores auth.localPassword in the System Keychain using Security.framework.
// Secret bytes never enter command arguments.
//
// Usage:
//   sudo push-cli auth set-password
//   sudo push-cli auth set-password --account localadmin
//   sudo push-cli auth show
//   sudo push-cli auth clear

import Foundation

// MARK: - Keychain constants

private let kService  = "com.push.autoupdate"
private let kAccount  = "push_auth_local_password"
private let kKeychain = "/Library/Keychains/System.keychain"

struct AuthCommand {
    let args: [String]
    var subcommand: String { args.first ?? "" }
    var rest: [String]    { args.isEmpty ? [] : Array(args.dropFirst()) }

    func run() {
        switch subcommand {
        case "set-password":         AuthSetPasswordCommand(args: rest).run()
        case "show":                 AuthShowCommand(args: rest).run()
        case "clear":                AuthClearCommand(args: rest).run()
        case "show-user-password":   AuthShowUserPasswordCommand(args: rest).run()
        case "clear-user-password":  AuthClearUserPasswordCommand(args: rest).run()
        default:
            cliError("Unknown auth subcommand '\(subcommand)'.")
            cliPrint("Usage: push-cli auth <set-password|show|clear|show-user-password|clear-user-password>")
            exit(1)
        }
    }
}

struct AuthShowUserPasswordCommand {
    let args: [String]
    func run() {
        cliSection("👤 User Saved Password")
        cliDivider()
        guard let user = consoleUser()?.name, !user.isEmpty else {
            cliInfo("Console user:", "(none — no logged-in user)")
            cliInfo("Status:",       "❌ Cannot read login keychain without a console user")
            return
        }
        cliInfo("Console user:", user)
        let exists = userPasswordExistsInLoginKeychain(account: user)
        if !exists {
            cliInfo("Status:", "❌ No saved password — user will be prompted at next install")
            return
        }
        // Exists — try to validate it. Validation requires reading the password,
        // which requires the login keychain to be unlocked.
        if let pwd = readUserPasswordFromLoginKeychain(account: user) {
            if validateUserPassword(account: user, password: pwd) {
                cliInfo("Status:", "✅ Saved and valid")
            } else {
                cliInfo("Status:", "⚠️  Saved but invalid (user changed password — will re-prompt)")
            }
        } else {
            cliInfo("Status:", "⚠️  Saved but unreadable (login keychain locked?)")
        }
    }
}

struct AuthClearUserPasswordCommand {
    let args: [String]
    func run() {
        guard getuid() == 0 else {
            cliError("auth clear-user-password requires root."); exit(1)
        }
        guard let user = consoleUser()?.name, !user.isEmpty else {
            cliError("No console user — nothing to clear."); exit(1)
        }
        deleteUserPasswordFromLoginKeychain(account: user)
        cliSuccess("Cleared saved password for \(user)")
        cliLog("[Auth] Cleared saved user password for \(user)")
    }
}

// MARK: - Set password

struct AuthSetPasswordCommand {
    let args: [String]

    func run() {
        guard getuid() == 0 else {
            cliError("auth set-password requires root. Run: sudo push-cli auth set-password")
            exit(1)
        }

        var account = argValue("--account", in: args) ?? ""

        // Try config first
        if account.isEmpty, let cfg = try? loadConfig() {
            account = cfg.auth.localAccount
        }

        // Prompt if still empty
        if account.isEmpty {
            print("Local admin account name (e.g. localadmin): ", terminator: "")
            account = readLine(strippingNewline: true) ?? ""
        }

        guard !account.isEmpty else {
            cliError("Account name cannot be empty"); exit(1)
        }

        // Prompt for password securely via getpass
        guard let rawPass = getpass("Password for \(account) (input hidden): ") else {
            cliError("Could not read password"); exit(1)
        }
        let password = String(cString: rawPass)
        guard !password.isEmpty else {
            cliError("Password cannot be empty"); exit(1)
        }

        let addStatus: Int32 = PushKeychain.save(service: kService, account: kAccount,
                                                  password: password, system: true) ? 0 : 1

        if addStatus == 0 {
            cliSuccess("Password stored in System Keychain for account: \(account)")
            cliLog("[Auth] Stored credentials for account '\(account)' in System Keychain")

            guard let cfgPath = resolvedConfigPath,
                  let yaml = try? String(contentsOfFile: cfgPath, encoding: .utf8) else {
                cliError("Password stored, but config could not be read. Set auth.localAccount before installing."); exit(1)
            }
            let updatedAccount = updatingYAMLString(yaml, section: ["auth"], field: "localAccount", value: account)
            let updated = updatingYAMLString(updatedAccount, section: ["auth"], field: "localPassword", value: "")
            do {
                try updated.write(toFile: cfgPath, atomically: true, encoding: .utf8)
                cliSuccess("Config updated — account saved and plaintext password removed")
            } catch {
                cliError("Password stored, but config migration failed. Check config permissions before installing."); exit(1)
            }
            cliPrint("")
            cliPrint("PUSH will now retrieve the password from the keychain at install time.")
            cliPrint("To verify: sudo push-cli auth show")
            cliPrint("To remove: sudo push-cli auth clear")
        } else {
            cliError("Failed to store password in System Keychain (exit \(addStatus))")
            exit(1)
        }
    }
}

// MARK: - Show

struct AuthShowCommand {
    let args: [String]

    func run() {
        let cfg     = try? loadConfig()
        let account = cfg?.auth.localAccount ?? ""

        cliSection("🔐 Auth Credentials")
        cliDivider()
        if account.isEmpty {
            cliInfo("Account:", "(not set)")
            cliInfo("Keychain:", "(not set)")
        } else {
            cliInfo("Account:", account)
            cliInfo("Keychain:", keychainPasswordExists() ? "✅ Password stored" : "❌ Not found")
        }
        if !(cfg?.auth.localPassword.isEmpty ?? true) {
            cliWarning("Plain text password found in config.yaml — migrate: sudo push-cli auth set-password")
        }
    }
}

// MARK: - Clear

struct AuthClearCommand {
    let args: [String]

    func run() {
        guard getuid() == 0 else {
            cliError("auth clear requires root. Run: sudo push-cli auth clear"); exit(1)
        }

        let status: Int32 = PushKeychain.delete(service: kService, account: kAccount, system: true) ? 0 : 1
        if status == 0 || status == 44 { // 44 = item not found
            cliSuccess("Keychain credentials cleared")
            cliLog("[Auth] Keychain credentials removed")
            if let cfgPath = resolvedConfigPath {
                do {
                    let yaml = try String(contentsOfFile: cfgPath, encoding: .utf8)
                    let updated = updatingYAMLString(yaml, section: ["auth"], field: "localPassword", value: "")
                    try updated.write(toFile: cfgPath, atomically: true, encoding: .utf8)
                } catch { cliError("Keychain cleared, but plaintext config cleanup failed."); exit(1) }
            }
        } else {
            cliError("Failed to clear keychain credentials (exit \(status))")
            exit(1)
        }
    }
}

// MARK: - Keychain helpers (used throughout push-cli)

/// Check if a password is stored in the System Keychain.
func keychainPasswordExists() -> Bool {
    PushKeychain.exists(service: kService, account: kAccount, system: true)
}
func keychainPassword() -> String? {
    PushKeychain.read(service: kService, account: kAccount, system: true)
}
