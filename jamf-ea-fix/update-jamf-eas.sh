#!/bin/bash
#
# update-jamf-eas.sh — Updates existing PUSH-related EAs in Jamf Pro with
# corrected script payloads.
#
# When to use this:
#   - You discovered an existing EA has a bug (wrong tag, missing echo, etc.)
#   - You want to push a corrected version of the script body to the EA
#   - The EA's NAME stays the same, only its SCRIPT body is replaced
#
# Why a separate script (not setup-jamf.sh):
#   - setup-jamf.sh is for CREATE operations; this is for UPDATE operations.
#   - Updates are destructive — incorrect script payload breaks the EA for
#     every Mac in the fleet at next inventory recon.
#   - Keeping the two operations separate forces explicit intent.
#
# DESIGN PRINCIPLES:
#   - Read-only by default. --apply required to make any changes.
#   - Per-EA confirmation. Each update requires "y" before the API call.
#   - Idempotent. Compares current script body to new — only updates if different.
#   - Backs up the current script payload to a local file BEFORE updating.
#     If the new script is bad, you can manually restore from the backup.
#
# USAGE:
#   ./update-jamf-eas.sh --jamf-url URL --client-id ID
#   ./update-jamf-eas.sh --jamf-url URL --client-id ID --apply

set +e  # explicit error handling instead of set -e (so failures don't silently exit mid-script)

JAMF_URL=""
CLIENT_ID=""
APPLY=false
YES=false
EA_DIR=""
BACKUP_DIR=""

usage() {
    cat <<EOF
Usage: $0 --jamf-url URL --client-id ID [--apply] [--yes] [--ea-dir PATH] [--backup-dir PATH]

  --jamf-url URL        Jamf Pro URL
  --client-id ID        OAuth Client ID with Update Computer Extension Attributes permission
  --apply               Make changes (without this flag, dry-run only)
  --yes                 Skip per-EA confirmation prompts
  --ea-dir PATH         Directory containing the new EA scripts (default: ./eas)
  --backup-dir PATH     Where to save backup of current scripts (default: ./ea-backups)
  --help                This message
EOF
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --jamf-url)    JAMF_URL="$2"; shift 2 ;;
        --client-id)   CLIENT_ID="$2"; shift 2 ;;
        --apply)       APPLY=true; shift ;;
        --yes)         YES=true; shift ;;
        --ea-dir)      EA_DIR="$2"; shift 2 ;;
        --backup-dir)  BACKUP_DIR="$2"; shift 2 ;;
        --help|-h)     usage ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

[ -z "$JAMF_URL" ] && { echo "ERROR: --jamf-url required" >&2; usage; }
[ -z "$CLIENT_ID" ] && { echo "ERROR: --client-id required" >&2; usage; }

# Default paths to script's directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -z "$EA_DIR" ] && EA_DIR="$SCRIPT_DIR/eas"
[ -z "$BACKUP_DIR" ] && BACKUP_DIR="$SCRIPT_DIR/ea-backups"

[ ! -d "$EA_DIR" ] && {
    echo "ERROR: EA scripts directory not found: $EA_DIR" >&2
    echo "Use --ea-dir to specify the path" >&2
    exit 1
}

mkdir -p "$BACKUP_DIR"

command -v curl >/dev/null 2>&1 || { echo "ERROR: curl required" >&2; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "ERROR: jq required (brew install jq)" >&2; exit 1; }

JAMF_URL="${JAMF_URL%/}"

# ── EA name → file mapping ────────────────────────────────────────────────────
# Names match what's actually in your Jamf instance. Update if you rename anything.

declare -a EA_NAMES=(
    "PUSH — OS Update Compliance EA"
    "PUSH — Days Until Deadline EA"
    "PUSH — Deferral Count EA"
    "PUSH — Deferral Reasons EA"
)
declare -a EA_FILES=(
    "ea-os-update-compliance.sh"
    "ea-days-until-deadline.sh"
    "ea-deferral-count.sh"
    "ea-deferral-reasons.sh"
)

# ── Banner ────────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   PUSH — Jamf EA Updater                             ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "Jamf URL:     $JAMF_URL"
echo "Client ID:    $CLIENT_ID"
echo "EA scripts:   $EA_DIR"
echo "Backup dir:   $BACKUP_DIR"
if $APPLY; then
    if $YES; then
        echo "Mode:         APPLY (no prompts)"
    else
        echo "Mode:         APPLY (per-EA confirmation)"
    fi
else
    echo "Mode:         DRY-RUN (no changes will be made)"
fi
echo ""

# ── Verify all source scripts exist ───────────────────────────────────────────

for f in "${EA_FILES[@]}"; do
    if [ ! -f "$EA_DIR/$f" ]; then
        echo "ERROR: Source script missing: $EA_DIR/$f" >&2
        exit 1
    fi
done

# ── Auth ──────────────────────────────────────────────────────────────────────

read -r -s -p "Enter Client Secret: " CLIENT_SECRET
echo ""
[ -z "$CLIENT_SECRET" ] && { echo "ERROR: Client secret required" >&2; exit 1; }

echo "→ Authenticating…"
TOKEN_RESPONSE=$(curl -s -X POST "$JAMF_URL/api/oauth/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "client_id=$CLIENT_ID" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_secret=$CLIENT_SECRET")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')

if [ -z "$ACCESS_TOKEN" ]; then
    echo "ERROR: Authentication failed." >&2
    echo "Response: $TOKEN_RESPONSE" >&2
    exit 1
fi

echo "✓ Authenticated"
echo ""

# ── Helpers ───────────────────────────────────────────────────────────────────

api_get() {
    curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
         -H "Accept: application/json" \
         "$JAMF_URL$1"
}

api_get_xml() {
    curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
         -H "Accept: application/xml" \
         "$JAMF_URL$1"
}

api_put_xml() {
    curl -s -X PUT -H "Authorization: Bearer $ACCESS_TOKEN" \
         -H "Content-Type: application/xml" \
         -H "Accept: application/xml" \
         -d "$2" "$JAMF_URL$1"
}

confirm() {
    if $YES; then return 0; fi
    if ! $APPLY; then return 1; fi
    read -r -p "$1 [y/N]: " response
    case "$response" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

xml_escape() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

xml_unescape() {
    sed -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&amp;/\&/g'
}

# ── Read existing EAs ─────────────────────────────────────────────────────────

echo "→ Reading existing EAs from Jamf…"
EXISTING_EAS=$(api_get "/JSSResource/computerextensionattributes")

# ── Process each EA ───────────────────────────────────────────────────────────

UPDATED_COUNT=0
SKIPPED_COUNT=0

for idx in "${!EA_NAMES[@]}"; do
    name="${EA_NAMES[$idx]}"
    src_file="$EA_DIR/${EA_FILES[$idx]}"

    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  $name"
    echo "═══════════════════════════════════════════════════════"

    # Look up EA ID by name
    ea_id=$(echo "$EXISTING_EAS" | jq -r --arg n "$name" '.computer_extension_attributes[]? | select(.name==$n) | .id // empty')

    if [ -z "$ea_id" ]; then
        echo "  ⚠ Not found in Jamf (skipping)"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    echo "  EA ID: $ea_id"

    # Fetch current script body (XML format gives us the script tag)
    current_xml=$(api_get_xml "/JSSResource/computerextensionattributes/id/$ea_id")
    current_script=$(echo "$current_xml" \
        | tr -d '\r' \
        | awk '/<script>/,/<\/script>/' \
        | sed -E 's/.*<script>//; s/<\/script>.*//' \
        | xml_unescape)

    new_script=$(cat "$src_file")

    # Backup current script to disk regardless
    backup_file="$BACKUP_DIR/${EA_FILES[$idx]%.sh}.backup-$(date +%Y%m%d-%H%M%S).sh"
    echo "$current_script" > "$backup_file"
    echo "  Backed up current to: $backup_file"

    # Compare current vs new
    if [ "$current_script" = "$new_script" ]; then
        echo "  ✓ Script body matches new version — no update needed"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    # Show diff summary
    current_lines=$(echo "$current_script" | wc -l | tr -d ' ')
    new_lines=$(echo "$new_script" | wc -l | tr -d ' ')
    echo "  Current script: $current_lines lines"
    echo "  New script:     $new_lines lines"
    echo "  → Update needed"

    if ! $APPLY; then
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    if ! confirm "  Update this EA?"; then
        echo "  Skipped"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    # Build update XML — only the script payload changes; everything else stays.
    new_script_escaped=$(echo "$new_script" | xml_escape)

    # Pull out the existing settings so we don't accidentally clobber them
    data_type=$(echo "$current_xml" | grep -E -o '<data_type>[^<]*</data_type>' | sed -E 's/<\/?data_type>//g' | head -1)
    inventory_display=$(echo "$current_xml" | grep -E -o '<inventory_display>[^<]*</inventory_display>' | sed -E 's/<\/?inventory_display>//g' | head -1)
    description=$(echo "$current_xml" | grep -E -o '<description>[^<]*</description>' | sed -E 's/<\/?description>//g' | head -1)
    [ -z "$data_type" ] && data_type="String"
    [ -z "$inventory_display" ] && inventory_display="Operating System"

    UPDATE_XML="<computer_extension_attribute>
  <name>${name}</name>
  <description>${description}</description>
  <data_type>${data_type}</data_type>
  <input_type>
    <type>script</type>
    <platform>Mac</platform>
    <script>${new_script_escaped}</script>
  </input_type>
  <inventory_display>${inventory_display}</inventory_display>
</computer_extension_attribute>"

    response=$(api_put_xml "/JSSResource/computerextensionattributes/id/$ea_id" "$UPDATE_XML")
    api_status=$?

    if [ $api_status -ne 0 ]; then
        echo "  ✗ curl exited with status $api_status"
        echo "  Backup is at: $backup_file"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    # Jamf returns XML on success, or an error message on failure.
    # Check for obvious error indicators.
    if echo "$response" | grep -qE "Conflict|Bad Request|Unauthorized|Forbidden|Not Found|Internal Server Error|<error"; then
        echo "  ✗ Jamf returned an error response:"
        echo "    $response" | head -c 500
        echo ""
        echo "  Backup is at: $backup_file"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    # Verify the update by re-reading the EA's script
    sleep 2
    verify_xml=$(api_get_xml "/JSSResource/computerextensionattributes/id/$ea_id")
    verify_script=$(echo "$verify_xml" \
        | tr -d '\r' \
        | awk '/<script>/,/<\/script>/' \
        | sed -E 's/.*<script>//; s/<\/script>.*//' \
        | xml_unescape)

    if [ "$verify_script" = "$new_script" ]; then
        echo "  ✓ Updated and verified"
        UPDATED_COUNT=$((UPDATED_COUNT + 1))
    else
        echo "  ⚠ Update sent but verification mismatch — manually verify in Jamf web UI"
        echo "  Backup is at: $backup_file"
        UPDATED_COUNT=$((UPDATED_COUNT + 1))
    fi
done

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   Summary                                            ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  Updated: $UPDATED_COUNT"
echo "  Skipped: $SKIPPED_COUNT"
echo ""

if ! $APPLY; then
    echo "Dry-run complete. Re-run with --apply to actually update the EAs."
else
    echo "Next steps:"
    echo ""
    echo "  1. On a test Mac, force inventory recon:"
    echo "       sudo jamf recon"
    echo ""
    echo "  2. Check that Mac's inventory in Jamf — the previously-blank EAs"
    echo "     should now have values."
    echo ""
    echo "  3. Backups of the OLD EA scripts are saved at:"
    echo "       $BACKUP_DIR"
    echo "     If anything looks wrong, you can paste the backup script back"
    echo "     into the EA in Jamf web UI to restore."
fi
echo ""