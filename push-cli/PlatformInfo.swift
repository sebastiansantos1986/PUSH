// ==============================================================================
// PUSH - Proactive Update Scheduling Helper
//
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
//
// Component: PlatformInfo.swift
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
// ==============================================================================

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
