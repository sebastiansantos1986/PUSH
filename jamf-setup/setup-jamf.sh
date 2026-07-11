#!/bin/bash
#
# setup-jamf.sh — Automate creation of PUSH-related Jamf objects.
#
# Creates seven Extension Attributes and operational Smart Computer Groups in
# your Jamf Pro instance, all scoped to the PUSH reporting flow.
#
# DESIGN PRINCIPLES:
#   - Read-only by default. --apply required to make any changes.
#   - Per-object confirmation. Each create requires "y" before the API call.
#   - Idempotent. If an object already exists with the same name, skip it.
#   - Verifies after every create. If creation succeeds but verification fails,
#     the script stops and tells you what's wrong.
#
# USAGE:
#   ./setup-jamf.sh --jamf-url https://yourtenant.jamfcloud.com \
#                   --client-id YOUR_CLIENT_ID
#   (Client secret is prompted at runtime — never put it on a command line.)
#
# DRY-RUN (default — shows what would happen, makes NO changes):
#   ./setup-jamf.sh --jamf-url ... --client-id ...
#
# APPLY (creates objects with per-object confirmation):
#   ./setup-jamf.sh --jamf-url ... --client-id ... --apply
#
# YES-MODE (skips confirmation prompts — only after a successful dry-run):
#   ./setup-jamf.sh --jamf-url ... --client-id ... --apply --yes
#
# REQUIREMENTS:
#   - macOS bash 3.2+, curl, jq
#   - curl, jq

set -e
set -o pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────

JAMF_URL=""
CLIENT_ID=""
APPLY=false
YES=false
EA_DIR=""

usage() {
    cat <<EOF
Usage: $0 --jamf-url URL --client-id ID [--apply] [--yes] [--ea-dir PATH]

  --jamf-url URL        Jamf Pro URL (e.g. https://yourtenant.jamfcloud.com)
  --client-id ID        OAuth Client ID with EA + Smart Group permissions
  --apply               Make changes (without this flag, dry-run only)
  --yes                 Skip per-object confirmation prompts (use with care)
  --ea-dir PATH         Directory containing PUSH EA scripts
  --help                This message

Client secret is read interactively (never on command line).
EOF
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --jamf-url)   JAMF_URL="$2"; shift 2 ;;
        --client-id)  CLIENT_ID="$2"; shift 2 ;;
        --apply)      APPLY=true; shift ;;
        --yes)        YES=true; shift ;;
        --ea-dir)     EA_DIR="$2"; shift 2 ;;
        --help|-h)    usage ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

[ -z "$JAMF_URL" ] && { echo "ERROR: --jamf-url required" >&2; usage; }
[ -z "$CLIENT_ID" ] && { echo "ERROR: --client-id required" >&2; usage; }

# Default to the canonical EA scripts shipped with PUSH.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -z "$EA_DIR" ] && EA_DIR="$SCRIPT_DIR/../jamf-ea-fix/eas"

[ ! -d "$EA_DIR" ] && {
    echo "ERROR: EA script directory not found at $EA_DIR" >&2
    echo "Use --ea-dir to specify the path" >&2
    exit 1
}

# Verify dependencies
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl required" >&2; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "ERROR: jq required (brew install jq)" >&2; exit 1; }

# Strip trailing slash from URL
JAMF_URL="${JAMF_URL%/}"

# ── Banner ────────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   PUSH — Jamf Setup                                  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "Jamf URL:     $JAMF_URL"
echo "Client ID:    $CLIENT_ID"
echo "EA scripts:   $EA_DIR"
if $APPLY; then
    if $YES; then
        echo "Mode:         APPLY (no prompts)"
    else
        echo "Mode:         APPLY (per-object confirmation)"
    fi
else
    echo "Mode:         DRY-RUN (no changes will be made)"
fi
echo ""

# ── Get client secret ─────────────────────────────────────────────────────────

read -r -s -p "Enter Client Secret: " CLIENT_SECRET
echo ""
[ -z "$CLIENT_SECRET" ] && { echo "ERROR: Client secret required" >&2; exit 1; }

# ── Auth ──────────────────────────────────────────────────────────────────────

echo "→ Authenticating…"
TOKEN_RESPONSE=$(curl -s -X POST "$JAMF_URL/api/oauth/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "client_id=$CLIENT_ID" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_secret=$CLIENT_SECRET")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')

if [ -z "$ACCESS_TOKEN" ]; then
    echo ""
    echo "ERROR: Authentication failed." >&2
    echo "Response: $TOKEN_RESPONSE" >&2
    exit 1
fi

echo "✓ Authenticated"
echo ""

# Helper for API calls
api_get() {
    curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
         -H "Accept: application/json" \
         "$JAMF_URL$1"
}

api_post_json() {
    curl -s -X POST -H "Authorization: Bearer $ACCESS_TOKEN" \
         -H "Content-Type: application/json" \
         -H "Accept: application/json" \
         -d "$2" "$JAMF_URL$1"
}

api_post_xml() {
    curl -s -X POST -H "Authorization: Bearer $ACCESS_TOKEN" \
         -H "Content-Type: application/xml" \
         -H "Accept: application/xml" \
         -d "$2" "$JAMF_URL$1"
}

# Per-object confirmation
confirm() {
    local prompt="$1"
    if $YES; then return 0; fi
    if ! $APPLY; then return 1; fi
    read -r -p "$prompt [y/N]: " response
    case "$response" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# XML escape helper for the EA script payload
xml_escape() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# ── Read existing state ───────────────────────────────────────────────────────

echo "→ Reading current Jamf state…"

EXISTING_EAS=$(api_get "/JSSResource/computerextensionattributes" || echo "")
EXISTING_GROUPS=$(api_get "/JSSResource/computergroups" || echo "")

declare -a EA_NAMES=(
    "PUSH — OS Update Compliance EA"
    "PUSH — Days Until Deadline EA"
    "PUSH — Deferral Count EA"
    "PUSH — Deferral Reasons EA"
    "PUSH — Deferrals Remaining EA"
    "PUSH — Health EA"
    "PUSH — Reboot Status EA"
)
declare -a EA_FILES=(
    "ea-os-update-compliance.sh"
    "ea-days-until-deadline.sh"
    "ea-deferral-count.sh"
    "ea-deferral-reasons.sh"
    "ea-deferrals-remaining.sh"
    "ea-push-health.sh"
    "ea-reboot-status.sh"
)
declare -a EA_TYPES=("String" "Integer" "Integer" "String" "Integer" "String" "String")
declare -a EA_DESCRIPTIONS=(
    "PUSH macOS update compliance state"
    "Calendar days remaining until the configured update deadline; -1 means no deadline"
    "Update deferrals used in the current update cycle"
    "User-provided update deferral reasons"
    "Update deferrals remaining in the current update cycle"
    "PUSH installation, daemon, and auto-check health"
    "PUSH uptime restart policy state"
)

for file in "${EA_FILES[@]}"; do
    [ -f "$EA_DIR/$file" ] || { echo "ERROR: Missing EA script: $EA_DIR/$file" >&2; exit 1; }
done

# Smart Group definitions — name + criterion(s)
declare -a GROUP_NAMES=(
    "PUSH: Compliant"
    "PUSH: Non-Compliant - Active"
    "PUSH: Past Deadline"
    "PUSH: Install In Progress"
    "PUSH: Not Installed"
    "PUSH: Not Configured"
    "PUSH: Deadline Due or Past"
    "PUSH: Deferrals Used"
    "PUSH: Deferrals Exhausted"
    "PUSH: Health Attention"
    "PUSH: Reboot Warning"
    "PUSH: Reboot Force"
)

# Smart Group criteria, tuned to PUSH's actual output format:
#   "Compliant"  (alone — exact match needed since "Compliant" is substring of "Non-Compliant")
#   "Non-Compliant | Running: X.Y | Target: X.Y | Deferrals: N/M"
#   (Past Deadline / Install In Progress formats not yet observed in production —
#    if your EA produces something unexpected, edit the criteria after creation)
declare -a GROUP_CRITERIA_0=("PUSH — OS Update Compliance EA|||is|||Compliant|||and")
declare -a GROUP_CRITERIA_1=("PUSH — OS Update Compliance EA|||like|||Non-Compliant|||and")
declare -a GROUP_CRITERIA_2=("PUSH — OS Update Compliance EA|||like|||Past Deadline|||and")
declare -a GROUP_CRITERIA_3=("PUSH — OS Update Compliance EA|||like|||Install Started|||and")
declare -a GROUP_CRITERIA_4=("PUSH — OS Update Compliance EA|||is|||PUSH not installed|||or" "PUSH — Health EA|||is|||Not Installed|||or")
declare -a GROUP_CRITERIA_5=("PUSH — OS Update Compliance EA|||is|||Not configured|||and")
declare -a GROUP_CRITERIA_6=("PUSH — OS Update Compliance EA|||like|||Non-Compliant|||and" "PUSH — Days Until Deadline EA|||less than|||1|||and")
declare -a GROUP_CRITERIA_7=("PUSH — Deferral Count EA|||more than|||0|||and")
declare -a GROUP_CRITERIA_8=("PUSH — OS Update Compliance EA|||like|||Non-Compliant|||and" "PUSH — Deferrals Remaining EA|||is|||0|||and")
declare -a GROUP_CRITERIA_9=("PUSH — Health EA|||like|||Attention|||and")
declare -a GROUP_CRITERIA_10=("PUSH — Reboot Status EA|||like|||Warning|||and")
declare -a GROUP_CRITERIA_11=("PUSH — Reboot Status EA|||like|||Force|||and")

# ── Print plan ────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  PLAN"
echo "═══════════════════════════════════════════════════════"
echo ""

for idx in "${!EA_NAMES[@]}"; do
    name="${EA_NAMES[$idx]}"
    if echo "$EXISTING_EAS" | jq -e --arg n "$name" '.computer_extension_attributes[]? | select(.name==$n)' >/dev/null 2>&1; then
        echo "  [SKIP] Extension Attribute '$name' already exists"
    else
        echo "  [CREATE] Extension Attribute: $name (${EA_TYPES[$idx]})"
    fi
done
echo ""

for idx in "${!GROUP_NAMES[@]}"; do
    name="${GROUP_NAMES[$idx]}"
    if echo "$EXISTING_GROUPS" | jq -e --arg n "$name" '.computer_groups[]? | select(.name==$n)' >/dev/null 2>&1; then
        echo "  [SKIP] Smart Group '$name' already exists"
    else
        echo "  [CREATE] Smart Group: $name"
    fi
done
echo ""

if ! $APPLY; then
    echo "Dry-run complete. No changes made."
    echo "Re-run with --apply to actually create the missing objects."
    exit 0
fi

# ── Confirm overall plan ──────────────────────────────────────────────────────

if ! $YES; then
    read -r -p "Proceed with creating missing objects? [y/N]: " response
    case "$response" in
        [yY]|[yY][eE][sS]) echo "" ;;
        *) echo "Cancelled."; exit 0 ;;
    esac
fi

# ── Create the EA ─────────────────────────────────────────────────────────────

# Create missing EAs. Existing EAs are never overwritten by this setup tool;
# use jamf-ea-fix/update-jamf-eas.sh when an existing script needs an update.
for idx in "${!EA_NAMES[@]}"; do
    name="${EA_NAMES[$idx]}"
    if echo "$EXISTING_EAS" | jq -e --arg n "$name" '.computer_extension_attributes[]? | select(.name==$n)' >/dev/null 2>&1; then
        continue
    fi

    echo "→ Extension Attribute: $name"
    if confirm "  Create now?"; then
        EA_SCRIPT_BODY=$(cat "$EA_DIR/${EA_FILES[$idx]}" | xml_escape)
        EA_XML="<computer_extension_attribute>
  <name>${name}</name>
  <description>${EA_DESCRIPTIONS[$idx]}. Generated by setup-jamf.sh.</description>
  <data_type>${EA_TYPES[$idx]}</data_type>
  <input_type>
    <type>script</type>
    <platform>Mac</platform>
    <script>${EA_SCRIPT_BODY}</script>
  </input_type>
  <inventory_display>Operating System</inventory_display>
</computer_extension_attribute>"

        RESPONSE=$(api_post_xml "/JSSResource/computerextensionattributes/id/0" "$EA_XML")

        # Verify
        sleep 1
        if api_get "/JSSResource/computerextensionattributes" \
            | jq -e --arg n "$name" '.computer_extension_attributes[]? | select(.name==$n)' >/dev/null 2>&1; then
            echo "  ✓ Created"
        else
            echo "  ✗ Verification failed. Response: $RESPONSE" >&2
            exit 1
        fi
    else
        echo "  Skipped"
    fi
    echo ""
done

# ── Create Smart Groups ───────────────────────────────────────────────────────

build_criteria_xml() {
    local -a criteria_array=("$@")
    local xml="<criteria>"
    local i=0
    for c in "${criteria_array[@]}"; do
        IFS='|||' read -r criterion_name op value and_or <<< "$c"
        # Triple pipe split actually uses single-char separators in bash;
        # work around with parameter substitution instead.
        criterion_name=$(echo "$c" | awk -F'\\|\\|\\|' '{print $1}')
        op=$(echo "$c" | awk -F'\\|\\|\\|' '{print $2}')
        value=$(echo "$c" | awk -F'\\|\\|\\|' '{print $3}')
        and_or=$(echo "$c" | awk -F'\\|\\|\\|' '{print $4}')
        xml+="
    <criterion>
      <name>${criterion_name}</name>
      <priority>${i}</priority>
      <and_or>${and_or}</and_or>
      <search_type>${op}</search_type>
      <value>${value}</value>
    </criterion>"
        i=$((i+1))
    done
    xml+="
    <size>${#criteria_array[@]}</size>
  </criteria>"
    echo "$xml"
}

for idx in "${!GROUP_NAMES[@]}"; do
    name="${GROUP_NAMES[$idx]}"

    if echo "$EXISTING_GROUPS" | jq -e --arg n "$name" '.computer_groups[]? | select(.name==$n)' >/dev/null 2>&1; then
        continue
    fi

    echo "→ Smart Group: $name"
    if confirm "  Create now?"; then
        # Get criteria for this index
        var_name="GROUP_CRITERIA_${idx}[@]"
        criteria=("${!var_name}")
        criteria_xml=$(build_criteria_xml "${criteria[@]}")

        GROUP_XML="<computer_group>
  <name>${name}</name>
  <is_smart>true</is_smart>
  ${criteria_xml}
</computer_group>"

        RESPONSE=$(api_post_xml "/JSSResource/computergroups/id/0" "$GROUP_XML")

        # Verify
        sleep 1
        if api_get "/JSSResource/computergroups" \
            | jq -e --arg n "$name" '.computer_groups[]? | select(.name==$n)' >/dev/null 2>&1; then
            echo "  ✓ Created"
        else
            echo "  ✗ Verification failed. Response: $RESPONSE" >&2
            echo "  Continuing with remaining groups…" >&2
        fi
    else
        echo "  Skipped"
    fi
    echo ""
done

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   Setup complete                                     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "Next steps (manual — these can't be automated cleanly):"
echo ""
echo "  1. On a test Mac with PUSH installed, run:"
echo "       sudo jamf recon"
echo "     Then check that Mac's record in Jamf — the EA value should populate."
echo ""
echo "  2. Optionally disable PUSH's API-based EA reporting (script-only mode):"
echo "       sudo /Library/Management/PUSH/push-cli config set jamf.reportEAAfterCheck false"
echo ""
echo "  3. Verify each Smart Group has the expected members in Jamf web UI:"
for name in "${GROUP_NAMES[@]}"; do
    echo "       - $name"
done
echo ""
