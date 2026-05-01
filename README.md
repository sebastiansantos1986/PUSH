# PUSH — Proactive Update Scheduling Helper

<p align="center">
  <img src="push-ui/InstallAssistant.icns" width="128" alt="PUSH icon">
</p>

<p align="center">
  <strong>A macOS update enforcement tool for Jamf-managed environments.</strong><br>
  Nudges users to install required macOS updates with a friendly UI, escalating to hard blocks when deadlines pass.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-blue" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/Jamf-10.48%2B-green" alt="Jamf 10.48+">
  <img src="https://img.shields.io/badge/version-1.1.0-brightgreen" alt="Version 1.1.0">
</p>

---

## Overview

PUSH is a two-component macOS tool:

- **`push-cli`** — A command-line daemon that detects available updates, manages the nudge schedule, and orchestrates the install workflow
- **`push-ui`** — A SwiftUI popup/notification app that surfaces update prompts to users

PUSH is designed to work alongside Jamf Pro. It detects updates via Apple's `softwareupdate` and `mdmclient`, downloads major upgrades using [mist-cli](https://github.com/ninxsoft/mist-cli), and reports compliance status back to Jamf via Extension Attributes.

---

## Features

- 🔔 **Soft nudge** once per day with a customizable message
- 🔔 **Toast notification** every hour between nudges
- 🔒 **Hard block** when deadline passes or deferrals are exhausted
- 📥 **mist-cli integration** for reliable major upgrade downloads
- 🔐 **Apple Silicon support** with System Keychain credential storage
- 📊 **Jamf EA reporting** after every compliance check
- ⚡ **Auto-recon** after successful upgrade
- 🛡️ **Preflight checks** for disk space, battery, and network
- ☕ **caffeinate** during install to prevent sleep
- 🔄 **Download resume** — picks up where it left off if interrupted

---

## Requirements

- macOS 13.0 Ventura or later
- Jamf Pro (optional but recommended)
- [mist-cli 2.2+](https://github.com/ninxsoft/mist-cli/releases) for major upgrades
- Xcode 15+ to build from source

---

## Installation

### Option 1 — Deploy via Jamf (Recommended)

1. **Build the project** in Xcode (select `push-cli` and `push-ui` targets, build for Release)

2. **Copy binaries** into the deployment folder:
```bash
cp -r /path/to/DerivedData/.../push-ui.app PUSH-deployment/pkg-build/payload/Library/Management/PUSH/
cp /path/to/DerivedData/.../push-cli PUSH-deployment/pkg-build/payload/Library/Management/PUSH/
```

3. **Add mist-cli** to the payload:
```bash
cp mist-cli.2.2.pkg PUSH-deployment/pkg-build/payload/Library/Management/PUSH/
```

4. **Build the pkg**:
```bash
cd PUSH-deployment
bash build-pkg.sh
```

5. **Upload `PUSH-1.1.0.pkg`** to Jamf and deploy as a policy.

The postinstall script automatically:
- Installs mist-cli
- Loads the LaunchDaemon
- Creates the `/usr/local/bin/push-cli` symlink

### Option 2 — Manual Install

```bash
sudo mkdir -p /Library/Management/PUSH
sudo cp push-cli /Library/Management/PUSH/
sudo cp -r push-ui.app /Library/Management/PUSH/
sudo chmod +x /Library/Management/PUSH/push-cli
sudo ln -sf /Library/Management/PUSH/push-cli /usr/local/bin/push-cli
sudo push-cli install-daemon --interval 1h
```

---

## Configuration

The config file lives at `/Library/Management/PUSH/config.yaml`. Key settings:

```yaml
update:
  targetVersion: ""              # Set automatically by auto-check
  toastIntervalSeconds: 3600     # Toast every 1 hour
  nudgeIntervalSeconds: 86400    # Nudge once per day
  requirePasswordOnAppleSilicon: true

ui:
  appName: "Software Update Required"
  majorMessage: "A major macOS upgrade is required..."
  minorMessage: "A security update is available..."

toast:
  position: "topRight"           # topRight, topLeft, bottomRight, bottomLeft
  width: 420
  message: ""                    # Custom message, leave empty for default

schedule:
  alertStartHour: 8              # Only show UI between 8am–6pm
  alertEndHour: 18
  skipWeekends: true
  skipDuringMeetings: true

preflight:
  minDiskSpaceGB: 40             # Minimum free space before installing
  minBatteryPercent: 0           # 0 = disabled

jamf:
  url: ""
  eaName: "OS Update Compliance"
  binaryPath: "/usr/local/bin/jamf"
```

### Set config values via CLI:
```bash
sudo push-cli config set toast.position "bottomRight"
sudo push-cli config set schedule.alertStartHour 9
sudo push-cli config set preflight.minDiskSpaceGB 50
```

---

## CLI Reference

```
DETECTION & COMPLIANCE
  push-cli auto-check              Detect updates and run nudge schedule
  push-cli auto-check --force      Force run regardless of alert window
  push-cli status                  Show compliance status and schedule
  push-cli check                   Silent check — exits 0=compliant, 1=non-compliant

INSTALL
  push-cli install                 Start install workflow
  push-cli download                Download installer only
  push-cli install-extras          Install non-system updates
  push-cli install-safari          Install Safari update

AUTH (Apple Silicon)
  push-cli auth set-password       Store local admin password in System Keychain
  push-cli auth show               Show credential status
  push-cli auth clear              Remove stored credentials

DAEMON
  push-cli install-daemon          Install LaunchDaemon (default: every 1h)
  push-cli install-daemon --interval 2h   Custom interval: 1h, 2h, 4h, 8h, 12h, 24h
  push-cli uninstall-daemon        Remove LaunchDaemon

CONFIG
  push-cli config show             Show full config
  push-cli config get <key>        Get a specific value
  push-cli config set <key> <val>  Set a value
  push-cli config validate         Validate config file

POPUPS (for testing)
  push-cli popup softNudge
  push-cli popup hardBlock
  push-cli popup toast
  push-cli popup downloading --download-progress 0.5
  push-cli popup installing
  push-cli popup preflightDisk --disk-available 8 --disk-required 40
  push-cli popup error --error "Something went wrong"

MAINTENANCE
  push-cli reset                   Reset all state
  push-cli reset --deferrals-only  Reset deferral count only
  push-cli log show                Show log
  push-cli log tail                Tail log live
  push-cli log clear               Clear log
  push-cli report                  Generate compliance report
  push-cli self-update             Check for and apply PUSH updates
  push-cli --version               Show version
```

---

## Jamf Integration

### Extension Attribute

Create a Script EA in Jamf with this script:

```bash
#!/bin/bash
result=$(/Library/Management/PUSH/push-cli check 2>/dev/null)
echo "<result>$result</result>"
```

PUSH also writes the EA automatically after every `auto-check` run if `jamf.eaName` and `jamf.url` are configured.

### Smart Groups

Create smart groups based on the EA value:
- **Non-Compliant** — EA contains `non-compliant`
- **Compliant** — EA contains `compliant`
- **Deferrals Exhausted** — EA contains `3/3`

### Jamf Post-Install Script

Use `push-jamf-postinstall.sh` to customize PUSH after deployment:

```bash
#!/bin/bash
# Set your org's target version
/Library/Management/PUSH/push-cli config set update.targetVersion "26.4.1"

# Configure alert window
/Library/Management/PUSH/push-cli config set schedule.alertStartHour 9
/Library/Management/PUSH/push-cli config set schedule.alertEndHour 17

# Store local admin password in keychain
/Library/Management/PUSH/push-cli auth set-password --account localadmin <<< "your-password"
```

---

## Apple Silicon — Password Setup

Major upgrades on Apple Silicon require a local admin account with a Secure Token. Store the password securely in the System Keychain:

```bash
sudo push-cli auth set-password --account localadmin
# Enter password when prompted (input is hidden)
```

PUSH will use this password automatically at install time — no user prompt needed.

---

## Update Flow

```
auto-check runs (every 1h via LaunchDaemon)
    ↓
Detect available update via mdmclient + softwareupdate
    ↓
First detection → show softNudge, set deadline (30 days major / 5 days minor)
    ↓
Every hour → toast notification
Every day  → softNudge popup
    ↓
User clicks "Install Now"
    ↓
Preflight: disk space, battery, network
    ↓
Major: mist-cli download → startosinstall
Minor: softwareupdate native install
    ↓
Machine reboots → upgrade completes
    ↓
First auto-check post-upgrade → jamf recon → EA updated
```

---

## Files

| Path | Description |
|------|-------------|
| `/Library/Management/PUSH/push-cli` | CLI daemon binary |
| `/Library/Management/PUSH/push-ui.app` | UI popup app |
| `/Library/Management/PUSH/config.yaml` | Configuration |
| `/Library/Management/PUSH/state.json` | Runtime state (deferrals, dates) |
| `/Library/Management/PUSH/logs/push.log` | Main log |
| `/Library/Management/PUSH/logs/push-cli.log` | Daemon stdout |
| `/Library/LaunchDaemons/com.push.autoupdate.plist` | LaunchDaemon |

---

## Uninstall

```bash
sudo bash push-uninstall.sh              # Full removal
sudo bash push-uninstall.sh --keep-logs  # Keep logs
sudo bash push-uninstall.sh --keep-mist  # Keep mist-cli
```

---

## Building from Source

1. Clone the repo
2. Open `PUSH.xcodeproj` in Xcode
3. Select the `push-cli` scheme → Build
4. Select the `push-ui` scheme → Build
5. Binaries are in `DerivedData/.../Build/Products/Debug/`

Quick deploy script:
```bash
export DEBUG="/Users/yourname/Library/Developer/Xcode/DerivedData/PUSH-.../Build/Products/Debug"
sudo cp "$DEBUG/push-cli" /Library/Management/PUSH/push-cli
sudo cp -r "$DEBUG/push-ui.app" /Library/Management/PUSH/push-ui.app
sudo chmod +x /Library/Management/PUSH/push-cli
```

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Acknowledgements

- [mist-cli](https://github.com/ninxsoft/mist-cli) by Nindi Gill — macOS installer downloader
- [SOFA](https://sofa.macadmins.io) — macOS update feed
- Inspired by [nudge](https://github.com/macadmins/nudge) and [super](https://github.com/Macjutsu/super)
