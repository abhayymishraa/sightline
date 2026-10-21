#!/bin/sh
# Renders the Remotion icon stills and writes ../macos/Resources/AppIcon.icns with every macOS size.
# 16 and 32 pt (1x) use the simplified art; everything else uses the full art.
set -eu
cd "$(dirname "$0")"
PORT=${PORT:-3123}   # 3000 is often taken by other dev servers

npx remotion still Icon out/icon.png --image-format=png --port="$PORT"
npx remotion still IconSmall out/icon-small.png --image-format=png --port="$PORT"

SET=out/AppIcon.iconset
rm -rf "$SET" && mkdir -p "$SET"
size() { sips -z "$2" "$2" "$1" --out "$SET/$3" >/dev/null; }
size out/icon-small.png 16 icon_16x16.png
size out/icon-small.png 32 icon_16x16@2x.png
size out/icon-small.png 32 icon_32x32.png
size out/icon.png 64 icon_32x32@2x.png
size out/icon.png 128 icon_128x128.png
size out/icon.png 256 icon_128x128@2x.png
size out/icon.png 256 icon_256x256.png
size out/icon.png 512 icon_256x256@2x.png
size out/icon.png 512 icon_512x512.png
cp out/icon.png "$SET/icon_512x512@2x.png"

iconutil -c icns "$SET" -o ../macos/Resources/AppIcon.icns
echo "Wrote macos/Resources/AppIcon.icns"
