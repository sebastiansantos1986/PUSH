#!/bin/bash
# Developer: Sebastian Santos — PUSH-DEV-SEBASTIAN-SANTOS
# Build only. No installer, application or monitor is executed.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:?Pass a new absolute artifact directory}"
[[ "$out" == /* && ! -e "$out" ]] || { echo 'Choose a NEW absolute artifact directory.' >&2; exit 2; }
mkdir -p "$out"
cd "$repo"
xcodebuild -project PUSH.xcodeproj -scheme PUSH-All -configuration Release \
  -derivedDataPath "$out/build/Engine" CODE_SIGNING_ALLOWED=NO \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
xcodebuild -project JamfCheckIn/JamfCheckIn.xcodeproj -scheme JamfCheckIn -configuration Release \
  -derivedDataPath "$out/build/JamfCheckIn" CODE_SIGNING_ALLOWED=NO \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
bash Packaging/build-local-package.sh "$out/build/Engine/Build/Products/Release" "$out/PUSH-1.9.1-Engine.pkg"
bash JamfCheckIn/deployment/build-client-component.sh "$out/build/JamfCheckIn/Build/Products/Release/JamfCheckIn.app" "$out/JamfCheckIn-1.1.0-Client.pkg"
bash Packaging/build-client-package.sh "$out/PUSH-1.9.1-Engine.pkg" "$out/JamfCheckIn-1.1.0-Client.pkg" "$out/PUSH-Client-1.9.1.pkg"
PUSH_CLIENT_PACKAGE="$out/PUSH-Client-1.9.1.pkg" bash PUSH-Admin/Packaging/build.sh "$out"
echo 'Built client and Admin packages. Nothing installed, launched or activated.'
