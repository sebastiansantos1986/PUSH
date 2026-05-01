// UserPasswordKeychain.swift — read the user's saved login password from
// their login keychain. push-cli runs as root, but the login keychain is
// readable only by that user, so we shell out as them via `sudo -u`.
//
// This helper is the cli-side counterpart to push-ui's UserPasswordKeychain.swift
// which writes the entry. Same service name on both sides.

import Foundation

let kPushUserPwService = "com.push.userpassword"

/// Try to retrieve the saved login password for the given user. Returns nil
/// if no entry exists, the keychain is locked, or the read fails for any
/// other reason. Caller should handle nil by falling through to next auth
/// method (LAPS, system keychain, prompt).
///
/// Important: this only succeeds when the user is logged in and their login
/// keychain is unlocked. From a daemon context with no active session, this
/// returns nil.
func readUserPasswordFromLoginKeychain(account: String) -> String? {
    guard !account.isEmpty, account != "root" else { return nil }

    // -w prints just the password value to stdout
    // We run as the user so the read targets THEIR login keychain.
    let cmd = """
    /usr/bin/sudo -u '\(escapeForShell(account))' \
      /usr/bin/security find-generic-password \
        -s '\(kPushUserPwService)' \
        -a '\(escapeForShell(account))' \
        -w 2>/dev/null
    """
    let (out, status) = runShellCapturingOutput(cmd)
    guard status == 0 else { return nil }

    let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// Validate a password against a local account using dscl.
/// Returns true only if the password is correct AND the account exists.
/// Used both before each install (to verify saved password is still valid)
/// and after retrieval failures.
func validateUserPassword(account: String, password: String) -> Bool {
    guard !account.isEmpty, !password.isEmpty else { return false }

    // dscl . -authonly succeeds (exit 0) if the password is correct
    let task = Process()
    task.launchPath = "/usr/bin/dscl"
    task.arguments  = [".", "-authonly", account, password]
    let devnull = FileHandle(forWritingAtPath: "/dev/null") ?? FileHandle.standardError
    task.standardOutput = devnull
    task.standardError  = devnull
    do {
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    } catch {
        return false
    }
}

/// Delete the saved password — used when validation fails (user changed
/// their password). Triggers a re-prompt next time.
func deleteUserPasswordFromLoginKeychain(account: String) {
    guard !account.isEmpty, account != "root" else { return }
    let cmd = """
    /usr/bin/sudo -u '\(escapeForShell(account))' \
      /usr/bin/security delete-generic-password \
        -s '\(kPushUserPwService)' \
        -a '\(escapeForShell(account))' 2>/dev/null
    """
    _ = runShellCapturingOutput(cmd)
}

/// Check whether a saved password exists without retrieving the value.
/// Useful for `push-cli auth show-user-password` status.
func userPasswordExistsInLoginKeychain(account: String) -> Bool {
    guard !account.isEmpty, account != "root" else { return false }
    let cmd = """
    /usr/bin/sudo -u '\(escapeForShell(account))' \
      /usr/bin/security find-generic-password \
        -s '\(kPushUserPwService)' \
        -a '\(escapeForShell(account))' >/dev/null 2>&1
    """
    let (_, status) = runShellCapturingOutput(cmd)
    return status == 0
}

// MARK: - Internal helpers

@discardableResult
private func runShellCapturingOutput(_ command: String) -> (String, Int32) {
    let task = Process()
    task.launchPath = "/bin/sh"
    task.arguments  = ["-c", command]
    let pipe = Pipe()
    task.standardOutput = pipe
    let devnull = FileHandle(forWritingAtPath: "/dev/null") ?? FileHandle.standardError
    task.standardError  = devnull
    do {
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "", task.terminationStatus)
    } catch {
        return ("", -1)
    }
}

private func escapeForShell(_ s: String) -> String {
    return s.replacingOccurrences(of: "'", with: "'\\''")
}
