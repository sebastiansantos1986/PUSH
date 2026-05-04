#!/bin/bash
# push-uninstall.sh — Complete removal of PUSH from macOS
# Run via Jamf policy or manually: sudo bash push-uninstall.sh
#
# Removes:
#   - LaunchDaemon
#   - push-cli binary + symlink
#   - push-ui.app
#   - /Library/Management/PUSH/ (config, state, logs, downloads)
#   - Keychain credentials (System Keychain)
#   - All /tmp/push-* temp files
#   - pkg receipts
#
# Options:
#   --keep-logs       Preserve /Library/Management/PUSH/logs/
#   --keep-mist       Do not uninstall mist-cli
#
# Safe to run even if PUSH was never fully installed.

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${BLUE}→${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
remove()  {
    if [[ -e "$1" || -L "$1" ]]; then
        rm -rf "$1"
        success "Removed: $1"
    fi
}

if [[ "$(id -u)" != "0" ]]; then
    echo "Run with sudo: sudo bash push-uninstall.sh"
    exit 1
fi

KEEP_LOGS=false
KEEP_MIST=false
for arg in "$@"; do
    [[ "$arg" == "--keep-logs" ]] && KEEP_LOGS=true
    [[ "$arg" == "--keep-mist" ]] && KEEP_MIST=true
done

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   PUSH Uninstaller v1.1.0                            ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Stop running processes ────────────────────────────────────────────────────
log "Stopping PUSH processes…"
pkill -x push-ui  2>/dev/null || true
pkill -x push-cli 2>/dev/null || true
pkill -f "caffeinate.*push" 2>/dev/null || true
sleep 0.5
success "Processes stopped"

# ── Unload and remove LaunchDaemon ────────────────────────────────────────────
PLIST="/Library/LaunchDaemons/com.push.autoupdate.plist"
if [[ -f "$PLIST" ]]; then
    log "Unloading LaunchDaemon…"
    launchctl bootout system "$PLIST" 2>/dev/null || \
        launchctl unload "$PLIST" 2>/dev/null || true
    remove "$PLIST"
fi

# ── Remove symlink ────────────────────────────────────────────────────────────
SYMLINK="/usr/local/bin/push-cli"
if [[ -L "$SYMLINK" ]]; then
    DEST=$(readlink "$SYMLINK")
    if [[ "$DEST" == *"push-cli"* ]]; then
        remove "$SYMLINK"
    fi
fi

# ── Remove Keychain credentials ───────────────────────────────────────────────
log "Removing keychain credentials…"
if security delete-generic-password \
    -s "com.push.autoupdate" \
    -a "push_auth_local_password" \
    /Library/Keychains/System.keychain 2>/dev/null; then
    success "Keychain credentials removed"
else
    success "No keychain credentials found (already clean)"
fi

# ── Clean up /tmp/push-* temp files ──────────────────────────────────────────
log "Cleaning up temp files…"
rm -f /tmp/push-* 2>/dev/null || true
success "Temp files cleaned"

# ── Remove managed folder ─────────────────────────────────────────────────────
log "Removing /Library/Management/PUSH/…"
remove "/Library/Management/PUSH/push-cli"
remove "/Library/Management/PUSH/push-ui.app"
remove "/Library/Management/PUSH/mist-cli*.pkg"
remove "/Library/Management/PUSH/downloads"

if [[ "$KEEP_LOGS" == true ]]; then
    warn "Preserving logs (--keep-logs specified)"
    find /Library/Management/PUSH -maxdepth 1 \
        ! -name "PUSH" ! -name "logs" -delete 2>/dev/null || true
else
    remove "/Library/Management/PUSH"
fi

# ── Optionally uninstall mist-cli ─────────────────────────────────────────────
if [[ "$KEEP_MIST" == false ]] && command -v mist &>/dev/null; then
    log "Uninstalling mist-cli…"
    remove "/usr/local/bin/mist"
    # Remove mist pkg receipt
    pkgutil --forget com.ninxsoft.mist 2>/dev/null || true
    success "mist-cli removed"
fi

# ── Remove pkg receipts ───────────────────────────────────────────────────────
log "Removing pkg receipts…"
for receipt in /private/var/db/receipts/com.push.*; do
    [[ -e "$receipt" ]] && remove "$receipt"
done
pkgutil --forget com.push.autoupdate 2>/dev/null || true

# ── Verify clean ──────────────────────────────────────────────────────────────
echo ""
REMAINING=$(find /Library/Management/PUSH \
    /Library/LaunchDaemons/com.push.autoupdate.plist \
    /usr/local/bin/push-cli 2>/dev/null | grep -v "^$" || true)

if [[ -z "$REMAINING" ]]; then
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║   PUSH completely removed  ✓                         ║"
    echo "╚══════════════════════════════════════════════════════╝"
else
    warn "Some files remain (may need manual review):"
    echo "$REMAINING"
fi
echo ""

exit 0
