# JamfCheckIn — Deployment Kit

Bundle ID: `com.sebastianitconsulting.jamfcheckin`

This folder has everything to get the app onto your fleet and verify it's working.

## What's here
- `build_and_package.sh` — builds, signs (Developer ID), notarizes, and produces a
  signed `.pkg` that installs the app to `/Applications` and the LaunchAgent to
  `/Library/LaunchAgents`.
- `com.sebastianitconsulting.jamfcheckin.plist` — managed LaunchAgent so the menu
  bar app launches at login for every user (and relaunches if quit).
- `JamfCheckIn-extension-attribute.sh` — Jamf Extension Attribute reporting install
  + running status, for Smart Groups.
- `JamfCheckIn-notifications.mobileconfig` — config profile that pre-authorizes
  notifications so users aren't prompted and stale alerts show.

## You must fill in (Apple Developer account specifics)
In `build_and_package.sh`:
- `TEAM_ID` — your 10-character Apple Developer Team ID.
- `DEV_ID_INSTALLER` — your "Developer ID Installer" certificate name. Find installed
  identities with: `security find-identity -v -p codesigning` and
  `security find-identity -v` (installer certs).
- `NOTARY_PROFILE` — created once with `xcrun notarytool store-credentials` (see the
  comment block at the top of the script).

You also need a "Developer ID Application" certificate in your keychain (Xcode can
create both from your Apple Developer account: Settings → Accounts → Manage Certificates).

## Order of operations
1. Open the Xcode project and set the target's Signing team to your account (it's
   already set to bundle ID `com.sebastianitconsulting.jamfcheckin`, Hardened Runtime
   on, App Sandbox off — leave those as-is).
2. Run `./build_and_package.sh`. You'll get `build/JamfCheckIn-1.0.pkg`.
3. Upload that `.pkg` to Jamf and create a policy (scope to a small **pilot** Smart
   Group first) to install it.
4. Upload `JamfCheckIn-extension-attribute.sh` as an Extension Attribute (type:
   String). Create Smart Groups like "JamfCheckIn — Not installed" and
   "— Installed not running" to watch rollout.
5. Upload `JamfCheckIn-notifications.mobileconfig` as a Configuration Profile (or
   rebuild it in Jamf's Notifications payload using the same bundle ID).
6. Verify on the pilot machines, then widen the policy + profile scope to the fleet.

## Verifying on a single Mac
- Installed: `ls -d /Applications/JamfCheckIn.app`
- Running:   `pgrep -x JamfCheckIn`
- LaunchAgent loaded for the logged-in user:
  `launchctl print gui/$(id -u)/com.sebastianitconsulting.jamfcheckin`
- The menu bar shield should be visible (the app has no other UI, so "running" ==
  "visible").

## Notes / caveats
- **Notifications profile** requires the Mac be MDM-enrolled; for it to silently take
  effect without user interaction the device generally needs to be supervised
  (Automated Device Enrollment). On user-approved enrollment it may still prompt.
- The in-app "Launch at login" toggle is per-user convenience; the managed
  LaunchAgent is what guarantees fleet-wide presence. They can coexist.
- The app reads `/var/log/jamf.log` and runs `jamf`, `fdesetup`, `profiles`, etc.,
  so it must stay **unsandboxed** (already configured). Hardened Runtime is on, which
  notarization requires and which doesn't block any of these.
- Firewall state and the Check-in/Inventory buttons still need root — pair this with
  the no-prompt helper (LaunchDaemon or sudoers) we discussed so those work silently.
