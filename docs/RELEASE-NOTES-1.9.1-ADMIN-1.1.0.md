# PUSH 1.9.1 / Admin 1.1.0 / JamfCheckIn 1.1.0

Developer: Sebastian Santos · macOS 14+ · Intel and Apple Silicon · test prerelease.

This release separates employee client deployment from the IT-only console. PUSH Admin now builds one configured installer containing PUSH, JamfCheckIn, reviewed YAML and staged branding, with explicit paused/live installation modes. Setup suggestions explain tracking, reminder timing, deadlines, support and prerequisite gaps before admins apply changes to the draft.

- JamfCheckIn integrates saved PUSH status/progress/recovery and guarded update requests without a PUSH password prompt; no second menu app.
- Deadline failure recovery adds saved reasons, absolute countdowns, guarded retries, spacing and daily limits.
- Around-clock reminder defaults, logged-out deadline preparation, compliance wallpaper and saved delivery history are included.
- Generic clients preserve current YAML and pause monitors. Configured installers replace reviewed YAML after backup; live mode defers first checks five minutes.
- Profiles accompany the package for MDM delivery. Optional restart automation requires the matching production-signed executable; no broad privacy grants.
- Existing native popups, approved app updates, Entra reminders, readiness and Sebastian Santos attribution are retained.

## Downloads

- **PUSH-Admin-1.1.0.pkg:** IT workstation only; includes the matching generic client as an export resource, not an auto-installed component.
- **PUSH-Client-1.9.1.pkg:** generic employee/pilot client; engine + JamfCheckIn, safe fresh defaults, existing YAML preserved, monitors paused.
- **PUSH-1.9.1-Admin-1.1.0-Source.zip:** active source and documentation.
- **PUSH-Admin-1.1.0-Guide.txt**, **PUSH-Client-Admin-Guide.txt:** setup and installation.
- Verification JSON files and **PUSH-1.9.1-Admin-1.1.0.sha256**.

Generate your custom **PUSH-Configured-Client.pkg** inside Admin. It replaces policy after backup and uses the reviewed installation mode; it is not a preconfigured fleet policy downloaded from this release.

## Verification and limits

671 offline checks passed: engine 343, Admin/package-builder 313, JamfCheckIn 15. Universal builds, ad-hoc signatures, source parity/attribution and package contents were verified. Both configured modes were built/inspected without executing either installer. No app, profile, live request, monitor, download/upgrade, registration, wallpaper change or restart was executed.

These are unsigned local test installers with ad-hoc signed binaries. Developer ID signing/notarization, MDM profile acceptance, optional restart TCC attribution, managed authorization and native GUI/install/reboot behavior still need a managed pilot. Selected external providers and registration products remain separate prerequisites.
