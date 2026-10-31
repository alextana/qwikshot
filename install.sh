#!/bin/zsh
# Builds Qwikshot, replaces the copy in /Applications, and reopens it.
set -euo pipefail
cd "${0:A:h}"

Scripts/setup-signing.sh
./build.sh

pkill -x Qwikshot || true
rm -rf /Applications/Qwikshot.app
cp -R Qwikshot.app /Applications/
open /Applications/Qwikshot.app
echo "Installed /Applications/Qwikshot.app"
