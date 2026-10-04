#!/bin/bash
# Build the executable and wrap it into MacTaskbar.app.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
APP_NAME="MacTaskbar"
BUNDLE_ID="com.user.mactaskbar"
APP_DIR="build/${APP_NAME}.app"

swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/${APP_NAME}"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "executable not found at $BIN_PATH" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/${APP_NAME}"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>Mac Taskbar</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>MacTaskbar needs Accessibility access to focus and raise windows when you click their tiles.</string>
</dict>
</plist>
PLIST

# Sign with a real identity so TCC (Accessibility, Screen Recording, …) keys
# the grant on a stable designated requirement instead of an ad-hoc cdhash
# that changes every rebuild. Override with SIGN_IDENTITY=... if needed.
SIGN_IDENTITY="${SIGN_IDENTITY:-01988AC4C43FEB3064FAFC9F54F3875F12B778B1}"
codesign --force --deep --options runtime \
    --identifier "$BUNDLE_ID" \
    --sign "$SIGN_IDENTITY" \
    "$APP_DIR"
codesign -dv --verbose=2 "$APP_DIR" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier)=' || true

echo "Built: $APP_DIR"
echo "Run:   open $APP_DIR"
