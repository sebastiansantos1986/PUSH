#!/bin/bash
#
# Build -> sign (Developer ID) -> notarize -> package JamfCheckIn for Jamf.
# Run on a Mac with Xcode + your Developer ID certificates installed.
#
# ONE-TIME SETUP (store notary credentials in the keychain):
#   xcrun notarytool store-credentials "JamfCheckIn-Notary" \
#       --apple-id "you@sebastianitconsulting.com" \
#       --team-id "YOUR_TEAM_ID" \
#       --password "app-specific-password"
#
# FILL IN the three values below, then: chmod +x build_and_package.sh && ./build_and_package.sh
# ---------------------------------------------------------------------------

set -euo pipefail

# ====== FILL THESE IN ======
TEAM_ID="YOUR_TEAM_ID"                                              # e.g. AB12CD34EF
DEV_ID_INSTALLER="Developer ID Installer: Sebastian IT Consulting (${TEAM_ID})"
NOTARY_PROFILE="JamfCheckIn-Notary"                                # from store-credentials above
# ===========================

APP_NAME="JamfCheckIn"
BUNDLE_ID="com.sebastianitconsulting.jamfcheckin"
VERSION="1.0"

# Resolve paths relative to this script (deployment/ lives next to the .xcodeproj)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
PKG_ROOT="$BUILD_DIR/pkgroot"
PKG_UNSIGNED="$BUILD_DIR/$APP_NAME-unsigned.pkg"
PKG_SIGNED="$BUILD_DIR/$APP_NAME-$VERSION.pkg"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$EXPORT_DIR" "$PKG_ROOT/Applications"

echo "==> Archiving (Release, Developer ID, hardened runtime)…"
xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    archive

# Export options for a Developer ID (outside-the-store) build
cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>${TEAM_ID}</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF

echo "==> Exporting signed .app…"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

cp -R "$EXPORT_DIR/$APP_NAME.app" "$PKG_ROOT/Applications/"

echo "==> Building component package…"
# Lay the managed LaunchAgent + auto check-in LaunchDaemon into the package too.
mkdir -p "$PKG_ROOT/Library/LaunchAgents" "$PKG_ROOT/Library/LaunchDaemons"
cp "$SCRIPT_DIR/$BUNDLE_ID.plist" "$PKG_ROOT/Library/LaunchAgents/"
cp "$SCRIPT_DIR/$BUNDLE_ID.autocheckin.plist" "$PKG_ROOT/Library/LaunchDaemons/"
cp "$SCRIPT_DIR/$BUNDLE_ID.inventory.plist" "$PKG_ROOT/Library/LaunchDaemons/"
chmod +x "$SCRIPT_DIR/scripts/postinstall"

pkgbuild --root "$PKG_ROOT" \
    --identifier "$BUNDLE_ID.pkg" \
    --version "$VERSION" \
    --scripts "$SCRIPT_DIR/scripts" \
    --install-location "/" \
    "$PKG_UNSIGNED"

echo "==> Signing package with Developer ID Installer…"
productsign --sign "$DEV_ID_INSTALLER" "$PKG_UNSIGNED" "$PKG_SIGNED"

echo "==> Notarizing package…"
xcrun notarytool submit "$PKG_SIGNED" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling…"
xcrun stapler staple "$PKG_SIGNED"

echo ""
echo "Done. Upload this to Jamf and deploy to /Applications:"
echo "  $PKG_SIGNED"
