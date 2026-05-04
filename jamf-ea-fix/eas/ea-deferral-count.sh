#!/bin/bash
# PUSH — Deferral Count EA
# Extension Attribute Type: Script
# Data Type: Integer
#
# Returns: number of times user has clicked "Remind Me Later" in current cycle.
# Resets to 0 after a successful upgrade or `push-cli reset`.

STATE_FILE="/Library/Management/PUSH/state.json"

if [ ! -f "$STATE_FILE" ]; then
    echo "<result>0</result>"
    exit 0
fi

COUNT=$(/usr/bin/python3 -c "
import json
try:
    d = json.load(open('$STATE_FILE'))
    print(d.get('deferralCount', 0))
except Exception:
    print(0)
" 2>/dev/null)

echo "<result>${COUNT:-0}</result>"
