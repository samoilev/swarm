#!/bin/bash
set -e

# Build DMG for Swarm
# Usage: ./build_dmg.sh

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Swarm"
BUNDLE_ID="com.samoilev.swarm"
VERSION="$(cat "$(cd "$(dirname "$0")" && pwd)/VERSION" 2>/dev/null || echo "1.5.0")"
BUILD_DIR="$PROJECT_DIR/.build/arm64-apple-macosx/release"
BINARY="$BUILD_DIR/Swarm"
# Two SwiftPM resource bundles after the SwarmCore split:
#   - App bundle: AppIcon.icns (loaded via Bundle.module in the app target)
#   - Core bundle: local place indexes and offline map vectors
APP_RESOURCE_BUNDLE="$BUILD_DIR/Swarm_Swarm.bundle"
CORE_RESOURCE_BUNDLE="$BUILD_DIR/Swarm_SwarmCore.bundle"
ICON_SRC="$PROJECT_DIR/Swarm/App/Resources/AppIcon.icns"
DMG_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DMG_DIR/$APP_NAME.app"

echo "=== Building release binary ==="
cd "$PROJECT_DIR"
./Scripts/run-tests.sh
swift build -c release

echo "=== Creating .app bundle ==="
rm -rf "$DMG_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/Swarm"

# Copy resource bundles (app icon + core data tables)
cp -R "$APP_RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
cp -R "$CORE_RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"

# Copy icon
cp "$ICON_SRC" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Swarm</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.lifestyle</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>GEDCOM File</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>ged</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.gedcom</string>
            </array>
        </dict>
    </array>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "=== .app bundle created at: $APP_BUNDLE ==="

# Sign the app. A real Developer ID (set CODESIGN_IDENTITY) produces a
# distributable, notarizable build with the hardened runtime; otherwise fall
# back to an ad-hoc signature for local use only (Gatekeeper will warn).
echo "=== Signing bundle ==="
if [ -n "$CODESIGN_IDENTITY" ]; then
    codesign --sign "$CODESIGN_IDENTITY" --force --deep --options runtime --timestamp "$APP_BUNDLE"
    echo "Signed with: $CODESIGN_IDENTITY"
else
    codesign --sign - --force --deep "$APP_BUNDLE"
    echo "Ad-hoc signed (local use only; not notarizable)"
fi

echo "=== Verifying app bundle ==="
test -x "$APP_BUNDLE/Contents/MacOS/Swarm"
plutil -lint "$APP_BUNDLE/Contents/Info.plist"
codesign --verify --deep --strict "$APP_BUNDLE"
echo "Architecture: $(lipo -archs "$APP_BUNDLE/Contents/MacOS/Swarm")"
echo "Signing: $(codesign -dv --verbose=2 "$APP_BUNDLE" 2>&1 | grep -E 'Signature|Authority|TeamIdentifier' | tr '\n' ' ')"

# Create DMG
echo "=== Creating DMG ==="
DMG_NAME="Swarm-${VERSION}.dmg"
DMG_PATH="$DMG_DIR/$DMG_NAME"
DMG_TEMP="$DMG_DIR/dmg_temp"

rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# Create symlink to Applications
ln -s /Applications "$DMG_TEMP/Applications"

# Create the DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_TEMP"

echo "=== Verifying DMG ==="
hdiutil verify "$DMG_PATH"
shasum -a 256 "$DMG_PATH" | tee "$DMG_PATH.sha256"

# Notarize + staple when credentials are available (requires Developer ID signing).
# Provide either a stored notarytool keychain profile via NOTARY_PROFILE, or
# APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD (an app-specific password).
if [ -n "$CODESIGN_IDENTITY" ] && { [ -n "$NOTARY_PROFILE" ] || [ -n "$APPLE_ID" ]; }; then
    echo "=== Notarizing DMG ==="
    if [ -n "$NOTARY_PROFILE" ]; then
        xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    else
        xcrun notarytool submit "$DMG_PATH" \
            --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
    fi
    xcrun stapler staple "$DMG_PATH"
    echo "Notarized and stapled."
else
    echo "Skipping notarization — set CODESIGN_IDENTITY plus NOTARY_PROFILE"
    echo "(or APPLE_ID/APPLE_TEAM_ID/APPLE_APP_PASSWORD) to enable a distributable build."
fi

echo ""
echo "=============================="
echo "DMG created: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
echo "=============================="
echo ""
echo "To install: Open the DMG and drag the app to Applications."
