#!/bin/sh
# Builds Sightline.app into macos/build.
# Usage: scripts/build-app.sh [--install | --zip]
#   ARCHS="arm64 x86_64"  universal build (needs Xcode); default: this Mac's architecture
#   VERSION=1.2.0         app version (default 0.0.0-dev)
#   SIGN_ID="name"        code-signing identity; default "Sightline Local Signing" if present, else ad-hoc
set -eu
cd "$(dirname "$0")/.."

ARCH_FLAGS=""
for a in ${ARCHS:-$(uname -m)}; do ARCH_FLAGS="$ARCH_FLAGS --arch $a"; done
# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS
# shellcheck disable=SC2086
BIN="$(swift build -c release $ARCH_FLAGS --show-bin-path)/Sightline"

APP=build/Sightline.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Sightline"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
plutil -replace CFBundleShortVersionString -string "${VERSION:-0.0.0-dev}" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${BUILD_NUMBER:-1}" "$APP/Contents/Info.plist"

# macOS ties Camera/Accessibility grants to the signature. An ad-hoc signature changes on every
# build, which silently invalidates the Accessibility grant. A stable identity keeps grants across
# rebuilds: set SIGN_ID, or create "Sightline Local Signing" with scripts/make-signing-identity.sh.
if [ -z "${SIGN_ID:-}" ] && security find-identity -p codesigning | grep -q "Sightline Local Signing"; then
    SIGN_ID="Sightline Local Signing"
fi
codesign --force --options runtime --entitlements Resources/Sightline.entitlements \
    --sign "${SIGN_ID:--}" "$APP"

case "${1:-}" in
--install)
    pkill -x Sightline 2>/dev/null || true
    rm -rf /Applications/Sightline.app
    cp -R "$APP" /Applications/
    open /Applications/Sightline.app
    ;;
--zip)
    rm -f build/Sightline-macOS.zip
    ditto -c -k --sequesterRsrc --keepParent "$APP" build/Sightline-macOS.zip
    echo "Packed build/Sightline-macOS.zip"
    ;;
esac
echo "Built $APP"
