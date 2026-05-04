#!/bin/bash
# PUSH — Deferral Reasons EA
# Extension Attribute Type: Script
# Data Type: String
#
# Returns: comma-separated list of reasons the user gave when deferring,
# or "None" if no reasons have been recorded.
#
# Note: requires ui.requireDeferralReason: true in config.yaml for the user
# to be prompted for a reason at deferral time. If that's false (the default),
# this EA will always return "None".

STATE_FILE="/Library/Management/PUSH/state.json"

if [ ! -f "$STATE_FILE" ]; then
    echo "<result>None</result>"
    exit 0
fi

REASONS=$(/usr/bin/python3 -c "
import json
try:
    d = json.load(open('$STATE_FILE'))
    reasons = d.get('deferralReasons', [])
    print(', '.join(reasons) if reasons else 'None')
except Exception:
    print('None')
" 2>/dev/null)

echo "<result>${REASONS:-None}</result>"
