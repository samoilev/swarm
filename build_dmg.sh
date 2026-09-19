#!/bin/bash
set -e

# Build DMG for Swarm
# Usage: ./build_dmg.sh

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Swarm"
BUNDLE_ID="com.samoilev.swarm"
VERSION="$(cat "$(cd "$(dirname "$0")" && pwd)/VERSION" 2>/dev/null || echo "1.5.0")"

# Single source of truth for the floor: Package.swift. LSMinimumSystemVersion below
# reads the same value, so the manifest and the bundle cannot drift apart.
MIN_OS="$(sed -n 's/.*platforms: \[\.macOS("\([0-9.]*\)")\].*/\1/p' "$PROJECT_DIR/Package.swift")"
SDK_VERSION="$(xcrun --show-sdk-version)"

# Two things this has to get right, neither of them the default.
#
# 1. Universal. `--arch` twice cross-compiles the Intel slice from an Apple silicon
#    machine; no extra toolchain needed.
# 2. The recorded SDK version. macOS gates Liquid Glass on the SDK a binary was LINKED
#    against (LC_BUILD_VERSION `sdk`), which is a different field from the deployment
#    target (`minos`). SwiftPM's current default build system writes `sdk` = the
#    deployment target, which would silently drop every macOS 26 user into the old
#    look. `-platform_version` pins both fields explicitly.
#
#    It goes through `-Xclang-linker` in clang's own `-Wl,` syntax, not as bare
#    `-Xlinker -platform_version`. The Swift Build engine in the Xcode 26 toolchain
#    hands linker arguments to the clang driver with the `-Xlinker` prefixes stripped,
#    so clang saw `-platform_version` as one of its own flags and failed the 3.5.3
#    release build with "unknown argument". Written this way clang recognises the
#    flag and forwards it to ld under either build system.
BUILD_FLAGS=(
    -c release
    --arch arm64 --arch x86_64
    -Xswiftc -Xclang-linker
    -Xswiftc "-Wl,-platform_version,macos,$MIN_OS,$SDK_VERSION"
)

# Derived, never hardcoded: the products path moved between SwiftPM build systems
# (.build/arm64-apple-macosx/release -> .build/out/Products/Release). The same flags
# must be passed here as to the build itself or the path comes back wrong.
BUILD_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
BINARY="$BUILD_DIR/Swarm"
# Two SwiftPM resource bundles after the SwarmCore split:
#   - App bundle: AppIcon.icns (loaded via Bundle.module in the app target)
#   - Core bundle: local place indexes and offline map vectors
APP_RESOURCE_BUNDLE="$BUILD_DIR/Swarm_Swarm.bundle"
CORE_RESOURCE_BUNDLE="$BUILD_DIR/Swarm_SwarmCore.bundle"
ICON_SRC="$PROJECT_DIR/Swarm/App/Resources/AppIcon.icns"
DMG_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DMG_DIR/$APP_NAME.app"

echo "=== Building universal release binary (arm64 + x86_64) ==="
cd "$PROJECT_DIR"
./Scripts/run-tests.sh
swift build "${BUILD_FLAGS[@]}"

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
    <string>${MIN_OS}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.lifestyle</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <!-- Without these, macOS denies access to files in these locations outright
         instead of asking. An archive holds its photos and attachments in folders
         beside the .ged, and reading them needs a grant the file picker's
         single-item permission does not cover. -->
    <key>NSDesktopFolderUsageDescription</key>
    <string>Swarm needs access to open family tree archives stored on your Desktop, including their photos and attachments.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Swarm needs access to open family tree archives stored in your Documents folder, including their photos and attachments.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Swarm needs access to open family tree archives stored in your Downloads folder, including their photos and attachments.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>Swarm needs access to open family tree archives stored on external drives, including their photos and attachments.</string>
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
# Assertions, not echoes: both of these have already been wrong once, and neither
# failure is visible until a user on the wrong machine opens the app.
archs="$(lipo -archs "$APP_BUNDLE/Contents/MacOS/Swarm" | tr ' ' '\n' | sort | tr '\n' ' ')"
if [ "$archs" != "arm64 x86_64 " ]; then
    echo "Expected a universal arm64+x86_64 binary, got: $archs" >&2
    exit 1
fi

# Built against an SDK older than 26 means no Liquid Glass for anyone, on any OS, and
# nothing else in the pipeline would notice.
linked_sdk="$(otool -l "$APP_BUNDLE/Contents/MacOS/Swarm" \
    | awk '/LC_BUILD_VERSION/{f=1} f&&/^ *sdk/{print $2; exit}')"
if [ "$(printf '%s\n26.0\n' "$linked_sdk" | sort -V | head -1)" != "26.0" ]; then
    echo "Linked against SDK $linked_sdk; macOS 26 needs an SDK >= 26.0 for Liquid Glass." >&2
    exit 1
fi

echo "Architecture: $archs"
echo "Deployment target: $MIN_OS, linked SDK: $linked_sdk"
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
# Record the bare filename, not the build path, so `shasum -a 256 -c` works
# where the file is downloaded rather than only where it was built.
(cd "$DMG_DIR" && shasum -a 256 "$DMG_NAME" | tee "$DMG_NAME.sha256")

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
