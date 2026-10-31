#!/bin/zsh
# Publishes the version in the VERSION file as a GitHub release, which is what
# every installed copy sees when it checks for updates.
set -euo pipefail
cd "${0:A:h:h}"

REPO=alextana/qwikshot
VERSION=$(<VERSION)
TAG="v$VERSION"

if [[ -n $(git status --porcelain --untracked-files=no) ]]; then
    echo "Commit your changes first: the build number comes from the commit count." >&2
    exit 1
fi
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "$TAG already exists. Raise the number in VERSION." >&2
    exit 1
fi

git push origin main
./build.sh

mkdir -p dist
ZIP="dist/Qwikshot-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent Qwikshot.app "$ZIP"
SIGNATURE=$(.build/artifacts/sparkle/Sparkle/bin/sign_update "$ZIP")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Qwikshot.app/Contents/Info.plist)
URL="https://github.com/$REPO/releases/download/$TAG/Qwikshot-$VERSION.zip"

cat > dist/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Qwikshot</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/$TAG</sparkle:releaseNotesLink>
      <enclosure url="$URL" type="application/octet-stream" $SIGNATURE/>
    </item>
  </channel>
</rss>
EOF

gh release create "$TAG" "$ZIP" dist/appcast.xml --repo "$REPO" --title "Qwikshot $VERSION" --generate-notes \
    --notes "Requires macOS 26 or later on Apple silicon. Qwikshot isn't notarized, so the first time you open it, macOS will block it: go to System Settings > Privacy & Security and choose Open Anyway."
