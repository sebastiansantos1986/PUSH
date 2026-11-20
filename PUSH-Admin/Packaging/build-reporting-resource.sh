#!/bin/bash
# PUSH Admin — Developer: Sebastian Santos — PUSH-DEV-SEBASTIAN-SANTOS
# Build a read-only inventory resource. Never run the helper or any installer.
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/push-hardware-resource.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
flags=()
if [[ "${PUSH_MACRO_SANDBOX_WORKAROUND:-0}" == 1 ]]; then flags=(-Xfrontend -disable-sandbox);fi
for architecture in arm64 x86_64; do
    minimum=11.0
    [[ "$architecture" != x86_64 ]] || minimum=10.15
    xcrun swiftc -O -swift-version 5 -target "$architecture-apple-macos$minimum" \
        -module-cache-path "$stage/modules-$architecture" "${flags[@]}" -framework IOKit \
        "$project/HardwareReporter/PUSHTahoeReadiness.swift" -o "$stage/helper-$architecture"
done
base="$stage/payload/Library/Management/PUSH/Tahoe-Campaign"
mkdir -p "$base"
lipo -create "$stage/helper-arm64" "$stage/helper-x86_64" -output "$base/push-tahoe-readiness"
cp "$project/Resources/AppleHardwareCatalog.json" "$base/AppleHardwareCatalog.json"
chmod 755 "$base/push-tahoe-readiness"
chmod 644 "$base/AppleHardwareCatalog.json"
codesign --force --sign - --timestamp=none "$base/push-tahoe-readiness"
codesign --verify --strict "$base/push-tahoe-readiness"
pkgbuild --root "$stage/payload" --ownership recommended --identifier com.push.tahoe.readiness \
    --version 1.0.0 --install-location / "$project/Resources/PUSH-Tahoe-Readiness.pkg"
