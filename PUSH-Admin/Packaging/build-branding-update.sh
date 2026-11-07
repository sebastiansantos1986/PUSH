#!/bin/bash
# Developer: Sebastian Santos
# Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
set -euo pipefail
[[ $# == 3 ]] || { echo 'Usage: build-branding-update.sh engine-1.9.0.pkg admin-0.9.0.pkg output.pkg' >&2; exit 2; }
engine="$1"; companion="$2"; output="$3"
stage="$(mktemp -d "${TMPDIR:-/tmp}/push-branding-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
pkgutil --expand "$engine" "$stage/engine"
grep -q 'identifier="com.push.pkg"' "$stage/engine/push-component.pkg/PackageInfo"
grep -q 'version="1.9.0"' "$stage/engine/push-component.pkg/PackageInfo"
pkgutil --flatten "$stage/engine/push-component.pkg" "$stage/push-engine.pkg"
cp "$companion" "$stage/push-admin.pkg"
pkgutil --expand "$companion" "$stage/admin"
grep -q 'identifier="com.push.admin.pkg"' "$stage/admin/PackageInfo"
grep -q 'version="0.9.0"' "$stage/admin/PackageInfo"
mkdir "$stage/resources"
cat > "$stage/resources/welcome.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><style>body{font-family:-apple-system,sans-serif;font-size:14px;line-height:1.5}h1{font-size:24px}</style></head><body>
<h1>PUSH — User Status &amp; Deadline Recovery</h1>
<p>Developer: Sebastian Santos</p>
<p>Updates PUSH Admin to 0.9.0 and the PUSH engine to 1.9.0.</p>
<p>Adds a read-only user menu-bar app with guarded update requests, plus deadline failure notices with persistent countdowns and bounded automatic retries. IT-only blockers do not get a false automatic bypass.</p>
<p>Refresh only reads installed policy, saved results and service status. It does not start checks, prompts, registration, updates or monitoring.</p>
<p>Quit PUSH Admin before installing. Previous engine, settings, state, health records and both monitor definitions are backed up. Existing policy is preserved. Both monitors remain paused after installation.</p>
<p>Open /Applications/PUSH Admin.app and select User Status &amp; Recovery. Selecting an image only changes the draft; Apply and monitoring remain explicit administrator actions.</p>
<p>This is an unsigned local test package. Installation does not launch either app, perform an upgrade, or restart the Mac.</p>
</body></html>
HTML
cat > "$stage/Distribution.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
<title>PUSH — User Status &amp; Deadline Recovery</title>
<organization>com.push</organization>
<domains enable_localSystem="true" enable_currentUserHome="false" enable_anywhere="false"/>
<options customize="never" require-scripts="true" rootVolumeOnly="true" hostArchitectures="arm64,x86_64"/>
<volume-check><allowed-os-versions><os-version min="14.0"/></allowed-os-versions></volume-check>
<welcome file="welcome.html" mime-type="text/html"/>
<choices-outline><line choice="engine"/><line choice="companion"/></choices-outline>
<choice id="engine" visible="false"><pkg-ref id="com.push.pkg"/></choice>
<choice id="companion" visible="false"><pkg-ref id="com.push.admin.pkg"/></choice>
<pkg-ref id="com.push.pkg" version="1.9.0" onConclusion="none">push-engine.pkg</pkg-ref>
<pkg-ref id="com.push.admin.pkg" version="0.9.0" onConclusion="none">push-admin.pkg</pkg-ref>
</installer-gui-script>
XML
productbuild --distribution "$stage/Distribution.xml" --resources "$stage/resources" --package-path "$stage" "$output"
echo 'Built the combined guided setup release. No package was installed and no application was launched.'
