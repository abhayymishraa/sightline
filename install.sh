#!/usr/bin/env bash
# Sightline installer for macOS.
#
#   Install or update:  curl -fsSL https://raw.githubusercontent.com/abhayymishraa/sightline/main/install.sh | bash
#   Uninstall:          curl -fsSL https://raw.githubusercontent.com/abhayymishraa/sightline/main/install.sh | bash -s -- --uninstall
#
# It downloads the latest release from GitHub and puts Sightline.app in /Applications
# (or ~/Applications when /Applications is not writable). Nothing else is installed.
set -euo pipefail

REPO="abhayymishraa/sightline"
APP_NAME="Sightline.app"
BUNDLE_ID="dev.sightline.Sightline"
URL="https://github.com/$REPO/releases/latest/download/Sightline-macOS.zip"

bold=$'\033[1m'; blue=$'\033[34m'; red=$'\033[31m'; dim=$'\033[2m'; reset=$'\033[0m'
step() { printf '%s==>%s %s\n' "$blue$bold" "$reset" "$1"; }
fail() { printf '%sError:%s %s\n' "$red$bold" "$reset" "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "This installer is for macOS. On Windows, see the README."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 14 ] || fail "Sightline needs macOS 14 Sonoma or later (this Mac runs $(sw_vers -productVersion))."

if [ -w /Applications ]; then DEST="/Applications"; else DEST="$HOME/Applications"; mkdir -p "$DEST"; fi

quit_running() {
    if pgrep -x Sightline >/dev/null 2>&1; then
        osascript -e 'tell application id "'"$BUNDLE_ID"'" to quit' >/dev/null 2>&1 || true
        sleep 1
        pkill -x Sightline 2>/dev/null || true
    fi
}

if [ "${1:-}" = "--uninstall" ]; then
    step "Quitting Sightline"
    quit_running
    for dir in /Applications "$HOME/Applications"; do
        [ -d "$dir/$APP_NAME" ] && { step "Removing $dir/$APP_NAME"; rm -rf "$dir/$APP_NAME"; }
    done
    step "Removing preferences and permissions"
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    tccutil reset Camera "$BUNDLE_ID" >/dev/null 2>&1 || true
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    printf '%sSightline is uninstalled.%s\n' "$bold" "$reset"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

step "Downloading the latest Sightline"
curl -fL --progress-bar "$URL" -o "$TMP/Sightline.zip" || fail "Download failed. Check your connection, or get the zip from https://github.com/$REPO/releases"
ditto -x -k "$TMP/Sightline.zip" "$TMP"
[ -d "$TMP/$APP_NAME" ] || fail "The download did not contain $APP_NAME."

step "Installing to $DEST"
quit_running
rm -rf "${DEST:?}/$APP_NAME"
ditto "$TMP/$APP_NAME" "$DEST/$APP_NAME"
# The app is not notarized; clear the download flag so Gatekeeper does not block the first launch.
xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true

step "Opening Sightline"
open "$DEST/$APP_NAME"

cat <<EOF

${bold}Sightline is installed.${reset} Look for its icon in the menu bar.
The Getting Started window asks for Camera and Accessibility access, then sets up your screens.
${dim}Update: run this command again.  Uninstall: add "-s -- --uninstall" after "bash".${reset}
EOF
