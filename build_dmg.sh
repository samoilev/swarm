#!/bin/bash
set -e

# Build DMG for FamilyTreeStudio
# Usage: ./build_dmg.sh

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Родословная Студия"
BUNDLE_ID="com.familytreestudio.app"
VERSION="1.3.0"
BUILD_DIR="$PROJECT_DIR/.build/arm64-apple-macosx/release"
BINARY="$BUILD_DIR/FamilyTreeStudio"
RESOURCE_BUNDLE="$BUILD_DIR/FamilyTreeStudio_FamilyTreeStudio.bundle"
ICON_SRC="$PROJECT_DIR/FamilyTreeStudio/Resources/AppIcon.icns"
DMG_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DMG_DIR/$APP_NAME.app"

echo "=== Building release binary ==="
cd "$PROJECT_DIR"
swift build -c release

echo "=== Creating .app bundle ==="
rm -rf "$DMG_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/FamilyTreeStudio"

# Copy resource bundle
cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"

# Copy icon
cp "$ICON_SRC" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FamilyTreeStudio</string>
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
            <string>Editor</string>
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

# Verify the app
echo "=== Verifying bundle ==="
codesign --sign - --force --deep "$APP_BUNDLE"
echo "Ad-hoc signed OK"

# Create DMG
echo "=== Creating DMG ==="
DMG_NAME="Родословная-Студия-${VERSION}.dmg"
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

echo ""
echo "=============================="
echo "DMG created: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
echo "=============================="
echo ""
echo "To install: Open the DMG and drag the app to Applications."
