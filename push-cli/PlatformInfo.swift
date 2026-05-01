// PlatformInfo.swift — macOS version + architecture detection helpers
// Used by install, download, and MDM workflows to pick the right command variant.

import Foundation

// MARK: - macOS major version

var macOSMajor: Int {
    ProcessInfo.processInfo.operatingSystemVersion.majorVersion
}

// Convenience booleans for command branching
var isMacOS14orLater: Bool { macOSMajor >= 14 }
var isMacOS13orLater: Bool { macOSMajor >= 13 }
var isMacOS12orLater: Bool { macOSMajor >= 12 }
var isMacOS11:        Bool { macOSMajor == 11 }

// MARK: - Architecture

func isAppleSilicon() -> Bool {
    var info = utsname(); uname(&info)
    return withUnsafeBytes(of: &info.machine) {
        String(bytes: $0.prefix(while: { $0 != 0 }), encoding: .ascii) ?? ""
    }.hasPrefix("arm")
}

// MARK: - User state

/// Returns true if a real user (not root/loginwindow) is at the console.
func userIsLoggedIn() -> Bool { consoleUser() != nil }

// MARK: - Secure token / volume owner checks

func userHasSecureToken(_ username: String) -> Bool {
    let (out, _) = shell("dscl . read \"/Users/\(username)\" AuthenticationAuthority 2>/dev/null | grep -c SecureToken")
    return (Int(out.trimmingCharacters(in: .whitespaces)) ?? 0) > 0
}

func userIsVolumeOwner(_ username: String) -> Bool {
    let (guid, _) = shell("dscl . read \"/Users/\(username)\" GeneratedUID 2>/dev/null | awk '{print $2}'")
    guard !guid.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
    let (owners, _) = shell("diskutil apfs listcryptousers / 2>/dev/null")
    return owners.contains(guid.trimmingCharacters(in: .whitespaces))
}

// MARK: - softwareupdate command builders

/// Build the correct softwareupdate download command for the current OS + arch + auth state.
func softwareupdateDownloadCmd(label: String, password: String?,
                                account: String?, user: (name: String, uid: Int)?) -> String {
    let as_ = isAppleSilicon()
    let uid  = user.map { "\($0.uid)" } ?? "0"
    let uname = user?.name ?? ""

    if isMacOS14orLater && as_ {
        // macOS 14+ Apple Silicon — authenticated download
        if let pwd = password, let acct = account, !acct.isEmpty {
            return "echo \"\(pwd)\" | launchctl asuser \(uid) sudo -u root softwareupdate --download \"\(label)\" --agree-to-license --user \"\(acct)\" --stdinpass"
        }
        // Fall through to 13 pattern if no credentials
        return "echo ' ' | launchctl asuser \(uid) sudo -u \"\(uname)\" softwareupdate --download \"\(label)\" --agree-to-license --user \"\(uname)\" --stdinpass"
    } else if isMacOS13orLater && as_ {
        return "echo ' ' | launchctl asuser \(uid) sudo -u \"\(uname)\" softwareupdate --download \"\(label)\" --agree-to-license --user \"\(uname)\" --stdinpass"
    } else if isMacOS13orLater && !as_ {
        return "launchctl asuser \(uid) sudo -u \"\(uname)\" softwareupdate --download \"\(label)\" --agree-to-license"
    } else if macOSMajor == 12 && as_ {
        return "launchctl asuser \(uid) sudo -u root softwareupdate --download \"\(label)\" --agree-to-license --user root --stdinpass \"\""
    } else if macOSMajor == 12 && !as_ {
        return "launchctl asuser \(uid) sudo -u root softwareupdate --download \"\(label)\" --agree-to-license"
    } else if isMacOS11 && as_ {
        return "echo ' ' | softwareupdate --download \"\(label)\" --agree-to-license"
    } else {
        return "softwareupdate --download \"\(label)\" --agree-to-license"
    }
}

/// Build the correct softwareupdate install command for the current OS + arch + auth state.
func softwareupdateInstallCmd(label: String, password: String?,
                               account: String?, user: (name: String, uid: Int)?) -> String {
    let as_   = isAppleSilicon()
    let uid   = user.map { "\($0.uid)" } ?? "0"
    let uname = user?.name ?? ""
    let base  = "--restart --force --no-scan --agree-to-license"

    if isMacOS13orLater && as_ {
        if let pwd = password, let acct = account, !acct.isEmpty {
            // User logged in: launchctl asuser + echo pipe (super's exact pattern)
            if user != nil {
                return "echo \"\(pwd)\" | launchctl asuser \(uid) sudo -u root softwareupdate --install \"\(label)\" \(base) --user \"\(acct)\" --stdinpass"
            } else {
                // No user at console
                return "echo \"\(pwd)\" | sudo -u root softwareupdate --install \"\(label)\" \(base) --user \"\(acct)\" --stdinpass"
            }
        }
        return "launchctl asuser \(uid) sudo -u root softwareupdate --install \"\(label)\" \(base)"
    } else if isMacOS13orLater && !as_ {
        // Intel — no auth needed
        if user != nil {
            return "launchctl asuser \(uid) sudo -u root softwareupdate --install \"\(label)\" \(base)"
        }
        return "softwareupdate --install \"\(label)\" \(base)"
    } else if macOSMajor == 12 && as_ {
        if let pwd = password, let acct = account, !acct.isEmpty {
            return "launchctl asuser \(uid) sudo -u root softwareupdate --install \"\(label)\" \(base) --user \"\(acct)\" --stdinpass \"\(pwd)\""
        }
        return "launchctl asuser \(uid) sudo -u root softwareupdate --install \"\(label)\" \(base)"
    } else if macOSMajor == 12 && !as_ {
        return "launchctl asuser \(uid) sudo -u root softwareupdate --install \"\(label)\" \(base)"
    } else if isMacOS11 && as_ {
        return "echo ' ' | softwareupdate --install \"\(label)\" \(base)"
    } else {
        return "softwareupdate --install \"\(label)\" \(base)"
    }
}

// MARK: - Non-system updates

func softwareupdateNonSystemCmd(labels: String) -> String {
    let uid   = consoleUser().map { "\($0.uid)" } ?? "0"
    let uname = consoleUser()?.name ?? ""

    if isMacOS12orLater && userIsLoggedIn() {
        return "launchctl asuser \(uid) sudo -u \"\(uname)\" softwareupdate --install \"\(labels)\" --force --agree-to-license"
    } else if isMacOS12orLater {
        return "sudo -i softwareupdate --install \"\(labels)\" --force --agree-to-license"
    } else {
        return "softwareupdate --install \"\(labels)\" --force --agree-to-license"
    }
}

// MARK: - Safari update

func softwareupdateSafariCmd() -> String {
    let uid   = consoleUser().map { "\($0.uid)" } ?? "0"
    let uname = consoleUser()?.name ?? ""

    if isMacOS12orLater && userIsLoggedIn() {
        return "launchctl asuser \(uid) sudo -u \"\(uname)\" softwareupdate --install --safari-only --force --agree-to-license"
    } else if isMacOS12orLater {
        return "sudo -i softwareupdate --install --safari-only --force --agree-to-license"
    } else {
        return "softwareupdate --install --safari-only --force --agree-to-license"
    }
}
