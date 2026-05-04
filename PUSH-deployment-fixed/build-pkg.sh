#!/bin/bash
# build-pkg.sh — Build PUSH.pkg for Jamf deployment
#
# Prerequisites:
#   - Xcode installed
#   - Both push-cli and push-ui built in Xcode (Debug or Release)
#   - Run from the PUSH-deployment directory
#
# Usage:
#   bash build-pkg.sh                    Build unsigned pkg (for testing)
#   bash build-pkg.sh --sign "Developer ID Installer: Your Name (TEAMID)"
#
# Output: PUSH-1.0.0.pkg

set -euo pipefail

VERSION="1.1.0"
IDENTIFIER="com.push.pkg"
INSTALL_LOCATION="/"
OUTPUT="PUSH-${VERSION}.pkg"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${BLUE}→${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
err()     { echo -e "${RED}✗${NC} $1"; exit 1; }

SIGN_IDENTITY=""
if [[ "${1:-}" == "--sign" && -n "${2:-}" ]]; then
    SIGN_IDENTITY="$2"
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   PUSH ${VERSION} — Package Builder                      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Find Xcode build products ──────────────────────────────────────────────────
# Find the Debug/Release products folder — parent of push-ui.app.
# Index.noindex is Xcode's index store, not a real build output, so skip it.
DERIVED=$(find ~/Library/Developer/Xcode/DerivedData \
    -name "push-ui.app" -path "*/Build/Products/*" \
    -not -path "*Index.noindex*" \
    -not -path "*.dSYM*" 2>/dev/null | head -1 | \
    xargs dirname 2>/dev/null || echo "")

if [[ -z "$DERIVED" ]]; then
    err "Cannot find Xcode build products. Build push-ui and push-cli in Xcode first."
fi

log "Found build products at: $DERIVED"

CLI_SRC="$DERIVED/push-cli"
UI_SRC="$DERIVED/push-ui.app"

[[ -f "$CLI_SRC" ]]  || err "push-cli not found at $CLI_SRC — build push-cli target first"
[[ -d "$UI_SRC" ]]   || err "push-ui.app not found at $UI_SRC — build push-ui target first"

ARCH=$(lipo -archs "$CLI_SRC" 2>/dev/null | tr ' ' ',' || file "$CLI_SRC" | grep -oE 'arm64|x86_64' | tr '
' ',' || echo 'binary')
success "push-cli found: arch=${ARCH%,}"
success "push-ui.app found"

# ── Copy binaries into payload ─────────────────────────────────────────────────
PAYLOAD="pkg-build/payload"
log "Copying binaries into payload…"

cp "$CLI_SRC" "$PAYLOAD/Library/Management/PUSH/push-cli"
chmod 755 "$PAYLOAD/Library/Management/PUSH/push-cli"

rm -rf "$PAYLOAD/Library/Management/PUSH/push-ui.app"
cp -r "$UI_SRC" "$PAYLOAD/Library/Management/PUSH/push-ui.app"

success "Binaries copied"

# ── Bundle mist-cli.pkg if present ────────────────────────────────────────────
MIST_PKG="pkg-build/payload/Library/Management/PUSH/mist-cli.pkg"
if [[ -f "$MIST_PKG" ]]; then
    log "Bundling mist-cli.pkg into payload…"
    chmod 644 "$MIST_PKG"
    success "mist-cli.pkg bundled ($(du -sh "$MIST_PKG" | cut -f1))"
else
    warn "mist-cli.pkg not found at $MIST_PKG — major upgrades will fall back to softwareupdate"
    warn "Place mist-cli.pkg at: $MIST_PKG and rebuild to include it"
fi

# ── Set script permissions ─────────────────────────────────────────────────────
chmod +x pkg-build/scripts/preinstall
chmod +x pkg-build/scripts/postinstall

# ── Build component pkg ────────────────────────────────────────────────────────
log "Building component package…"

COMPONENT_PKG="/tmp/push-component.pkg"
pkgbuild \
    --root "$PAYLOAD" \
    --scripts "pkg-build/scripts" \
    --identifier "$IDENTIFIER" \
    --version "$VERSION" \
    --install-location "$INSTALL_LOCATION" \
    --min-os-version "13.0" \
    "$COMPONENT_PKG"

success "Component pkg built"

# ── Build distribution pkg ────────────────────────────────────────────────────
log "Building distribution package…"

DIST_XML="/tmp/push-distribution.xml"
cat > "$DIST_XML" << DISTEOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>PUSH — Software Update Enforcement</title>
    <organization>com.push</organization>
    <domains enable_localSystem="true"/>
    <options customize="never" require-scripts="true" rootVolumeOnly="true"/>
    <welcome file="welcome.html" mime-type="text/html"/>
    <pkg-ref id="${IDENTIFIER}"/>
    <options hostArchitectures="arm64,x86_64"/>
    <choices-outline>
        <line choice="${IDENTIFIER}"/>
    </choices-outline>
    <choice id="${IDENTIFIER}" visible="false">
        <pkg-ref id="${IDENTIFIER}"/>
    </choice>
    <pkg-ref id="${IDENTIFIER}" version="${VERSION}" onConclusion="none">push-component.pkg</pkg-ref>
</installer-gui-script>
DISTEOF

if [[ -n "$SIGN_IDENTITY" ]]; then
    productbuild \
        --distribution "$DIST_XML" \
        --package-path /tmp \
        --sign "$SIGN_IDENTITY" \
        "$OUTPUT"
    success "Signed pkg built: $OUTPUT"
else
    productbuild \
        --distribution "$DIST_XML" \
        --package-path /tmp \
        "$OUTPUT"
    warn "Unsigned pkg built: $OUTPUT (use --sign for production)"
fi

# ── Cleanup ────────────────────────────────────────────────────────────────────
rm -f "$COMPONENT_PKG" "$DIST_XML"

# ── Summary ────────────────────────────────────────────────────────────────────
SIZE=$(du -sh "$OUTPUT" | cut -f1)
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   Build complete                                      ║"
echo "╚══════════════════════════════════════════════════════╝"
success "Output: $OUTPUT ($SIZE)"
echo ""
echo "Next steps:"
echo "  1. Upload $OUTPUT to Jamf Pro → Settings → Packages"
echo "  2. Create a Policy → Packages → add PUSH-${VERSION}.pkg"
echo "  3. Add Scripts → add push-jamf-postinstall.sh as After"
echo "  4. Scope to your target smart group"
echo ""
