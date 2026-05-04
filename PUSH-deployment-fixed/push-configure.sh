#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  PUSH — Configuration Script                                                ║
# ║  Run after deploying PUSH-1.1.0.pkg via Jamf or manually                   ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# USAGE:
#   Manually:  sudo bash push-configure.sh
#   Via Jamf:  Add as post-install script. Pass values as Jamf script parameters.
#
# JAMF SCRIPT PARAMETERS:
#   $4 = Local admin account name       (e.g. localadmin)
#   $5 = Local admin password           (stored securely in System Keychain)
#   $6 = Jamf Pro URL                   (e.g. https://yourorg.jamfcloud.com)
#   $7 = Jamf OAuth Client ID
#   $8 = Jamf OAuth Client Secret
#   $9 = IT contact email               (e.g. it@yourorg.com)
#
# TO CUSTOMIZE: Edit the values in each section below before deploying.

CLI="/Library/Management/PUSH/push-cli"
CONFIG="/Library/Management/PUSH/config.yaml"

# Verify PUSH is installed
if [[ ! -x "$CLI" ]]; then
    echo "ERROR: push-cli not found at $CLI"
    echo "Deploy PUSH-1.1.0.pkg first."
    exit 1
fi

echo "Configuring PUSH $($CLI --version | awk '{print $NF}')..."
echo ""

# ── Helper: set a simple key=value in config.yaml ─────────────────────────────
set_config() {
    local key="$1"
    local value="$2"
    $CLI config set "$key" "$value"
}

# ── Helper: write a multiline message directly to config.yaml ─────────────────
# Uses Python to safely write strings with \n without shell mangling them.
set_message() {
    local key="$1"
    local value="$2"
    python3 - "$CONFIG" "$key" "$value" << 'PYEOF'
import sys, re

config_path = sys.argv[1]
key         = sys.argv[2]
value       = sys.argv[3]

with open(config_path, 'r') as f:
    content = f.read()

# Escape any double quotes in the value
escaped = value.replace('"', '\\"')

# Replace the existing key line with the new value
pattern = r'^(\s*' + re.escape(key) + r':).*$'
replacement = r'\g<1> "' + escaped + '"'
new_content = re.sub(pattern, replacement, content, flags=re.MULTILINE)

with open(config_path, 'w') as f:
    f.write(new_content)

print(f"  ✓ Set {key}")
PYEOF
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  UPDATE SETTINGS                                                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set_config update.minorMaxDeferrals 5
set_config update.majorMaxDeferrals 3
set_config auto.minorDeadlineDays 5
set_config auto.majorDeadlineDays 30
set_config update.toastIntervalSeconds 3600
set_config update.nudgeIntervalSeconds 86400
set_config update.requirePasswordOnAppleSilicon true
set_config update.silentInstallAfterDeadline false
set_config update.autoInstallAfterDeadline true      # Auto-start install when deadline passes
set_config update.forceRestartAfterInstall false

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  AUTO DETECTION                                                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set_config auto.enabled true
set_config auto.skipBetas true
set_config auto.minorOnly false
set_config auto.enforceMinimumMajorVersion 0
set_config auto.notifyAdminOnDetection false
set_config auto.notifyOnDeadlineHit true
set_config auto.notifyOnDeferralExhausted true
set_config auto.notifyOnInstallComplete true

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  UI SETTINGS                                                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set_config ui.appName "Software Update Required"
set_config ui.accentColorHex "#0A84FF"
set_config ui.popupWidth 540
set_config ui.hardBlockFullscreen false
set_config ui.requireDeferralReason false
set_config ui.installMajorButtonLabel "Begin Upgrade"
set_config ui.installMinorButtonLabel "Install Now"
set_config ui.deferButtonLabel "Remind Me Later"

# IT contact info (shown in error and hard block screens)
IT_EMAIL="${9:-}"
if [[ -n "$IT_EMAIL" ]]; then
    set_config ui.itContactEmail "$IT_EMAIL"
fi

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  MESSAGES                                                                   ║
# ║  Written directly to config.yaml to preserve \n line breaks                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set_message majorMessage "A major macOS upgrade is required by IT. Please save your work and begin the upgrade today.\n\nWhat to expect:\n- The upgrade takes 45–60 minutes\n- Your files and apps will be preserved\n- Your Mac will restart automatically"

set_message minorMessage "A required macOS security update is available. Please install it at your earliest convenience.\n\nThis update includes:\n- Security patches\n- Performance improvements\n- Bug fixes"

set_message deadlineMessage "Your Mac must be updated immediately.\n\nSave your work and click Install Now to begin. The update takes 45–60 minutes."

set_message installingMessage "Installation in progress. This takes 45–60 minutes.\n\nPlease keep your Mac powered on."

set_message alreadyUpToDateMessage "Your Mac is running the required version of macOS. No action needed."

# Message shown during forced automatic install (deadline passed, autoInstallAfterDeadline: true)
# Leave empty to use the smart built-in default
set_message forcedInstallMessage "Your Mac is overdue for a required macOS update. The installation is beginning automatically — no action is needed from you."

# "What to expect" bullet points during forced install — one per line using \n
# Leave empty to use the smart built-in defaults
set_message forcedInstallNotice "Save any open work now\nThis window cannot be closed\nIf the window disappears, the update continues in the background\nYour Mac will restart automatically when ready\nThe process takes approximately 30-45 minutes"

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  TOAST NOTIFICATION                                                         ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set_config toast.position "topRight"
set_config toast.width 420
set_config toast.screenMargin 16
set_config toast.cornerRadius 16
set_config toast.showCloseButton true
set_config toast.showDeferButton true
set_config toast.installButtonLabel "Install Now"
set_config toast.deferButtonLabel "Later"
set_config toast.soundName "Funk"
# Uncomment and edit to set a custom toast message:
# set_message message "Hello!\n\nmacOS Tahoe is available.\n\n- Enhanced security\n- Better performance\n\nInstallation takes 30-45 minutes."

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SCHEDULE                                                                   ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set_config schedule.alertStartHour 8
set_config schedule.alertEndHour 18
set_config schedule.skipWeekends true
set_config schedule.skipDuringMeetings true
set_config schedule.skipOnVPN false

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  PREFLIGHT CHECKS                                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set_config preflight.minDiskSpaceGB 40
set_config preflight.minBatteryPercent 0
set_config preflight.powerCheckTimeoutMinutes 5
set_config preflight.checkNetworkReachability true
set_config preflight.skipOnVPN false

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  JAMF INTEGRATION                                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set_config jamf.eaName "OS Update Compliance"
set_config jamf.binaryPath "/usr/local/bin/jamf"
set_config jamf.reportEAAfterCheck true

JAMF_URL="${6:-}"
JAMF_CLIENT_ID="${7:-}"
JAMF_CLIENT_SECRET="${8:-}"

if [[ -n "$JAMF_URL" ]];           then set_config jamf.url "$JAMF_URL"; fi
if [[ -n "$JAMF_CLIENT_ID" ]];     then set_config jamf.clientId "$JAMF_CLIENT_ID"; fi
if [[ -n "$JAMF_CLIENT_SECRET" ]]; then set_config jamf.clientSecret "$JAMF_CLIENT_SECRET"; fi

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  APPLE SILICON AUTH                                                         ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

ADMIN_ACCOUNT="${4:-}"
ADMIN_PASSWORD="${5:-}"

if [[ -n "$ADMIN_ACCOUNT" && -n "$ADMIN_PASSWORD" ]]; then
    echo "Storing credentials for '$ADMIN_ACCOUNT' in System Keychain..."
    $CLI auth set-password --account "$ADMIN_ACCOUNT" <<< "$ADMIN_PASSWORD"
    echo "Credentials stored."
else
    echo "No credentials provided — PUSH will prompt user at install time."
fi

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  RESET DEADLINE                                                             ║
# ║  Clears existing deadline and detection log so auto-check recalculates      ║
# ║  the deadline from today based on majorDeadlineDays / minorDeadlineDays     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

echo ""
echo "Resetting deadline..."

# Clear deadline and targetVersion from config so auto-check reconfigures fresh
python3 - "$CONFIG" << 'PYEOF'
import sys, re

config_path = sys.argv[1]
with open(config_path, 'r') as f:
    content = f.read()

# Clear deadline so auto-check sets it fresh from today
content = re.sub(r'^(\s*deadline:).*$', r'\1 ""', content, flags=re.MULTILINE)
content = re.sub(r'^(\s*targetVersion:).*$', r'\1 ""', content, flags=re.MULTILINE)

with open(config_path, 'w') as f:
    f.write(content)

print("  ✓ Deadline and targetVersion cleared")
PYEOF

# Clear state and detection log
$CLI reset
# Remove detection log so first-seen date is recalculated from today
rm -f /Library/Management/PUSH/detections.json 2>/dev/null
echo "  ✓ State and detection log cleared"

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  VALIDATE & RUN                                                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

echo ""
echo "Validating config..."
$CLI config validate

echo ""
echo "Running initial auto-check (deadline calculated from today)..."
$CLI auto-check

echo ""
echo "✓ PUSH configured successfully."
echo "  Run 'push-cli status' to verify the new deadline."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "POPUP TESTING EXAMPLES — run these to preview any UI state:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  # Daily nudge popup"
echo "  sudo push-cli popup softNudge"
echo ""
echo "  # Hard block — deadline passed, user must click"
echo "  sudo push-cli popup hardBlock"
echo ""
echo "  # Corner toast notification"
echo "  sudo push-cli popup toast"
echo ""
echo "  # Password prompt (Apple Silicon)"
echo "  sudo push-cli popup passwordPrompt"
echo ""
echo "  # Download progress — 3 stages"
echo "  sudo push-cli popup downloading --download-progress 0.0 --download-subtitle "Connecting to Apple servers…""
echo "  sudo push-cli popup downloading --download-progress 0.42 --download-subtitle "Downloading macOS… 42%""
echo "  sudo push-cli popup downloading --download-progress 0.96 --download-subtitle "Finalizing… 11 of 13 GB""
echo ""
echo "  # Installation in progress"
echo "  sudo push-cli popup installing"
echo ""
echo "  # Restart countdown"
echo "  sudo push-cli popup rebooting"
echo ""
echo "  # Already up to date"
echo "  sudo push-cli popup compliant"
echo ""
echo "  # Error dialog"
echo "  sudo push-cli popup error --error "Could not download the macOS installer. Please contact IT support.""
echo ""
echo "  # Disk space warning"
echo "  sudo push-cli popup preflightDisk --disk-available 8.5 --disk-required 40"
echo ""
echo "  # AC power required"
echo "  sudo push-cli popup preflightPower"
echo ""
echo "  # Force install flow (deadline passed)"
echo "  sudo push-cli config set update.deadline "2026-01-01T00:00:00Z""
echo "  sudo push-cli auto-check --force"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
exit 0
