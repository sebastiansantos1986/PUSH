// PUSH - Proactive Update Scheduling Helper
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

import Foundation
let kPushUserPwService = "com.push.userpassword"
private func loginCredentialRequest(_ operation: String, account: String) -> (String, Int32) {
    guard let user = consoleUser(), user.name == account, account != "root", !account.isEmpty else { return ("", 1) }
    let ui = resolveUIBinary()
    if getuid() == user.uid { return runDirect(ui, [operation, account]) }
    guard getuid() == 0 else { return ("", 1) }
    return runDirect("/bin/launchctl", ["asuser", String(user.uid), "/usr/bin/sudo", "-u", account, "--", ui, operation, account])
}
func readUserPasswordFromLoginKeychain(account: String) -> String? {
    let (password, status) = loginCredentialRequest("--credential-read", account: account)
    return status == 0 && !password.isEmpty ? password : nil
}
func validateUserPassword(account: String, password: String) -> Bool {
    verifyLocalPassword(account: account, password: password)
}
func deleteUserPasswordFromLoginKeychain(account: String) {
    _ = loginCredentialRequest("--credential-delete", account: account)
}
func userPasswordExistsInLoginKeychain(account: String) -> Bool {
    loginCredentialRequest("--credential-exists", account: account).1 == 0
}
