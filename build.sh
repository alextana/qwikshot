#!/bin/zsh
# Builds Qwikshot.app next to this script. Signs it with the identity from
# Scripts/setup-signing.sh if there is one, otherwise ad hoc.
set -euo pipefail
cd "${0:A:h}"

swift build -c release

APP=Qwikshot.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/Qwikshot "$APP/Contents/MacOS/Qwikshot"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
ditto .build/release/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"

VERSION=$(<VERSION)
BUILD=$(git rev-list --count HEAD)

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Qwikshot</string>
    <key>CFBundleDisplayName</key><string>Qwikshot</string>
    <key>CFBundleIdentifier</key><string>local.qwikshot.app</string>
    <key>CFBundleExecutable</key><string>Qwikshot</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>SUFeedURL</key><string>https://github.com/alextana/qwikshot/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key><string>43H1awIwjf6hDhaq9YPK9oJONwGJqzKQbmh+SALbAvo=</string>
</dict>
</plist>
PLIST

IDENTITY="Qwikshot Local Signing"
security find-certificate -c "$IDENTITY" >/dev/null 2>&1 || IDENTITY=-

# Signed inside out: each bundle's signature covers what's nested in it.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for ITEM in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
    codesign --force --sign "$IDENTITY" "$SPARKLE/$ITEM"
done
codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$IDENTITY" --identifier local.qwikshot.app "$APP"
echo "Built $PWD/$APP"
