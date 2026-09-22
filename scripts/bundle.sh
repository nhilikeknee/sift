#!/bin/sh
# Wraps the SPM executable in a .app bundle so it gets a dock icon, a menu bar
# name, and normal activation. Ad-hoc signed, here and in the release both
# (D-8, D-247).
#
# usage: bundle.sh [debug|release] [destination-dir]
#
# With no destination it builds into ~/Applications, which is what makes it
# openable from Launchpad and Spotlight (D-56). There is exactly one bundle:
# build/Sift.app is a symlink to it, so `make run` and
# `open -a build/Sift.app <folder>` keep working and can never be a stale
# second copy. Not `--args <folder>`: since D-324 the app is sandboxed, and a
# path handed to `main` is a string it can read and a folder it cannot open.
#
# `scripts/dmg.sh` passes a staging directory instead, so the release is built
# by this script rather than by a second copy of it that drifts the first time
# the bundle gains a file (D-247). A staged build is the bundle and nothing
# else: it does not touch build/Sift.app and it does not tell LaunchServices
# about a bundle that is about to be thrown away.
set -eu
cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"
DEFAULT_DIR="$HOME/Applications"
INSTALL_DIR="${2:-$DEFAULT_DIR}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Sift"

APP="$INSTALL_DIR/Sift.app"
LINK="build/Sift.app"

mkdir -p "$INSTALL_DIR" build
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Sift"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Rebuild the icon from geometry each time, so AppIcon.svg stays the source.
swift scripts/make-icon.swift >/dev/null
iconutil -c icns build/Sift.iconset -o Resources/AppIcon.icns
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# `--options runtime` is the one hardening an ad-hoc signature can carry.
# Without it any process running as this user can put a dylib inside Sift with
# DYLD_INSERT_LIBRARIES and read the reader's photographs under Sift's own TCC
# grants for Desktop, Documents, Downloads and removable volumes (D-260). It
# costs nothing here: the app embeds no libraries and links only system
# frameworks, and the build is no more notarized than it was (D-267).
#
# stdout is quiet, stderr is not. A codesign that fails silently is how a
# hardening flag goes missing without anybody hearing about it.
#
# The entitlements are what put the app in the sandbox (D-324), so this line
# is the whole of the permission model: drop `--entitlements` and the app
# silently goes back to reading the account's whole home directory with every
# bookmark it holds still resolving. `--verbose` on the check below is how
# that would be heard.
codesign --force --sign - --options runtime \
    --entitlements Resources/Sift.entitlements "$APP" >/dev/null

# Read the sandbox back off the signed bundle rather than trusting the line
# above. A typo in the plist is accepted by codesign and produces an app that
# launches, reads everything, and looks exactly like a working one.
# The backslashes are not optional: plutil reads a dot as a step into a
# nested dictionary, so the unescaped key asks for `security` inside `apple`
# inside `com` and fails on an app that is correctly sandboxed. Caught by this
# check failing the first build after it was written, which is the argument
# for writing it.
codesign -d --entitlements - --xml "$APP" 2>/dev/null \
    | plutil -extract 'com\.apple\.security\.app-sandbox' raw - >/dev/null \
    || { echo "bundle.sh: the signed app is not sandboxed" >&2; exit 1; }

if [ "$INSTALL_DIR" = "$DEFAULT_DIR" ]; then
    # Point the old path at the new one. A directory left behind by a build
    # from before D-56 is removed rather than linked over.
    rm -rf "$LINK"
    ln -s "$APP" "$LINK"

    # Tell LaunchServices about it now, rather than waiting for it to notice.
    # This is also what refreshes the icon after the geometry changes.
    LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    [ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$APP" || true
fi

echo "$APP"
