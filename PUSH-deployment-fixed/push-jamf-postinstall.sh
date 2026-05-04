#!/bin/bash
# push-jamf-postinstall.sh — Jamf policy script for PUSH
# Run as: After in Jamf policy → Scripts
#
# This script runs AFTER the PUSH.pkg is installed.
# It customizes config for your org, installs the daemon, and fires first check.
#
# ── CUSTOMIZE THESE VALUES FOR YOUR ORG ──────────────────────────────────────

ORG_NAME="Your Organization"
IT_EMAIL="it@yourorg.com"
IT_PHONE="1-800-555-0100"
ACCENT_COLOR="#0A84FF"

# Enforce macOS 26 across all Macs
# Machines on 15.x → major upgrade, machines on 26.x → minor update
ENFORCE_MAJOR_VERSION="26"

# Deadline days from first detection
MINOR_DEADLINE_DAYS="5"
MAJOR_DEADLINE_DAYS="30"

# Max deferrals
MINOR_MAX_DEFERRALS="5"
MAJOR_MAX_DEFERRALS="3"

# Teams/Slack webhook URL (leave empty to disable)
WEBHOOK_URL=""

# Jamf Pro API credentials for MDM push commands (push-cli mdm push)
# OAuth client credentials — recommended (Jamf Pro 10.48+)
JAMF_CLIENT_ID=""
JAMF_CLIENT_SECRET=""
# Legacy account — used if client credentials are empty
JAMF_ACCOUNT_NAME=""
JAMF_ACCOUNT_PASSWORD=""

# Hard block fullscreen lockout (true/false)
HARD_BLOCK_FULLSCREEN="false"

# Alert window (24h)
ALERT_START_HOUR="8"
ALERT_END_HOUR="18"

# ── DO NOT EDIT BELOW THIS LINE ───────────────────────────────────────────────

CLI="/Library/Management/PUSH/push-cli"
LOG="/Library/Management/PUSH/logs/push.log"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [Jamf] $1" | tee -a "$LOG"; }

log "Running PUSH post-install configuration"

# Verify push-cli is installed
if [[ ! -x "$CLI" ]]; then
    log "ERROR: push-cli not found at $CLI"
    exit 1
fi

# Apply org config
"$CLI" config set ui.orgName            "$ORG_NAME"
"$CLI" config set ui.itContactEmail     "$IT_EMAIL"
"$CLI" config set ui.itContactPhone     "$IT_PHONE"
"$CLI" config set ui.accentColorHex     "$ACCENT_COLOR"
"$CLI" config set ui.hardBlockFullscreen "$HARD_BLOCK_FULLSCREEN"

"$CLI" config set auto.enforceMinimumMajorVersion "$ENFORCE_MAJOR_VERSION"
"$CLI" config set auto.minorDeadlineDays           "$MINOR_DEADLINE_DAYS"
"$CLI" config set auto.majorDeadlineDays           "$MAJOR_DEADLINE_DAYS"
"$CLI" config set auto.minorMaxDeferrals           "$MINOR_MAX_DEFERRALS"
"$CLI" config set auto.majorMaxDeferrals           "$MAJOR_MAX_DEFERRALS"

"$CLI" config set schedule.alertStartHour "$ALERT_START_HOUR"
"$CLI" config set schedule.alertEndHour   "$ALERT_END_HOUR"
"$CLI" config set schedule.skipOnVPN      false

# Apply Jamf API credentials if set
if [[ -n "$JAMF_CLIENT_ID" ]]; then
    "$CLI" config set jamf.clientId      "$JAMF_CLIENT_ID"
    "$CLI" config set jamf.clientSecret  "$JAMF_CLIENT_SECRET"
fi
if [[ -n "$JAMF_ACCOUNT_NAME" ]]; then
    "$CLI" config set jamf.accountName     "$JAMF_ACCOUNT_NAME"
    "$CLI" config set jamf.accountPassword "$JAMF_ACCOUNT_PASSWORD"
fi

if [[ -n "$WEBHOOK_URL" ]]; then
    "$CLI" config set auto.adminWebhookURL          "$WEBHOOK_URL"
    "$CLI" config set auto.notifyAdminOnDetection   true
    "$CLI" config set auto.notifyOnDeadlineHit      true
    "$CLI" config set auto.notifyOnDeferralExhausted true
    "$CLI" config set auto.notifyOnInstallComplete  true
fi

log "Config applied"

# Create symlink if missing
if [[ ! -L /usr/local/bin/push-cli ]]; then
    ln -sf "$CLI" /usr/local/bin/push-cli
    log "Symlink created: /usr/local/bin/push-cli"
fi

# Load LaunchDaemon if not already loaded
PLIST="/Library/LaunchDaemons/com.push.autoupdate.plist"
if [[ -f "$PLIST" ]]; then
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST" 2>/dev/null && log "LaunchDaemon loaded" || log "LaunchDaemon load failed"
fi

# Validate config
"$CLI" config validate && log "Config valid" || log "WARNING: Config validation failed"

# Fire first auto-check to detect any pending updates immediately
log "Running initial auto-check…"
"$CLI" auto-check
log "Initial auto-check complete"

log "PUSH post-install complete"
exit 0
