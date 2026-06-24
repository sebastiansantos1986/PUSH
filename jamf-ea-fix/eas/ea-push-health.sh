#!/bin/bash
# PUSH - Health EA
# Extension Attribute Type: Script
# Data Type: String

PUSH_DIR="/Library/Management/PUSH"
PUSH_CLI="$PUSH_DIR/push-cli"
CONFIG_FILE="$PUSH_DIR/config.yaml"
LOG_FILE="$PUSH_DIR/logs/push.log"
DAEMON_LABEL="com.push.autoupdate"

if [ ! -x "$PUSH_CLI" ]; then
    echo "<result>Not Installed</result>"
    exit 0
fi

VERSION=$($PUSH_CLI --version 2>/dev/null | /usr/bin/awk '{print $NF}')
[ -z "$VERSION" ] && VERSION="Unknown"
VERSION=${VERSION#v}

if [ ! -f "$CONFIG_FILE" ]; then
    echo "<result>Attention | Version $VERSION | Config missing</result>"
    exit 0
fi

if ! /bin/launchctl print "system/$DAEMON_LABEL" >/dev/null 2>&1; then
    echo "<result>Attention | Version $VERSION | Daemon not loaded</result>"
    exit 0
fi

if [ ! -f "$LOG_FILE" ]; then
    echo "<result>Attention | Version $VERSION | No auto-check log</result>"
    exit 0
fi

NOW=$(/bin/date +%s)
LOG_MODIFIED=$(/usr/bin/stat -f %m "$LOG_FILE" 2>/dev/null)
[ -z "$LOG_MODIFIED" ] && LOG_MODIFIED=0
AGE_HOURS=$(( (NOW - LOG_MODIFIED) / 3600 ))

if [ "$AGE_HOURS" -gt 25 ]; then
    echo "<result>Attention | Version $VERSION | Auto-check stale ${AGE_HOURS}h</result>"
else
    echo "<result>Healthy | Version $VERSION | Daemon loaded | Last activity ${AGE_HOURS}h</result>"
fi
