#!/bin/bash
# Developer: Sebastian Santos — PUSH-DEV-SEBASTIAN-SANTOS
# Build only. Does not install, activate, download macOS or request a restart.
set -euo pipefail
cd "$(dirname "$0")/.."
repo="$PWD"
output="${1:-$repo/artifacts}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
client_version="$(sed -n 's/^let cliVersion = "\([0-9.]*\)"/\1/p' push-cli/main.swift)"
admin_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' PUSH-Admin/Packaging/Info.plist)"
[[ "$client_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$admin_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
flags=()
if [[ "${PUSH_MACRO_SANDBOX_WORKAROUND:-0}" == 1 ]]; then flags=('OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -disable-sandbox'); fi
xcodebuild -project PUSH.xcodeproj -scheme PUSH-All -configuration Release \
    -derivedDataPath "$output/DerivedData" CODE_SIGNING_ALLOWED=NO \
    'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO ${flags[@]+"${flags[@]}"} build
bash Packaging/build-local-package.sh "$output/DerivedData/Build/Products/Release" "$output/PUSH-Engine-$client_version.pkg"
bash Packaging/build-client-package.sh "$output/PUSH-Engine-$client_version.pkg" "$output/PUSH-Client-$client_version.pkg"
PUSH_CLIENT_PACKAGE="$output/PUSH-Client-$client_version.pkg" bash PUSH-Admin/Packaging/build.sh "$output/Admin"
/usr/bin/shasum -a 256 "$output/PUSH-Client-$client_version.pkg" "$output/Admin/PUSH-Admin-$admin_version.pkg" > "$output/SHA256SUMS.txt"
printf 'Built client %s and Admin %s in %s. Nothing was installed or activated.\n' "$client_version" "$admin_version" "$output"
