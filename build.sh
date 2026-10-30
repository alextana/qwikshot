#!/bin/zsh
# Builds Snapper.app next to this script, signed ad hoc.
set -euo pipefail
cd "${0:A:h}"

swift build -c release

APP=Snapper.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Snapper "$APP/Contents/MacOS/Snapper"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Snapper</string>
    <key>CFBundleDisplayName</key><string>Snapper</string>
    <key>CFBundleIdentifier</key><string>local.snapper.app</string>
    <key>CFBundleExecutable</key><string>Snapper</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier local.snapper.app "$APP"
echo "Built $PWD/$APP"
