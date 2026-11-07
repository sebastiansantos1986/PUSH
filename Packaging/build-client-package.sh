#!/bin/bash
# Developer: Sebastian Santos — PUSH-DEV-SEBASTIAN-SANTOS
# Combines engine + JamfCheckIn only. Never include PUSH Admin on client Macs.
set -euo pipefail
[[ $# == 3 ]] || { echo 'Usage: build-client-package.sh engine.pkg jamfcheckin.pkg output.pkg' >&2; exit 2; }
engine="$1"; jamf="$2"; output="$3"
stage="$(mktemp -d "${TMPDIR:-/tmp}/push-client.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
pkgutil --expand "$engine" "$stage/engine"
grep -q 'identifier="com.push.pkg"' "$stage/engine/push-component.pkg/PackageInfo"
grep -q 'version="1.9.1"' "$stage/engine/push-component.pkg/PackageInfo"
pkgutil --flatten "$stage/engine/push-component.pkg" "$stage/push-engine.pkg"
pkgutil --expand "$jamf" "$stage/jamf"
grep -q 'identifier="com.sebastianitconsulting.jamfcheckin.pkg"' "$stage/jamf/PackageInfo"
grep -q 'version="1.1.0"' "$stage/jamf/PackageInfo"
cp "$jamf" "$stage/jamfcheckin.pkg"
mkdir "$stage/resources"
cat > "$stage/resources/welcome.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><style>body{font-family:-apple-system,sans-serif;font-size:14px;line-height:1.5}</style></head><body>
<h1>PUSH Client — JamfCheckIn Integration</h1><p>Developer: Sebastian Santos</p>
<p>Installs PUSH 1.9.1 and JamfCheckIn 1.1.0. PUSH Admin is a separate IT-only installer and is not included.</p>
<p>JamfCheckIn displays PUSH status, saved failures, countdowns and update progress. PUSH update requests use a guarded channel without a user password prompt. Existing Jamf check-in and inventory administrator actions remain separate.</p>
<p>Previous PUSH and JamfCheckIn files are backed up. Installed PUSH policy, state, credentials and images are preserved. The old standalone PUSH Status menu is retired after backup.</p>
<p>PUSH monitors remain paused. Installation does not launch apps, run a Jamf check-in, download/install updates, change wallpaper or restart. JamfCheckIn opens at the next graphical login, or you can open it manually.</p>
<p>The client does not silently delete an existing PUSH Admin app from older combined installers. Manage removal separately on employee computers.</p>
<p>Local test build: ad-hoc signed apps, unsigned installer. Use verified Developer ID signing and notarization before fleet rollout.</p></body></html>
HTML
cat > "$stage/Distribution.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
<title>PUSH Client 1.9.1 — JamfCheckIn</title><organization>com.push</organization>
<domains enable_localSystem="true" enable_currentUserHome="false" enable_anywhere="false"/>
<options customize="never" require-scripts="true" rootVolumeOnly="true" hostArchitectures="arm64,x86_64"/>
<volume-check><allowed-os-versions><os-version min="14.0"/></allowed-os-versions></volume-check>
<welcome file="welcome.html" mime-type="text/html"/>
<choices-outline><line choice="engine"/><line choice="menu"/></choices-outline>
<choice id="engine" visible="false"><pkg-ref id="com.push.pkg"/></choice>
<choice id="menu" visible="false"><pkg-ref id="com.sebastianitconsulting.jamfcheckin.pkg"/></choice>
<pkg-ref id="com.push.pkg" version="1.9.1" onConclusion="none">push-engine.pkg</pkg-ref>
<pkg-ref id="com.sebastianitconsulting.jamfcheckin.pkg" version="1.1.0" onConclusion="none">jamfcheckin.pkg</pkg-ref>
</installer-gui-script>
XML
productbuild --distribution "$stage/Distribution.xml" --resources "$stage/resources" --package-path "$stage" "$output"
echo 'Built PUSH Client only. Nothing installed, launched or activated.'
