#!/bin/bash
# Developer: Sebastian Santos
# Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
set -euo pipefail
cd "$(dirname "$0")/.."
output_dir="${1:?Pass an absolute output directory}"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/push-admin-build.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
mkdir -p "$output_dir/PUSH Admin.app/Contents/MacOS" "$output_dir/PUSH Admin.app/Contents/Resources"
compiler_flags=()
if [[ "${PUSH_MACRO_SANDBOX_WORKAROUND:-0}" == 1 ]]; then compiler_flags=(-Xfrontend -disable-sandbox); fi
for architecture in arm64 x86_64; do
    xcrun swiftc -O -swift-version 5 -target "$architecture-apple-macos14.0" \
        -module-cache-path "$build_dir/modules" "${compiler_flags[@]}" \
        -framework SwiftUI -framework AppKit -framework IOKit Sources/*.swift -o "$build_dir/PUSHAdmin-$architecture"
done
lipo -create "$build_dir/PUSHAdmin-arm64" "$build_dir/PUSHAdmin-x86_64" -output "$output_dir/PUSH Admin.app/Contents/MacOS/PUSHAdmin"
cp Packaging/Info.plist "$output_dir/PUSH Admin.app/Contents/Info.plist"
client="${PUSH_CLIENT_PACKAGE:?Set PUSH_CLIENT_PACKAGE to the verified matching client package}"
[[ -f "$client" && ! -L "$client" ]] || exit 1
cp "$client" "$output_dir/PUSH Admin.app/Contents/Resources/PUSH-Client-1.9.1.pkg"
cp LICENSE "$output_dir/PUSH Admin.app/Contents/Resources/LICENSE"
cp Resources/PUSH-NonCompliant.png "$output_dir/PUSH Admin.app/Contents/Resources/PUSH-NonCompliant.png"
cp Resources/InstallAssistant.icns "$output_dir/PUSH Admin.app/Contents/Resources/InstallAssistant.icns"
codesign --force --sign - --timestamp=none "$output_dir/PUSH Admin.app"
codesign --verify --deep --strict "$output_dir/PUSH Admin.app"
mkdir -p "$build_dir/payload/Applications"
ditto "$output_dir/PUSH Admin.app" "$build_dir/payload/Applications/PUSH Admin.app"
pkgbuild --analyze --root "$build_dir/payload" "$build_dir/components.plist"
plutil -replace 0.BundleIsRelocatable -bool NO "$build_dir/components.plist"
pkgbuild --root "$build_dir/payload" --component-plist "$build_dir/components.plist" \
    --ownership recommended --identifier com.push.admin.pkg --version 1.1.0 --install-location / \
    "$output_dir/PUSH-Admin-1.1.0.pkg"
echo 'Built the companion app and package. Neither was launched or installed.'
