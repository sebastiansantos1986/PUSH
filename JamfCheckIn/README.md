# PUSH Client / Admin separation

Developer: Sebastian Santos · Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

Current delivery: PUSH Client 1.9.1 (engine + JamfCheckIn 1.1.0) and PUSH Admin 1.0.0 (IT only). Client Macs do not receive the admin console or a second menu app. PUSH Admin → Deployment exports a client/policy/assets/profile bundle. No component is launched or activated by the local-test installer. Production Developer ID signing and notarization remain required before fleet rollout.

The original Desktop projects are unchanged. Existing functionality is retained; PUSH requests use the guarded user channel. Jamf check-in/inventory administration is separate. See the delivered Client-Admin guide and exported READ-ME-FIRST for activation and profile scope.

## Previous project documentation

# JamfCheckIn (v2)

A macOS **menu bar** app (no Dock icon) that shows Jamf check-in status plus key
device facts at a glance, and lets you trigger a check-in or inventory update.

## What it shows
- **Last check-in** and **last inventory** (parsed from `/var/log/jamf.log`)
- **Check in now** / **Update inventory** buttons (run `jamf policy` / `jamf recon`)
- **Stale alert**: a macOS notification when no check-in for 48h (once per episode)
- **Launch at login** toggle
- Device panel: **macOS version**, **disk used/total**, **battery % + health,
  max-capacity estimate, cycle count**, **last reboot/uptime**, **FileVault**,
  **MDM enrollment**, and **Jamf server URL + reachability**

Menu-bar icon: check = checked in within 24h, exclamation = older than 24h,
question mark = no log / no entries. Thresholds live in JamfMonitor.swift.

## Requirements
- macOS 13.0+ (uses MenuBarExtra and SMAppService)
- Xcode 15+

## Open & run
1. Unzip, double-click **JamfCheckIn.xcodeproj**.
2. Press **Run** (Cmd-R). The shield icon appears at the top-right; click for details.
3. If Xcode shows a signing error, open **Signing & Capabilities** and select your
   team (or "Sign to Run Locally").

## Permissions, by feature
- **Reading status** (check-in, OS, disk, battery, reboot, FileVault, server URL):
  no admin rights needed. /var/log/jamf.log is world-readable on managed Macs.
- **Check in now / Update inventory**: the jamf binary needs root, so these show
  the standard macOS admin password prompt (via osascript "with administrator
  privileges"). Nothing is stored.
- **Notifications**: macOS asks once for permission. Granting it enables stale alerts.
- **Launch at login**: works best once the app lives in /Applications. Toggling
  from Xcode's build folder registers that temporary path; re-toggle after moving it.

App Sandbox is intentionally **off** -- required to read system logs and run the
jamf, fdesetup, and profiles tools. Keep it off if you edit build settings.

## Notes / caveats
- This reflects the **local agent** view. The Jamf Pro **server's** last-contact
  time can differ; that requires the Jamf Pro API (URL + credentials).
- MDM enrollment uses "profiles status -type enrollment"; on some macOS versions
  that needs root and will show "Unknown" without it.
- Battery max-capacity % is an estimate from IORegistry (AppleRawMaxCapacity /
  DesignCapacity) and may differ slightly from System Settings.
- Inventory-time parsing is best-effort; jamf.log phrasing varies by Jamf version.
- I could not compile this against Apple's SDK in my environment, so treat the first
  build as a smoke test. If anything does not compile, paste the error and I'll fix it.
