#!/bin/bash
# Jamf Extension Attribute: JamfCheckIn status
# Data type: String. Inventory Display: Extension Attributes.
# Build Smart Groups on values like "Not installed" or "Installed not running".

APP="/Applications/JamfCheckIn.app"

if [ ! -d "$APP" ]; then
    echo "<result>Not installed</result>"
    exit 0
fi

VER=$(/usr/bin/defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
[ -z "$VER" ] && VER="?"

if /usr/bin/pgrep -x "JamfCheckIn" >/dev/null 2>&1; then
    echo "<result>Running ${VER}</result>"
else
    echo "<result>Installed not running ${VER}</result>"
fi
