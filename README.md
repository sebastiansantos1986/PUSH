# PUSH — Proactive Update Scheduling Helper

A macOS update enforcement tool for Jamf-managed environments.

Nudges users to install required macOS updates with a friendly UI, escalates to forced installs when deadlines pass, and reports compliance status to Jamf for fleet-wide visibility.

**Current status:** v1.1 pilot-ready (May 2026). Verified end-to-end on Apple Silicon VMs upgrading 15.0 → 26.4.1.

---

## Repository structure

This repo contains four related top-level folders:

| Folder | Purpose |
|---|---|
| `push-cli/`, `push-ui/` | Swift source code for the daemon and UI app |
| `PUSH-deployment-fixed/` | Package builder — produces the installable `.pkg` |
| `jamf-setup/` | Automation script that creates the EA and Smart Groups in Jamf |
| `jamf-ea-fix/` | Automation script that updates existing EA scripts in Jamf |

`PUSH.xcodeproj`, `config.yaml`, and the Swift source folders make up the application itself. The other folders are operational tooling for getting PUSH into a Jamf-managed fleet.

---

## What PUSH does

`push-cli` is a root daemon that runs every hour via LaunchDaemon. On each run it:

1. Detects available macOS updates (via `mdmclient` + `softwareupdate`)
2. Decides whether the Mac is compliant against your configured `targetVersion`
3. Manages the nudge/deadline lifecycle for non-compliant Macs
4. Triggers forced install + reboot once the deadline passes
5. Reports compliance state to Jamf via Extension Attributes

`push-ui` is a SwiftUI app that surfaces popups and toasts to the user — soft nudges, deadline reminders, install progress, reboot prompts, etc.

---

## Features

**Update enforcement**
- Soft nudge once per day until deadline (configurable interval)
- Toast notification every hour between nudges
- Forced install at deadline — runs `startosinstall` silently (no popup, no opt-out)
- mist-cli integration for major OS upgrades (downloads installer reliably)
- Native `softwareupdate` for minor security updates
- Auto-installs non-system updates (Safari, XProtect, etc.) without nudging
- Skips forced install during active screen-share to avoid disrupting meetings

**Apple Silicon credential handling**
- End-user password capture during soft-nudge engagement (super.app pattern)
- Storage in System Keychain — no plaintext anywhere on disk
- Secure-token preflight before install attempts

**Compliance signaling**
- Compliance wallpaper switching — desktop background changes when Mac falls out of compliance, restores on success
- Uptime monitoring — separate two-phase reboot reminders for Macs that stay up too long
- Jamf EA reporting after every auto-check
- Auto-recon on detection and after successful upgrades

**Date picker scheduling**
- Users can choose when to install — any time before the deadline
- Once scheduled, install runs silently at the chosen time
- After deadline: scheduling not allowed, install fires automatically

---

## Requirements

- macOS 13.0 Ventura or later
- Apple Silicon (Intel currently untested)
- Jamf Pro (optional but recommended for fleet visibility)
- mist-cli 2.2+ (bundled in the deployment .pkg, lazy-installed at first use)
- desktoppr (bundled in the deployment .pkg, lazy-installed if wallpaper switching is enabled)
- Xcode 15+ to build from source

---

## Installation

### Option 1 — Deploy via Jamf (recommended)

```bash
# 1. Build the project in Xcode
#    Open PUSH.xcodeproj, select push-cli + push-ui targets, build for Debug or Release

# 2. Build the .pkg
cd PUSH-deployment-fixed
./build-pkg.sh

# 3. Upload PUSH-1.1.0.pkg to Jamf
#    Settings → Computer Management → Packages → Upload

# 4. Create a policy
#    Computers → Policies → New
#    Add the .pkg, scope to your test group, set trigger and frequency
```

The postinstall script handles:
- Creating `/Library/Management/PUSH/`
- Loading the LaunchDaemon
- Creating `/usr/local/bin/push-cli` symlink
- Lazy-installing mist-cli on first use
- Lazy-installing desktoppr if wallpaper switching is enabled

### Option 2 — Manual install (for dev/testing)

```bash
sudo /usr/sbin/installer -pkg PUSH-1.1.0.pkg -target /
```

That's it. The .pkg handles everything.

---

## Configuration

`/Library/Management/PUSH/config.yaml` is the policy file. Edit it directly or via `push-cli config set`.

### Key sections

```yaml
update:
  targetVersion: ""              # Set this to enforce a specific OS version
  deadline: ""                   # Auto-calculated, or set ISO 8601 manually
  maxDeferrals: 5

auto:
  enabled: true
  intervalSeconds: 3600          # 1 hour — auto-check frequency
  minorDeadlineDays: 5           # Days from detection until deadline (minor)
  majorDeadlineDays: 7           # Days from detection until deadline (major)
  minorMaxDeferrals: 5
  majorMaxDeferrals: 7
  autoInstallAfterDeadline: true # Forced install when deadline passes
  skipDuringMeetings: true       # NUDGE skip only — post-deadline still fires

ui:
  appName: "Software Update Required"
  majorMessage: "A major macOS upgrade is required..."
  minorMessage: "A security update is available..."

schedule:
  alertStartHour: 8              # Only show nudges between 8am and 6pm
  alertEndHour: 18
  skipWeekends: true
  skipDuringMeetings: true       # Suppresses nudges; post-deadline still fires

preflight:
  minDiskSpaceGB: 40
  minBatteryPercent: 0           # 0 = disabled

jamf:
  url: ""
  eaName: "PUSH — OS Update Compliance EA"
  binaryPath: "/usr/local/bin/jamf"
  reportEAAfterCheck: true

compliance:                      # Wallpaper switching
  wallpaperEnabled: true
  compliantWallpaper:    "/Library/Management/PUSH/Compliance-Background/compliant.jpg"
  nonCompliantWallpaper: "/Library/Management/PUSH/Compliance-Background/non-compliant.jpg"
  wallpaperBackgroundColor: "020C19"
  wallpaperScale: "fit"

uptime:                          # Reboot reminders for compliant Macs
  enabled: false
  warningThresholdDays: 14
  forceThresholdDays: 21
```

### Editing config

```bash
sudo push-cli config set update.targetVersion "26.4.1"
sudo push-cli config get compliance.wallpaperEnabled
sudo push-cli config show
```

---

## CLI reference

### Detection & compliance
```
push-cli auto-check                 Run nudge schedule + Jamf EA report
push-cli auto-check --force         Bypass alert window, run immediately
push-cli check                      Silent check — exits 0=compliant, 1=non-compliant
push-cli status                     Show current compliance state
```

### Install
```
push-cli install                    Begin install workflow
push-cli download                   Download installer only
push-cli install-extras             Install non-OS updates (Safari, XProtect)
```

### Auth (Apple Silicon)
```
push-cli auth set-password          Store admin password in System Keychain
push-cli auth show-user-password    Show user-saved password status
push-cli auth show                  Show admin credential status
push-cli auth clear                 Remove stored credentials
```

### Wallpaper (compliance signaling)
```
push-cli wallpaper enable           Turn on compliance wallpaper switching
push-cli wallpaper disable          Turn off wallpaper switching
push-cli wallpaper apply <state>    Force apply (compliant|non-compliant|auto)
push-cli wallpaper status           Show wallpaper config and last-applied state
push-cli wallpaper install-desktoppr   Lazy-install desktoppr from bundled pkg
```

### Daemon
```
push-cli install-daemon             Install LaunchDaemon (default 1h interval)
push-cli install-daemon --interval 2h
push-cli uninstall-daemon
```

### Config
```
push-cli config show
push-cli config get <key>
push-cli config set <key> <value>
push-cli config validate
```

### Popups (testing UI without waiting)
```
push-cli popup softNudge
push-cli popup hardBlock
push-cli popup toast
push-cli popup downloading --download-progress 0.5
push-cli popup installing
push-cli popup preflightDisk --disk-available 8 --disk-required 40
push-cli popup error --error "Something went wrong"
```

### Maintenance
```
push-cli reset                      Clear all state
push-cli reset --deferrals-only
push-cli log show
push-cli log tail
push-cli log clear
push-cli report                     Generate compliance report
push-cli self-update                Check for and apply PUSH updates
```

---

## Jamf integration

PUSH is designed to work tightly with Jamf Pro for fleet-wide compliance reporting.

### Quick setup — automated

Use the automation scripts in `jamf-setup/` to create the Jamf objects in one command:

```bash
cd jamf-setup
./setup-jamf.sh \
    --jamf-url https://yourtenant.jamfcloud.com \
    --client-id YOUR_API_CLIENT_ID
```

The script:
- Authenticates with Jamf via OAuth
- Creates the OS Update Compliance Extension Attribute (if missing)
- Creates 5 Smart Computer Groups for filtering compliance state
- Asks per-object confirmation before any change
- Verifies each object after creation

See `jamf-setup/JAMF-SETUP.md` for the manual fallback path and `jamf-setup/SMART-GROUPS.md` for what each Smart Group does.

### Updating existing EAs

If you've already deployed PUSH and need to push fixes to your existing EA scripts, use:

```bash
cd jamf-ea-fix
./update-jamf-eas.sh \
    --jamf-url https://yourtenant.jamfcloud.com \
    --client-id YOUR_API_CLIENT_ID
```

This updates the EA script payload in Jamf without changing the EA's name, ID, or downstream Smart Group references. Backups of the previous script are saved to `jamf-ea-fix/ea-backups/` before each update.

### Required API client privileges

The setup scripts need an OAuth API client with:
- Read + Create + Update Computer Extension Attributes
- Read + Create + Update Smart Computer Groups
- Read Computers

Create the client in: Jamf Pro → Settings → User Accounts and Groups → API Roles and Clients

### Smart Groups

The setup creates these by default — adjust criteria in Jamf web UI as needed:

| Group | Filters |
|---|---|
| PUSH: Compliant | EA equals "Compliant" |
| PUSH: Non-Compliant - Active | EA contains "Non-Compliant" AND NOT "Past Deadline" |
| PUSH: Past Deadline | EA contains "Past Deadline" |
| PUSH: Install In Progress | EA contains "Install Started" |
| PUSH: Not Reporting | EA is "Not Installed" or blank |

---

## Update flow

```
LaunchDaemon fires (every 1h)
    ↓
auto-check runs
    ↓
mdmclient + softwareupdate detect available updates
    ↓
First detection?
    YES → set deadline (5 days minor / 7 days major), show softNudge
    NO  → continue lifecycle below
    ↓
Within alert window (8am–6pm, weekdays)?
    NO  → quiet mode (Jamf EA still updates), exit
    YES → continue
    ↓
Past deadline?
    YES → forced install (silent, mist-cli + startosinstall)
          ↓ (skipped if user is screen-sharing)
    NO  → toast every hour, soft nudge once per day
    ↓
User engages soft nudge
    ↓
"Begin Upgrade" → preflight checks → install
"Schedule"     → date picker (capped at deadline) → install at chosen time
"Later"        → deferral counted, schedule continues
    ↓
Install starts
    ↓
caffeinate prevents sleep
mist-cli downloads (major) OR softwareupdate runs (minor)
    ↓
startosinstall runs → reboot
    ↓
Mac comes back at target version
    ↓
Next auto-check → jamf recon → EA shows "Compliant"
    ↓
Wallpaper transitions back to compliant background
```

---

## Files & paths

| Path | Purpose |
|---|---|
| `/Library/Management/PUSH/push-cli` | Daemon binary |
| `/Library/Management/PUSH/push-ui.app` | UI popup app |
| `/Library/Management/PUSH/config.yaml` | Policy configuration (operator-edited) |
| `/Library/Management/PUSH/state.json` | Runtime state (deferrals, dates, install status) |
| `/Library/Management/PUSH/logs/push.log` | Main log |
| `/Library/Management/PUSH/logs/push-cli.log` | Daemon stdout |
| `/Library/Management/PUSH/Compliance-Background/` | Wallpaper images and desktoppr.pkg |
| `/Library/LaunchDaemons/com.push.autoupdate.plist` | LaunchDaemon |
| `/usr/local/bin/push-cli` | Symlink to daemon binary |

---

## Uninstall

```bash
sudo bash PUSH-deployment-fixed/push-uninstall.sh              # Full removal
sudo bash PUSH-deployment-fixed/push-uninstall.sh --keep-logs  # Preserve logs
sudo bash PUSH-deployment-fixed/push-uninstall.sh --keep-mist  # Preserve mist-cli install
```

---

## Building from source

```bash
# 1. Open the project
open PUSH.xcodeproj

# 2. In Xcode: select push-cli scheme → Build (⌘B)
#              select push-ui scheme → Build (⌘B)

# 3. Binaries land in DerivedData. Find your build path:
ls ~/Library/Developer/Xcode/DerivedData/PUSH-*/Build/Products/Debug/

# 4. Quick deploy to local Mac for testing
DEBUG=~/Library/Developer/Xcode/DerivedData/PUSH-XXXX/Build/Products/Debug
sudo cp "$DEBUG/push-cli" /Library/Management/PUSH/push-cli
sudo cp -R "$DEBUG/push-ui.app" /Library/Management/PUSH/push-ui.app
sudo chmod +x /Library/Management/PUSH/push-cli

# 5. Verify changes landed
strings /Library/Management/PUSH/push-cli | grep "<a unique string from your changes>"
```

For producing a deployable .pkg, use `PUSH-deployment-fixed/build-pkg.sh` which packages the binaries with mist-cli and desktoppr bundled.

---

## License

MIT — see LICENSE.

## Acknowledgements

PUSH stands on the shoulders of incredible work from the Mac Admins community. Genuine thanks to the people and projects below — without them, building this would have been a much harder road.

- **[mist-cli](https://github.com/ninxsoft/mist-cli)** by Nindi Gill ([@ninxsoft](https://github.com/ninxsoft)) — the macOS installer downloader that makes major OS upgrades reliable
- **[desktoppr](https://github.com/scriptingosx/desktoppr)** by Armin Briegel ([@scriptingosx](https://github.com/scriptingosx)) — the desktop wallpaper tool used for compliance signaling
- **[SOFA](https://sofa.macadmins.io/)** by [Mac Admins Open Source](https://github.com/macadmins/sofa) — Simple Organized Feed for Apple Software Updates, the canonical source for macOS release information
- **[nudge](https://github.com/macadmins/nudge)** by Erik Gomez ([@erikng](https://github.com/erikng)) and the [Mac Admins community](https://github.com/macadmins/nudge/graphs/contributors) — pioneering work on user-respectful update enforcement
- **[super (S.U.P.E.R.M.A.N.)](https://github.com/Macjutsu/super)** by Kevin M. White ([@Macjutsu](https://github.com/Macjutsu)) — comprehensive update orchestration that inspired our deferral and password-capture flows
