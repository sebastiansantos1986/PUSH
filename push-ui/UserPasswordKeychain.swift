// UserPasswordKeychain.swift — store/read the user's login password in their
// own login keychain. Runs from push-ui (as the user) so the login keychain
// is accessible. push-cli reads it back via `sudo -u <user> security ...`.
//
// We use a service name unique to PUSH so the entry shows up clearly in
// Keychain Access.app and can be identified/audited.

import Foundation

let kPushUserPwService = "com.push.userpassword"

/// Save the user's password to their login keychain. Used after a successful
/// authentication so future installs don't need to prompt again.
///
/// Failure here is non-fatal — the install can still proceed with the password
/// in /tmp. We just won't have a saved copy for next time.
func saveUserPasswordToLoginKeychain(account: String, password: String) {
    guard !account.isEmpty, !password.isEmpty else { return }

    // Delete any existing entry first — `security add` fails (errSecDuplicateItem)
    // if one already exists. Suppress output: this fails harmlessly if no entry.
    let deleteCmd = """
    /usr/bin/security delete-generic-password \
      -s '\(kPushUserPwService)' \
      -a '\(escapeForShell(account))' \
      2>/dev/null
    """
    _ = runShell(deleteCmd)

    // Add the new entry to login keychain. -U updates if exists; -T allows
    // future invocations of /usr/bin/security itself to read it.
    // -A would allow ALL applications — we explicitly avoid that for safety.
    let addCmd = """
    /usr/bin/security add-generic-password \
      -s '\(kPushUserPwService)' \
      -a '\(escapeForShell(account))' \
      -l 'PUSH — Saved login password' \
      -j 'Saved by PUSH for automatic macOS update authentication.' \
      -w '\(escapeForShell(password))' \
      -T /usr/bin/security \
      2>/dev/null
    """
    _ = runShell(addCmd)
}

/// Quick local helper — Process-based shell exec.
/// Returns exit status. Output is discarded since password values shouldn't
/// be printed or logged.
@discardableResult
private func runShell(_ command: String) -> Int32 {
    let task = Process()
    task.launchPath = "/bin/sh"
    task.arguments  = ["-c", command]
    let devnull = FileHandle(forWritingAtPath: "/dev/null") ?? FileHandle.standardError
    task.standardOutput = devnull
    task.standardError  = devnull
    do {
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus
    } catch {
        return -1
    }
}

/// Escape single quotes for shell use. The `security` command takes args as
/// strings, so we wrap each value in single quotes and escape any single
/// quotes inside the value.
private func escapeForShell(_ s: String) -> String {
    return s.replacingOccurrences(of: "'", with: "'\\''")
}
