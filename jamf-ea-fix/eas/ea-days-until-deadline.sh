#!/bin/bash
# PUSH — Days Until Deadline EA
# Extension Attribute Type: Script
# Data Type: Integer
#
# Returns: days remaining until update deadline.
#   N   = N days until deadline
#   0   = deadline today
#   -N  = N days past deadline
#   -1  = no deadline configured (or PUSH not installed)

CONFIG_FILE="/Library/Management/PUSH/config.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "<result>-1</result>"
    exit 0
fi

# Pull deadline from yaml. The line looks like:    deadline: "2026-05-11T15:27:59Z"
# Use sed instead of awk to handle the quotes and any leading whitespace cleanly.
DEADLINE=$(grep -E "^[[:space:]]*deadline:" "$CONFIG_FILE" 2>/dev/null \
    | head -n 1 \
    | sed -E 's/^[[:space:]]*deadline:[[:space:]]*//' \
    | sed -E 's/^"//; s/"$//' \
    | sed -E "s/^'//; s/'$//")

if [ -z "$DEADLINE" ]; then
    echo "<result>-1</result>"
    exit 0
fi

DAYS=$(/usr/bin/python3 -c "
from datetime import datetime, timezone
try:
    s = '$DEADLINE'.replace('Z', '+00:00')
    dl = datetime.fromisoformat(s)
    now = datetime.now(timezone.utc)
    print((dl - now).days)
except Exception:
    print(-1)
" 2>/dev/null)

echo "<result>${DAYS:--1}</result>"
