#!/bin/bash
# PUSH - Deferrals Remaining EA
# Extension Attribute Type: Script
# Data Type: Integer

STATE_FILE="/Library/Management/PUSH/state.json"
CONFIG_FILE="/Library/Management/PUSH/config.yaml"

yaml_section_value() {
    /usr/bin/awk -v section="$1" -v key="$2" '
        $0 ~ "^" section ":[[:space:]]*$" { in_section=1; next }
        in_section && $0 ~ "^[^[:space:]#]" { exit }
        in_section && $0 ~ "^[[:space:]]+" key ":[[:space:]]*" {
            sub("^[[:space:]]+" key ":[[:space:]]*", "")
            gsub(/^[\047\"]|[\047\"]$/, "")
            print
            exit
        }
    ' "$CONFIG_FILE" 2>/dev/null
}

MAX_DEFERRALS=$(yaml_section_value "update" "maxDeferrals")
[ -z "$MAX_DEFERRALS" ] && MAX_DEFERRALS=0

COUNT=0
if [ -f "$STATE_FILE" ]; then
    VALUE=$(/usr/bin/plutil -extract deferralCount raw -o - "$STATE_FILE" 2>/dev/null)
    case "$VALUE" in
        ''|*[!0-9]*) COUNT=0 ;;
        *) COUNT=$VALUE ;;
    esac
fi

REMAINING=$((MAX_DEFERRALS - COUNT))
[ "$REMAINING" -lt 0 ] && REMAINING=0
echo "<result>$REMAINING</result>"

