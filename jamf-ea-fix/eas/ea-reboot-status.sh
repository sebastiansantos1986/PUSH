#!/bin/bash
# PUSH - Reboot Status EA
# Extension Attribute Type: Script
# Data Type: String

PUSH_CLI="/Library/Management/PUSH/push-cli"
CONFIG_FILE="/Library/Management/PUSH/config.yaml"
STATE_FILE="/Library/Management/PUSH/state.json"

if [ ! -x "$PUSH_CLI" ]; then
    echo "<result>Not Installed</result>"
    exit 0
fi

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

ENABLED=$(yaml_section_value "uptime" "enabled")
WARNING_DAYS=$(yaml_section_value "uptime" "warningThresholdDays")
FORCE_DAYS=$(yaml_section_value "uptime" "forceThresholdDays")
MAX_DEFERRALS=$(yaml_section_value "uptime" "maxDeferrals")

[ "$ENABLED" != "true" ] && {
    echo "<result>Disabled</result>"
    exit 0
}
[ -z "$WARNING_DAYS" ] && WARNING_DAYS=14
[ -z "$FORCE_DAYS" ] && FORCE_DAYS=20
[ -z "$MAX_DEFERRALS" ] && MAX_DEFERRALS=3

BOOT_SECONDS=$(/usr/sbin/sysctl -n kern.boottime 2>/dev/null \
    | /usr/bin/sed -E 's/.*sec = ([0-9]+).*/\1/')
NOW=$(/bin/date +%s)
case "$BOOT_SECONDS" in
    ''|*[!0-9]*) UPTIME_DAYS=0 ;;
    *) UPTIME_DAYS=$(( (NOW - BOOT_SECONDS) / 86400 )) ;;
esac

DEFERRALS=0
if [ -f "$STATE_FILE" ]; then
    VALUE=$(/usr/bin/plutil -extract uptimeDeferralCount raw -o - "$STATE_FILE" 2>/dev/null)
    case "$VALUE" in
        ''|*[!0-9]*) DEFERRALS=0 ;;
        *) DEFERRALS=$VALUE ;;
    esac
fi

if [ "$UPTIME_DAYS" -ge "$FORCE_DAYS" ] || [ "$DEFERRALS" -ge "$MAX_DEFERRALS" ]; then
    echo "<result>Force | Uptime ${UPTIME_DAYS}d | Deferrals ${DEFERRALS}/${MAX_DEFERRALS}</result>"
elif [ "$UPTIME_DAYS" -ge "$WARNING_DAYS" ]; then
    echo "<result>Warning | Uptime ${UPTIME_DAYS}d | Deferrals ${DEFERRALS}/${MAX_DEFERRALS}</result>"
else
    echo "<result>Healthy | Uptime ${UPTIME_DAYS}d</result>"
fi
