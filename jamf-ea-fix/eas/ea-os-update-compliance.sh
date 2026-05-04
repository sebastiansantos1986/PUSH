#!/bin/bash
# PUSH — OS Update Compliance EA
# Extension Attribute Type: Script
# Data Type: String
#
# Returns one of:
#   Compliant
#   Non-Compliant | Running: 15.7.4 | Target: 26.4.1 | Deferrals: 0/7
#   Past Deadline | Running: 15.7.4 | Target: 26.4.1
#   Install Started | Running: 15.7.4 → 26.4.1
#   Not configured
#   PUSH not installed

STATE_FILE="/Library/Management/PUSH/state.json"
CONFIG_FILE="/Library/Management/PUSH/config.yaml"
PUSH_CLI="/Library/Management/PUSH/push-cli"

# Helper: pull a top-level yaml value cleanly, stripping quotes and whitespace
yaml_value() {
    local key="$1"
    grep -E "^[[:space:]]*${key}:" "$CONFIG_FILE" 2>/dev/null \
        | head -n 1 \
        | sed -E "s/^[[:space:]]*${key}:[[:space:]]*//" \
        | sed -E 's/^"//; s/"$//' \
        | sed -E "s/^'//; s/'$//"
}

# Helper: pull a JSON scalar from state.json
state_value() {
    local key="$1"
    /usr/bin/python3 -c "
import json
try:
    d = json.load(open('$STATE_FILE'))
    v = d.get('$key', '')
    if isinstance(v, bool):
        print('true' if v else 'false')
    else:
        print(v)
except Exception:
    print('')
" 2>/dev/null
}

# ── Fast path: PUSH not installed ─────────────────────────────────────────────
if [ ! -x "$PUSH_CLI" ]; then
    echo "<result>PUSH not installed</result>"
    exit 0
fi

# ── Read state ────────────────────────────────────────────────────────────────
CURRENT=$(/usr/bin/sw_vers -productVersion)
TARGET=$(yaml_value "targetVersion")
DEADLINE=$(yaml_value "deadline")
MAX_DEFERRALS=$(yaml_value "maxDeferrals")

DEFERRAL_COUNT=$(state_value "deferralCount")
INSTALL_STARTED=$(state_value "installStarted")
INSTALL_COMPLETED=$(state_value "installCompleted")

[ -z "$DEFERRAL_COUNT" ] && DEFERRAL_COUNT=0
[ -z "$MAX_DEFERRALS" ] && MAX_DEFERRALS=7

# ── No target → not configured ────────────────────────────────────────────────
if [ -z "$TARGET" ]; then
    echo "<result>Not configured</result>"
    exit 0
fi

# ── Compare versions ──────────────────────────────────────────────────────────
COMPLIANT=$(/usr/bin/python3 -c "
a = list(map(int, '$CURRENT'.split('.')))
b = list(map(int, '$TARGET'.split('.')))
while len(a) < len(b): a.append(0)
while len(b) < len(a): b.append(0)
print('true' if a >= b else 'false')
" 2>/dev/null)

if [ "$COMPLIANT" = "true" ]; then
    echo "<result>Compliant</result>"
    exit 0
fi

# ── Install in progress ───────────────────────────────────────────────────────
if [ "$INSTALL_STARTED" = "true" ] && [ "$INSTALL_COMPLETED" != "true" ]; then
    echo "<result>Install Started | Running: $CURRENT → $TARGET</result>"
    exit 0
fi

# ── Past deadline check ───────────────────────────────────────────────────────
PAST_DEADLINE=false
if [ -n "$DEADLINE" ]; then
    DEADLINE_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$DEADLINE" +%s 2>/dev/null)
    NOW_EPOCH=$(date -u +%s)
    if [ -n "$DEADLINE_EPOCH" ] && [ "$NOW_EPOCH" -gt "$DEADLINE_EPOCH" ]; then
        PAST_DEADLINE=true
    fi
fi

if [ "$PAST_DEADLINE" = "true" ]; then
    echo "<result>Past Deadline | Running: $CURRENT | Target: $TARGET</result>"
    exit 0
fi

# ── Default: non-compliant ────────────────────────────────────────────────────
echo "<result>Non-Compliant | Running: $CURRENT | Target: $TARGET | Deferrals: ${DEFERRAL_COUNT}/${MAX_DEFERRALS}</result>"
