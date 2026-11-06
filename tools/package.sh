#!/bin/bash
# Builds MythicScoreboard-<version>.zip (version from the TOC) in dist/.
cd "$(dirname "$0")/.."
ver=$(grep -m1 "^## Version:" MythicScoreboard/MythicScoreboard.toc | sed 's/## Version: *//' | tr -d '\r')
mkdir -p dist
rm -f "dist/MythicScoreboard-$ver.zip"
zip -qr "dist/MythicScoreboard-$ver.zip" MythicScoreboard -x '*/.*'
echo "dist/MythicScoreboard-$ver.zip"
