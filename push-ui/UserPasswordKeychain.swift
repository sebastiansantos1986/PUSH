// UserPasswordKeychain.swift — pass a validated password back to the root
// daemon for one-time System Keychain storage.

import Foundation

let kPushUserPwService = "com.push.userpassword"

/// Write the validated password to a short-lived handoff file. push-cli runs as
/// root, reads this file immediately after the UI exits, stores the password in
/// the System Keychain, then deletes the file. This avoids repeated login
/// keychain access prompts on future daemon runs.
@discardableResult
func writePasswordHandoffForRoot(account: String, password: String) -> Bool {
    guard !account.isEmpty, !password.isEmpty else { return false }

    let path = "/tmp/push-user-password.\(getuid())"
    let payload = "\(account)\n\(password)"
    do {
        try payload.write(toFile: path, atomically: true, encoding: .utf8)
        chmod(path, S_IRUSR | S_IWUSR)
        return true
    } catch {
        return false
    }
}
