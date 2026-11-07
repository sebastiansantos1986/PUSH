#!/bin/bash
# Developer: Sebastian Santos
# Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
# Use explicit build products; never search for a potentially stale DerivedData build.
set -euo pipefail
[[ $# == 2 ]] || { echo 'Usage: build-local-package.sh /absolute/Release/products /absolute/output.pkg' >&2; exit 2; }
products="$1"
output="$2"
packaging="$(cd "$(dirname "$0")" && pwd)"
stage="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/push-package.XXXXXX")"
trap '/bin/rm -rf "$stage"' EXIT
base="$stage/payload/Library/Management/PUSH"
/bin/mkdir -p "$base/Local-Test"
[[ -x "$products/push-cli" && -x "$products/push-ui.app/Contents/MacOS/push-ui" ]] || exit 1
/usr/bin/ditto "$products/push-cli" "$base/push-cli"
/usr/bin/ditto "$products/push-ui.app" "$base/push-ui.app"
/bin/cp "$packaging/default-config.yaml" "$base/Local-Test/default-config.yaml"
/bin/cp "$packaging/INSTALL-AND-TEST.txt" "$base/Local-Test/INSTALL-AND-TEST.txt"
/bin/cp "$packaging/../LICENSE" "$base/Local-Test/LICENSE"
/bin/chmod 755 "$base/push-cli"
/usr/bin/codesign --force --sign - --timestamp=none "$base/push-cli"
/usr/bin/codesign --force --sign - --timestamp=none "$base/push-ui.app"
/usr/bin/codesign --verify --strict "$base/push-cli"
/usr/bin/codesign --verify --deep --strict "$base/push-ui.app"
/usr/bin/pkgbuild --analyze --root "$stage/payload" "$stage/components.plist"
/usr/bin/plutil -replace 0.BundleIsRelocatable -bool NO "$stage/components.plist"
/usr/bin/plutil -replace 0.BundleIsVersionChecked -bool NO "$stage/components.plist"
/usr/bin/pkgbuild --root "$stage/payload" --component-plist "$stage/components.plist" \
    --scripts "$packaging/scripts" --ownership recommended \
    --identifier com.push.pkg --version 1.6.0 --install-location / "$stage/push-component.pkg"
cat > "$stage/Distribution.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
<title>PUSH 1.6.0 — Local Test</title>
<organization>com.push</organization>
<domains enable_localSystem="true" enable_currentUserHome="false" enable_anywhere="false"/>
<options customize="never" require-scripts="true" rootVolumeOnly="true" hostArchitectures="arm64,x86_64"/>
<volume-check><allowed-os-versions><os-version min="14.0"/></allowed-os-versions></volume-check>
<welcome file="welcome.html" mime-type="text/html"/>
<choices-outline><line choice="push"/></choices-outline>
<choice id="push" visible="false"><pkg-ref id="com.push.pkg"/></choice>
<pkg-ref id="com.push.pkg" version="1.6.0" onConclusion="none">push-component.pkg</pkg-ref>
</installer-gui-script>
XML
/usr/bin/productbuild --distribution "$stage/Distribution.xml" --resources "$packaging/resources" \
    --package-path "$stage" "$output"
echo "Built $output. No installation or app execution was performed."
