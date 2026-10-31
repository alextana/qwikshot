#!/bin/zsh
# Builds Qwikshot.app next to this script, signed ad hoc.
set -euo pipefail
cd "${0:A:h}"

swift build -c release

APP=Qwikshot.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Qwikshot "$APP/Contents/MacOS/Qwikshot"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Qwikshot</string>
    <key>CFBundleDisplayName</key><string>Qwikshot</string>
    <key>CFBundleIdentifier</key><string>local.qwikshot.app</string>
    <key>CFBundleExecutable</key><string>Qwikshot</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier local.qwikshot.app "$APP"
echo "Built $PWD/$APP"
