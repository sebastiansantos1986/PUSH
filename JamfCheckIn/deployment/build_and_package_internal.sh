#!/bin/bash
#
# Internal build + package (NO Developer ID, NO notarization).
# Produces an installable .pkg for Jamf/MDM deployment.
#
# Why this works without notarization: an app installed by an MDM-pushed package
# is placed in /Applications WITHOUT the com.apple.quarantine flag, so an
# ad-hoc-signed app launches normally on managed Macs. No paid Apple Developer
# account needed.
#
# Usage:  chmod +x build_and_package_internal.sh && ./build_and_package_internal.sh
# ---------------------------------------------------------------------------

set -euo pipefail

APP_NAME="JamfCheckIn"
BUNDLE_ID="com.sebastianitconsulting.jamfcheckin"
VERSION="1.0"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DD="$BUILD_DIR/dd"
PKG_ROOT="$BUILD_DIR/pkgroot"
PKG="$BUILD_DIR/$APP_NAME-$VERSION.pkg"

rm -rf "$BUILD_DIR"
mkdir -p "$PKG_ROOT/Applications" "$PKG_ROOT/Library/LaunchAgents" "$PKG_ROOT/Library/LaunchDaemons"

echo "==> Building Release (unsigned)…"
xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$DD" \
    CODE_SIGNING_ALLOWED=NO \
    build

APP="$DD/Build/Products/Release/$APP_NAME.app"
cp -R "$APP" "$PKG_ROOT/Applications/"

echo "==> Ad-hoc signing the app…"
/usr/bin/codesign --force --deep --sign - "$PKG_ROOT/Applications/$APP_NAME.app"

echo "==> Adding LaunchAgent + auto check-in LaunchDaemon…"
cp "$SCRIPT_DIR/$BUNDLE_ID.plist" "$PKG_ROOT/Library/LaunchAgents/"
cp "$SCRIPT_DIR/$BUNDLE_ID.autocheckin.plist" "$PKG_ROOT/Library/LaunchDaemons/"
cp "$SCRIPT_DIR/$BUNDLE_ID.inventory.plist" "$PKG_ROOT/Library/LaunchDaemons/"
chmod +x "$SCRIPT_DIR/scripts/postinstall"

echo "==> Building package…"
pkgbuild --root "$PKG_ROOT" \
    --identifier "$BUNDLE_ID.pkg" \
    --version "$VERSION" \
    --scripts "$SCRIPT_DIR/scripts" \
    --install-location "/" \
    "$PKG"

echo ""
echo "Done. Upload this to Jamf and deploy to /Applications:"
echo "  $PKG"
