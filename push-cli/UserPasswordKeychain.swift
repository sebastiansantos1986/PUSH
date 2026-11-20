// PUSH - Proactive Update Scheduling Helper
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

import Foundation
let kPushUserPwService = "com.push.userpassword"
private func loginCredentialRequest(_ operation: String, account: String) -> (String, Int32) {
    guard let user = consoleUser(), user.name == account, account != "root", !account.isEmpty else { return ("", 1) }
    let ui = resolveUIBinary()
    if getuid() == user.uid { return runDirect(ui, [operation, account],discardStderr:true) }
    guard getuid() == 0 else { return ("", 1) }
    return runDirect("/bin/launchctl", ["asuser", String(user.uid), "/usr/bin/sudo", "-n", "-H", "-u", account, "--", ui, operation, account],discardStderr:true)
}
func readUserPasswordFromLoginKeychain(account: String) -> String? {
    let (password, status) = loginCredentialRequest("--credential-read", account: account)
    return status == 0 && !password.isEmpty && password.utf8.count<=4096 && !password.contains("\n") && !password.contains("\r") ? password : nil
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

// Root-only diagnostic of the exact private launcher. No Keychain query or UI.
func checkInstallAuthorizationLaunch()->Int32 {
    guard getuid()==0,let user=consoleUser() else{return 1}
    return loginCredentialRequest("--credential-check",account:user.name).1
}
