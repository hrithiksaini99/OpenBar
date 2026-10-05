#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
case "$CONFIGURATION" in debug|release) ;; *) echo "usage: $0 [debug|release]" >&2; exit 2 ;; esac
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/toolchain.sh"
swift build --configuration "$CONFIGURATION" --product OpenBar
BUILD_BINARY="$(swift build --configuration "$CONFIGURATION" --show-bin-path)/OpenBar"
APP_BUNDLE="$ROOT_DIR/dist/OpenBar.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BUILD_BINARY" "$APP_BUNDLE/Contents/MacOS/OpenBar"
chmod +x "$APP_BUNDLE/Contents/MacOS/OpenBar"
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>internal.openbar.app</string>
    <key>CFBundleName</key><string>OpenBar</string>
    <key>CFBundleDisplayName</key><string>OpenBar</string>
    <key>CFBundleExecutable</key><string>OpenBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>LSMultipleInstancesProhibited</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>OpenBar captures the current pixels of hidden menu bar items so the tray panel shows their exact current state.</string>
</dict>
</plist>
PLIST
/usr/bin/plutil -lint "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$APP_BUNDLE"
echo "Built $APP_BUNDLE"
