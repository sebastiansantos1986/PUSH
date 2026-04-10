# PUSH Roadmap

This document tracks what has been completed and what remains to be built.
Last updated: April 2026 — v1.1.0

---

## ✅ Completed (v1.1.0)

### Core Install Workflow
- [x] Update detection via `mdmclient` + `softwareupdate`
- [x] SOFA feed integration for accurate version info
- [x] mist-cli as primary download method for major upgrades
- [x] softwareupdate as fallback / primary for minor updates
- [x] Download resume — picks up where it left off
- [x] Dynamic progress tracking via `du` on installer file
- [x] mist-cli progress tracking via temp directory
- [x] `startosinstall` for major upgrades
- [x] Native pending update path for minor updates
- [x] `caffeinate` during install to prevent sleep
- [x] Post-install `jamf recon` so EA updates immediately

### UI & User Experience
- [x] SoftNudge popup (once per day)
- [x] HardBlock popup (deadline passed / deferrals exhausted)
- [x] Toast notification (every hour)
- [x] Download progress popup with real % tracking
- [x] Installing popup with time-based progress + countdown
- [x] Rebooting countdown (minor updates)
- [x] Password prompt (Apple Silicon)
- [x] Disk space preflight popup
- [x] Power preflight popup
- [x] Error popup with specific message
- [x] Compliant popup
- [x] Personalized toast greeting using logged-in user name
- [x] `\n` newline support in all message fields
- [x] Auto-sizing toast height based on content
- [x] Solid opaque card design (no glass/transparency issues)

### Schedule & Timing
- [x] Nudge once per day (24h lock before popup opens)
- [x] Toast every hour between nudges
- [x] Alert window (default 8am–6pm weekdays)
- [x] Meeting/presentation detection
- [x] VPN detection
- [x] Concurrent daemon run protection (lock before showing popup)

### Preflight Checks
- [x] Disk space check (default 40 GB minimum)
- [x] Battery/AC power check
- [x] Network reachability check
- [x] Installer Gatekeeper validation before password prompt
- [x] startosinstall failure detection + error popup

### Authentication (Apple Silicon)
- [x] System Keychain credential storage (`push-cli auth`)
- [x] Password priority: Keychain → config.yaml → prompt user
- [x] No deprecated SecKeychain APIs (uses `security` CLI)

### Jamf Integration
- [x] Extension Attribute reporting after every auto-check
- [x] `jamf recon` after successful upgrade
- [x] Post-install script template
- [x] OAuth support (Jamf Pro 10.48+)
- [x] Legacy API account fallback

### CLI
- [x] `auto-check` with `--force` and `--dry-run`
- [x] `status` — full compliance + daemon + auth info
- [x] `install`, `download`, `install-extras`, `install-safari`
- [x] `auth set-password / show / clear`
- [x] `install-daemon --interval` with validation (1m–24h)
- [x] `config show / get / set / validate`
- [x] `popup <state>` for all UI states
- [x] `reset`, `reset --deferrals-only`
- [x] `log show / tail / clear`
- [x] `report --json / --csv`
- [x] `self-update --check`
- [x] `mdm push / download / check / recon / fix-swu`
- [x] `grace grant / status / revoke`
- [x] `debug on / off / status`

### Deployment
- [x] `build-pkg.sh` — builds signed pkg with version bump
- [x] `postinstall` — installs mist-cli, loads daemon, creates symlink
- [x] `preinstall` — safely unloads existing daemon
- [x] `push-uninstall.sh` — full removal including keychain + mist-cli
- [x] LaunchDaemon using full binary path (not symlink)
- [x] `launchctl bootstrap/bootout` (replaces deprecated load/unload)

### Documentation
- [x] README.md with full feature overview
- [x] GitHub Wiki (8 pages)
- [x] Screenshots for all popup states
- [x] config.yaml reference
- [x] CLI reference
- [x] Jamf integration guide
- [x] Apple Silicon setup guide
- [x] Troubleshooting guide

---

## 🔲 Remaining / Future Work

### Self-Update Mechanism
- [ ] Decide on hosting: GitHub Releases, S3, or Jamf handles updates
- [ ] If GitHub: create release workflow, tag releases, upload push-cli as asset
- [ ] If S3/custom: host a JSON feed with latest version + download URL
- [ ] Set `selfUpdateURL` in config.yaml once hosting is decided
- [ ] Test `push-cli self-update` end to end
- [ ] Add `self-update --check` to Jamf EA for version tracking

### Jamf EA — Richer Fleet Data
- [ ] EA script to pull `state.json` fields (deferral count, last nudge, install started)
- [ ] EA for PUSH version installed (useful for tracking rollout)
- [ ] EA for next deadline date
- [ ] Jamf Smart Group: "PUSH Deadline This Week"
- [ ] Jamf Smart Group: "PUSH Not Installed"

### Fleet Dashboard
- [ ] Decide on infrastructure (AWS Lambda + S3, or existing web server)
- [ ] Each Mac POSTs status JSON to collector endpoint after auto-check
- [ ] Collector stores per-machine: serial, version, compliance, deferrals, deadline
- [ ] Dashboard UI — compliance % across fleet, non-compliant list, deadline countdown
- [ ] Add `auto.adminWebhookURL` to config and test end to end

### MDM Push
- [ ] Test `push-cli mdm push` against real Jamf instance
- [ ] Test `push-cli mdm download` workflow
- [ ] Validate Bootstrap Token handling

### Power Preflight Screenshot
- [ ] Capture screenshot of `preflightPower` popup for wiki
- [ ] Needs laptop disconnected from power (or VM with battery simulation)
- [ ] Add to `screenshots/` folder and update User-Experience wiki page

### Minor Polish
- [ ] `push-cli install-daemon --interval` show current interval if no flag given
- [ ] `push-cli status` show PUSH binary build date
- [ ] Silent mode for VDI / kiosk machines with no console user
- [ ] Config option to customize deferral reasons list

---

## Notes for Next Session

**Self-update decision needed:**
The `SelfUpdateCommand.swift` is complete and working. Just needs a URL.
Options:
1. GitHub Releases — tag each version, upload `push-cli` binary as release asset, set `selfUpdateURL: "https://api.github.com/repos/sebastiansantos1986/PUSH/releases/latest"`
2. Jamf — skip self-update, use Jamf policies to push new pkg versions

**Dashboard decision needed:**
The per-machine data exists in `state.json` and logs. Need a central collector.
Simplest path: AWS API Gateway + Lambda + DynamoDB, each Mac POSTs after auto-check.

**Files to know:**
- Source: `PUSH-fixed/` — Xcode project
- Deployment: `PUSH-deployment-fixed/` — pkg build scripts
- DerivedData: `/Users/sebastian.santos/Library/Developer/Xcode/DerivedData/PUSH-cnhckvdfyqdhccbsqgurbxciigjw/Build/Products/Debug`

**Deploy command:**
```bash
export DEBUG="/Users/sebastian.santos/Library/Developer/Xcode/DerivedData/PUSH-cnhckvdfyqdhccbsqgurbxciigjw/Build/Products/Debug"
sudo cp "$DEBUG/push-cli" /Library/Management/PUSH/push-cli
sudo cp -r "$DEBUG/push-ui.app" /Library/Management/PUSH/push-ui.app
sudo chmod +x /Library/Management/PUSH/push-cli
```
