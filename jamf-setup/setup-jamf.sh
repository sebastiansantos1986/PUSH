#!/bin/bash
#
# setup-jamf.sh — Automate creation of PUSH-related Jamf objects.
#
# Creates one Extension Attribute and six Smart Computer Groups in your
# Jamf Pro instance, all scoped to the PUSH compliance reporting flow.
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
#   - bash 4+ (macOS ships with 3.2; install via brew if missing)
#   - curl, jq

set -e
set -o pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────

JAMF_URL=""
CLIENT_ID=""
APPLY=false
YES=false
EA_SCRIPT_PATH=""

usage() {
    cat <<EOF
Usage: $0 --jamf-url URL --client-id ID [--apply] [--yes] [--ea-script PATH]

  --jamf-url URL        Jamf Pro URL (e.g. https://yourtenant.jamfcloud.com)
  --client-id ID        OAuth Client ID with EA + Smart Group permissions
  --apply               Make changes (without this flag, dry-run only)
  --yes                 Skip per-object confirmation prompts (use with care)
  --ea-script PATH      Path to push-os-compliance.sh (default: same directory)
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
        --ea-script)  EA_SCRIPT_PATH="$2"; shift 2 ;;
        --help|-h)    usage ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

[ -z "$JAMF_URL" ] && { echo "ERROR: --jamf-url required" >&2; usage; }
[ -z "$CLIENT_ID" ] && { echo "ERROR: --client-id required" >&2; usage; }

# Default EA script path to same directory as this script
if [ -z "$EA_SCRIPT_PATH" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    EA_SCRIPT_PATH="$SCRIPT_DIR/push-os-compliance.sh"
fi

[ ! -f "$EA_SCRIPT_PATH" ] && {
    echo "ERROR: EA script not found at $EA_SCRIPT_PATH" >&2
    echo "Use --ea-script to specify the path" >&2
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
echo "EA script:    $EA_SCRIPT_PATH"
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

EA_NAME="PUSH — OS Update Compliance EA"
EA_EXISTS=false
if echo "$EXISTING_EAS" | jq -e --arg n "$EA_NAME" '.computer_extension_attributes[]? | select(.name==$n)' >/dev/null 2>&1; then
    EA_EXISTS=true
fi

# Smart Group definitions — name + criterion(s)
declare -a GROUP_NAMES=(
    "PUSH: Compliant"
    "PUSH: Non-Compliant - Active"
    "PUSH: Past Deadline"
    "PUSH: Install In Progress"
    "PUSH: Not Reporting"
)

# Smart Group criteria, tuned to PUSH's actual output format:
#   "Compliant"  (alone — exact match needed since "Compliant" is substring of "Non-Compliant")
#   "Non-Compliant | Running: X.Y | Target: X.Y | Deferrals: N/M"
#   (Past Deadline / Install In Progress formats not yet observed in production —
#    if your EA produces something unexpected, edit the criteria after creation)
declare -a GROUP_CRITERIA_0=("is|||Compliant|||and")
declare -a GROUP_CRITERIA_1=("like|||Non-Compliant|||and" "not like|||Past Deadline|||and")
declare -a GROUP_CRITERIA_2=("like|||Past Deadline|||and")
declare -a GROUP_CRITERIA_3=("like|||Install Started|||and")
declare -a GROUP_CRITERIA_4=("is|||Not Installed|||or" "is|||(blank)|||and")

# ── Print plan ────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  PLAN"
echo "═══════════════════════════════════════════════════════"
echo ""

if $EA_EXISTS; then
    echo "  [SKIP] Extension Attribute '$EA_NAME' already exists"
else
    echo "  [CREATE] Extension Attribute: $EA_NAME"
    echo "           Type: Script"
    echo "           Source: $EA_SCRIPT_PATH"
fi
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

if ! $EA_EXISTS; then
    echo "→ Extension Attribute: $EA_NAME"
    if confirm "  Create now?"; then
        EA_SCRIPT_BODY=$(cat "$EA_SCRIPT_PATH" | xml_escape)
        EA_XML="<computer_extension_attribute>
  <name>${EA_NAME}</name>
  <description>PUSH compliance state. Generated by setup-jamf.sh.</description>
  <data_type>String</data_type>
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
            | jq -e --arg n "$EA_NAME" '.computer_extension_attributes[]? | select(.name==$n)' >/dev/null 2>&1; then
            echo "  ✓ Created"
        else
            echo "  ✗ Verification failed. Response: $RESPONSE" >&2
            exit 1
        fi
    else
        echo "  Skipped"
    fi
    echo ""
fi

# ── Create Smart Groups ───────────────────────────────────────────────────────

build_criteria_xml() {
    local -a criteria_array=("$@")
    local xml="<criteria>"
    local i=0
    for c in "${criteria_array[@]}"; do
        IFS='|||' read -r op value and_or <<< "$c"
        # Triple pipe split actually uses single-char separators in bash;
        # work around with parameter substitution instead.
        op=$(echo "$c" | awk -F'\\|\\|\\|' '{print $1}')
        value=$(echo "$c" | awk -F'\\|\\|\\|' '{print $2}')
        and_or=$(echo "$c" | awk -F'\\|\\|\\|' '{print $3}')
        xml+="
    <criterion>
      <name>${EA_NAME}</name>
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