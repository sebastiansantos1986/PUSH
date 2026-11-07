// PUSH - Proactive Update Scheduling Helper
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

import Foundation
import Darwin

/// Validate product OS metadata, never the installer's unrelated bundle version.
enum InstallerValidation {
    static func productVersion(in plist: URL) -> String? {
        guard let data = try? Data(contentsOf: plist),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = object as? [String: Any] else { return nil }
        if let image = dict["System Image Info"] as? [String: Any],
           let version = image["version"] as? String, numericOSVersion(version) != nil { return version }
        if let assets = dict["Assets"] as? [[String: Any]] {
            let versions = Set(assets.compactMap { $0["OSVersion"] as? String }.filter { numericOSVersion($0) != nil })
            if versions.count == 1 { return versions.first }
        }
        return nil
    }
    static func matches(_ installer: String, target: String) -> Bool {
        guard numericOSVersion(target) != nil,
              FileManager.default.isExecutableFile(atPath: installer + "/Contents/Resources/startosinstall") else { return false }
        let base = URL(fileURLWithPath: installer)
        for name in ["Contents/SharedSupport/InstallInfo.plist", "Contents/Resources/InstallInfo.plist"] {
            if let version = productVersion(in: base.appendingPathComponent(name)) { return sameOSVersion(version, target) }
        }
        // Modern installers hold MobileAsset product metadata in SharedSupport.dmg.
        let dmg = base.appendingPathComponent("Contents/SharedSupport/SharedSupport.dmg").path
        guard FileManager.default.fileExists(atPath: dmg) else { return false }
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("push-metadata-" + UUID().uuidString)
        do { try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: false,
                                                     attributes: [.posixPermissions: 0o700]) } catch { return false }
        defer { try? FileManager.default.removeItem(at: mount) }
        let (_, status) = runDirect("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path, dmg])
        guard status == 0 else { return false }
        defer { _ = runDirect("/usr/bin/hdiutil", ["detach", mount.path]) }
        guard let files = FileManager.default.enumerator(at: mount, includingPropertiesForKeys: nil) else { return false }
        var versions = Set<String>()
        for case let file as URL in files where ["xml", "plist"].contains(file.pathExtension) {
            if file.lastPathComponent.contains("MacSoftwareUpdate"), let version = productVersion(in: file) { versions.insert(version) }
        }
        return versions.count == 1 && versions.first.map { sameOSVersion($0, target) } == true
    }
    static func find(in directories: [String], target: String) -> String? {
        for directory in directories {
            guard let files = FileManager.default.enumerator(at: URL(fileURLWithPath: directory),
                includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in files {
                if url.pathExtension == "app" {
                    files.skipDescendants()
                    if url.lastPathComponent.hasPrefix("Install"), matches(url.path, target: target) { return url.path }
                }
            }
        }
        return nil
    }
}

func currentBootTimestamp() -> Double? {
    var boot = timeval(), size = MemoryLayout<timeval>.stride
    guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return nil }
    return Double(boot.tv_sec)
}

extension CLIDeferralState {
    mutating func beginInstallation(target: String, running: String, boot: Double?) {
        installStartedAt = Date()
        installOwnerPID = getpid()
        lastSeenVersion = running
        installTargetVersion = target
        installBootTimestamp = boot
        installStarted = true
        installCompleted = false
    }
    mutating func failInstallation() {
        installStarted = false
        installCompleted = false
        installTargetVersion = nil
        installBootTimestamp = nil
        installStartedAt = nil
        installOwnerPID = nil
    }
    /// Returns true only for a verified completion; an unsuccessful reboot releases retries.
    mutating func reconcileInstallation(running: String, boot: Double?, fallbackTarget: String) -> Bool {
        guard installStarted, !installCompleted else { return false }
        let rebooted = installBootTimestamp.flatMap { previous in boot.map { abs($0 - previous) > 1 } } ?? (running != lastSeenVersion)
        guard rebooted else { return false }
        let target = installTargetVersion ?? fallbackTarget
        if numericOSVersion(running) != nil, numericOSVersion(target) != nil,
           versionGTE(running, target), running != lastSeenVersion {
            installStarted = false
            installCompleted = true
            return true
        }
        failInstallation()
        return false
    }
}

func preparePushRuntime() -> Bool {
    let path = "/private/var/run/com.push"
    if mkdir(path, 0o755) != 0 && errno != EEXIST { return false }
    var info = stat()
    return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
        && info.st_uid == 0 && (info.st_mode & 0o022) == 0
}

// MARK: - Discovery policy and installation health
// Developer: Sebastian Santos

enum DiscoveryPolicy {
    static func deadline(config: CLIConfig, target: String, isMajor: Bool, firstSeen: Date) -> String {
        if !config.update.deadline.isEmpty { return config.update.deadline }
        if sameOSVersion(config.update.automaticDeadlineTarget, target), ISO8601DateFormatter().date(from: config.update.automaticDeadline) != nil {
            return config.update.automaticDeadline
        }
        let days = max(1, min(365, isMajor ? config.auto.majorDeadlineDays : config.auto.minorDeadlineDays))
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: firstSeen) ?? firstSeen.addingTimeInterval(Double(days) * 86400)
        return ISO8601DateFormatter().string(from: date)
    }
    static func eligible(version: String, beta: Bool, current: String, config: CLIConfig) -> Bool {
        guard numericOSVersion(version) != nil, !versionGTE(current, version),
              !(config.auto.skipBetas && beta), !config.auto.skipVersions.contains(version) else { return false }
        let currentMajor = Int(current.split(separator: ".").first ?? "0") ?? 0
        let targetMajor = Int(version.split(separator: ".").first ?? "0") ?? 0
        if currentMajor < config.auto.enforceMinimumMajorVersion && targetMajor < config.auto.enforceMinimumMajorVersion { return false }
        // Explicit minimum-major enforcement is an exception to the minor-only ceiling.
        let ceiling = max(currentMajor, config.auto.enforceMinimumMajorVersion)
        return !config.auto.minorOnly || targetMajor <= ceiling
    }
}

/// Returns nil when activity cannot be established safely. No installer is launched.
func installationIsActive() -> Bool? {
    let path = managedBase + "/install.lock"
    if FileManager.default.fileExists(atPath: path) {
        let fd = open(path, O_RDWR | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 { return errno == EWOULDBLOCK ? true : nil }
        flock(fd, LOCK_UN)
    }
    for name in ["startosinstall", "softwareupdate", "mist", "osinstallersetupd", "installer"] {
        let (_, result) = runDirect("/usr/bin/pgrep", ["-x", name])
        if result == 0 { return true }
        if result != 1 { return nil }
    }
    return false
}

extension CLIDeferralState {
    /// Recover only demonstrably obsolete flags. A modern staged install still waits for a reboot.
    mutating func recoverInstallation(running: String, boot: Double?, target: String, active: Bool?) -> String? {
        guard installStarted, active == false else { return nil }
        let intended = installTargetVersion ?? target
        if installCompleted && !intended.isEmpty && versionGTE(running, intended) {
            installStarted = false
            lastRecoveryMessage = "Cleared legacy pending flag; macOS already meets the completed target."
            return lastRecoveryMessage
        }
        if reconcileInstallation(running: running, boot: boot, fallbackTarget: target) {
            lastRecoveryMessage = "Verified completed macOS installation after restart."
            return lastRecoveryMessage
        }
        if !installStarted {
            lastRecoveryMessage = "The restart did not reach the target; installation may be retried."
            return lastRecoveryMessage
        }
        // Legacy flags with no target or boot evidence cannot represent a verified staged installation.
        // Only release these when no installer/lock is active and the owning workflow is gone.
        let ownerAlive = installOwnerPID.map { kill($0, 0) == 0 || errno == EPERM } ?? false
        if installTargetVersion == nil && installBootTimestamp == nil && !ownerAlive {
            failInstallation()
            lastRecoveryMessage = "Recovered obsolete installation flags without staging metadata; no installer is active."
            return lastRecoveryMessage
        }
        return nil
    }
}
