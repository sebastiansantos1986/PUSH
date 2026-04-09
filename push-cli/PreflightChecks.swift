// PreflightChecks.swift — Preflight validation before showing popups or installing

import Foundation
import IOKit.ps

// MARK: - Preflight result

enum PreflightResult {
    case pass
    case fail(reason: String, uiState: String)

    var passed: Bool {
        if case .pass = self { return true }
        return false
    }
}

// MARK: - Preflight runner

struct PreflightChecks {
    let config: CLIConfig

    // MARK: - Full preflight (run before install)

    func runAll(availableGB: Double) -> PreflightResult {
        if let r = checkBattery()          { return r }
        if let r = checkDisk(availableGB)  { return r }
        return .pass
    }

    // MARK: - Battery check

    func checkBattery() -> PreflightResult? {
        let threshold = config.preflight.minBatteryPercent
        guard threshold > 0 else { return nil }

        let pct = currentBatteryPercent()
        let onAC = isOnACPower()

        cliLog("[Preflight] Battery: \(pct)% (AC: \(onAC))")

        // On AC power — only fail if battery is critically low
        if onAC && pct >= threshold { return nil }
        if onAC && pct < threshold {
            return .fail(
                reason: "Battery too low (\(pct)%). Minimum required: \(threshold)%",
                uiState: "preflightPower"
            )
        }
        // On battery — fail immediately, prompt to plug in
        return .fail(
            reason: "Not connected to AC power. Please plug in your charger.",
            uiState: "preflightPower"
        )
    }

    // MARK: - Disk check

    func checkDisk(_ availableGB: Double) -> PreflightResult? {
        let required = Double(config.preflight.minDiskSpaceGB)
        guard availableGB < required else { return nil }
        return .fail(
            reason: String(format: "%.1f GB available, %.0f GB required", availableGB, required),
            uiState: "preflightDisk"
        )
    }

    // MARK: - Network check (for download only)

    func checkNetworkReachability() -> Bool {
        guard config.preflight.checkNetworkReachability else { return true }
        let (_, status) = shell("curl -s --max-time 5 --head https://swscan.apple.com/content/catalogs/ > /dev/null 2>&1")
        let reachable = status == 0
        cliLog("[Preflight] Network reachability: \(reachable ? "OK" : "FAILED")")
        return reachable
    }

    // MARK: - VPN check

    func isOnVPN() -> Bool {
        guard config.preflight.skipOnVPN else { return false }
        // Check for common VPN interfaces
        let (output, _) = shell("ifconfig 2>/dev/null | grep -E '^(utun|ppp|tun|ipsec)[0-9]' | grep -v 'flags=8010'")
        let onVPN = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if onVPN { cliLog("[Preflight] VPN detected — skipping") }
        return onVPN
    }

    // MARK: - Available disk space

    static func availableDiskGB() -> Double {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let free  = attrs[.systemFreeSize] as? Int64
        else { return 0 }
        return Double(free) / 1_073_741_824
    }

    // MARK: - Battery helpers

    private func currentBatteryPercent() -> Int {
        let snapshot  = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources   = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            if let info = IOPSGetPowerSourceDescription(snapshot, source)?
                              .takeUnretainedValue() as? [String: Any],
               let pct  = info[kIOPSCurrentCapacityKey] as? Int {
                return pct
            }
        }
        return 100 // assume full if can't read
    }

    func isOnACPower() -> Bool {
        let snapshot  = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources   = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            if let info  = IOPSGetPowerSourceDescription(snapshot, source)?
                               .takeUnretainedValue() as? [String: Any],
               let state = info[kIOPSPowerSourceStateKey] as? String {
                return state == kIOPSACPowerValue
            }
        }
        return true // assume AC if can't read
    }
}


