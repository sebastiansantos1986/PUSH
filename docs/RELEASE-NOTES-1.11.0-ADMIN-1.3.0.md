# PUSH 1.11.0 / Admin 1.3.0 / JamfCheckIn 1.1.1

Developer: Sebastian Santos · Test prerelease

Adds configurable major-demo/notice size, banner image/text and runtime user greetings; isolated informational one-off alerts/toasts inspired by Regina Pro; explicit Apple catalog refresh and local hardware assessment; and an isolated major-offer-only package profile. Confirmed unsupported hardware stops the full required major-upgrade workflow before downloading and cannot enter automatic retries.

The major-offer flow remains **debug/simulation only**. No live optional download, install or restart route is enabled. Major-only excludes Admin, JamfCheckIn, normal enforcement UI, launch jobs and permission profiles. Installing it over full PUSH replaces reviewed YAML after backup and pauses PUSH monitors. The original Regina project was not modified or imported wholesale.

## Downloads

- PUSH-Admin-1.3.0.pkg: IT workstation; includes the matching full client for package building.
- PUSH-Client-1.11.0.pkg: generic full endpoint client with JamfCheckIn 1.1.1; preserves existing YAML and leaves monitors paused.
- PUSH-Major-Offer-Only-1.11.0.zip: ready major-only preview package, default greeting/layout and real Apple catalog snapshot.
- Source ZIP, detailed guide, verification report and SHA-256 checksums.

## Verification

387 engine + 362 Admin/package-profile + 15 JamfCheckIn offline checks passed. A separate 354-check run built the ready package with real Apple data. Universal builds, signatures, embedded client and package contents were inspected. No GUI, installer, live credential operation, monitor, upgrade, registration, wallpaper change or restart was run. Native UI and managed session delivery need a pilot.

Apps are ad-hoc signed; installers are unsigned. Production signing/notarization and managed upgrade authorization remain prerequisites. Apple snapshot assessment can be unverified when stale/missing/unrecognized; major-family support does not establish minimum build or install authorization.
