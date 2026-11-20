#!/bin/bash
# Developer: Sebastian Santos — PUSH-DEV-SEBASTIAN-SANTOS
# Packages PUSH only. JamfCheckIn and PUSH Admin are not deployed.
set -euo pipefail
[[ $# == 2 ]] || { echo 'Usage: build-client-package.sh engine.pkg output.pkg' >&2; exit 2; }
engine="$1"; output="$2"
stage="$(mktemp -d "${TMPDIR:-/tmp}/push-client.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
pkgutil --expand "$engine" "$stage/engine"
grep -q 'identifier="com.push.pkg"' "$stage/engine/push-component.pkg/PackageInfo"
grep -q 'version="1.16.7"' "$stage/engine/push-component.pkg/PackageInfo"
pkgutil --flatten "$stage/engine/push-component.pkg" "$stage/push-engine.pkg"
mkdir "$stage/resources"
cat > "$stage/resources/welcome.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><style>body{font-family:-apple-system,sans-serif;font-size:14px;line-height:1.5}</style></head><body>
<h1>PUSH Client</h1><p>Developer: Sebastian Santos</p>
<p>Installs PUSH 1.16.7 only. JamfCheckIn and PUSH Admin are not included. Existing JamfCheckIn installations are left unchanged.</p>
<p>Installed PUSH policy, state, credentials and images are preserved. PUSH monitors remain paused until explicitly enabled by a configured workflow. This installer does not launch an upgrade, download macOS or restart the Mac.</p>
<p>Self Service offers collect authorization when needed, show download and installer preparation progress, and display a final restart notice.</p>
<p>Local testing build: ad-hoc signed apps and unsigned installer. Production signing and notarization remain separate.</p></body></html>
HTML
cat > "$stage/Distribution.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
<title>PUSH Client 1.16.7</title><organization>com.push</organization>
<domains enable_localSystem="true" enable_currentUserHome="false" enable_anywhere="false"/>
<options customize="never" require-scripts="true" rootVolumeOnly="true" hostArchitectures="arm64,x86_64"/>
<volume-check><allowed-os-versions><os-version min="14.0"/></allowed-os-versions></volume-check>
<welcome file="welcome.html" mime-type="text/html"/>
<choices-outline><line choice="engine"/></choices-outline>
<choice id="engine" visible="false"><pkg-ref id="com.push.pkg"/></choice>
<pkg-ref id="com.push.pkg" version="1.16.7" onConclusion="none">push-engine.pkg</pkg-ref>
</installer-gui-script>
XML
productbuild --distribution "$stage/Distribution.xml" --resources "$stage/resources" --package-path "$stage" "$output"
echo 'Built PUSH Client only. Nothing installed, launched or activated.'
