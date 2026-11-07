// PUSH - Proactive Update Scheduling Helper
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

import Foundation
let kPushUserPwService = "com.push.userpassword"
@discardableResult
func saveUserPasswordToLoginKeychain(account: String, password: String) -> Bool {
    guard account == NSUserName(), getuid() != 0 else { return false }
    return PushKeychain.save(service: kPushUserPwService, account: account, password: password)
}

/// Runs before AppKit starts. The same signed UI executable owns and reads the entry.
func handleCredentialRequest(_ args: [String]) {
    guard args.count == 3, args[1].hasPrefix("--credential-") else { return }
    guard getuid() != 0, args[2] == NSUserName() else { exit(1) }
    let account = args[2]
    switch args[1] {
    case "--credential-read":
        guard let password = PushKeychain.read(service: kPushUserPwService, account: account) else { exit(1) }
        FileHandle.standardOutput.write(Data(password.utf8))
        exit(0)
    case "--credential-exists":
        exit(PushKeychain.exists(service: kPushUserPwService, account: account) ? 0 : 1)
    case "--credential-delete":
        exit(PushKeychain.delete(service: kPushUserPwService, account: account) ? 0 : 1)
    default: exit(1)
    }
}
