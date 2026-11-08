#!/bin/bash
# Developer: Sebastian Santos — PUSH-DEV-SEBASTIAN-SANTOS
# Explicit products only. No app execution or service activation.
set -euo pipefail
[[ $# == 2 ]] || { echo 'Usage: build-client-component.sh /absolute/JamfCheckIn.app /absolute/output.pkg' >&2; exit 2; }
app="$1"; output="$2"
packaging="$(cd "$(dirname "$0")" && pwd)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/jamf-client.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/payload/Applications" "$stage/payload/Library/LaunchAgents" "$stage/scripts"
ditto "$app" "$stage/payload/Applications/JamfCheckIn.app"
codesign --force --sign - --timestamp=none "$stage/payload/Applications/JamfCheckIn.app"
codesign --verify --deep --strict "$stage/payload/Applications/JamfCheckIn.app"
cp "$packaging/com.sebastianitconsulting.jamfcheckin.plist" "$stage/payload/Library/LaunchAgents/"
cp "$packaging/client-preinstall" "$stage/scripts/preinstall"
chmod 755 "$stage/scripts/preinstall"
pkgbuild --analyze --root "$stage/payload" "$stage/components.plist"
plutil -replace 0.BundleIsRelocatable -bool NO "$stage/components.plist"
plutil -replace 0.BundleIsVersionChecked -bool NO "$stage/components.plist"
pkgbuild --root "$stage/payload" --component-plist "$stage/components.plist" --scripts "$stage/scripts" --ownership recommended --identifier com.sebastianitconsulting.jamfcheckin.pkg --version 1.1.1 --install-location / "$output"
echo 'Built JamfCheckIn client component. Nothing launched or installed.'
