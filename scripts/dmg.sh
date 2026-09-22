#!/bin/sh
# Builds the disk image a release is made of: the file the README's download
# button points at, so that installing Sift is a download and a drag rather
# than a clone and a build (D-247).
#
# usage: dmg.sh [version]
#
# The version is the release tag with its leading v removed, and it is stamped
# into the staged bundle so the About box and the download's filename cannot
# disagree. With no argument it takes whatever Resources/Info.plist says, which
# is what a local `make dmg` wants and is never what CI passes.
#
# It is ad-hoc signed, which is what bundle.sh already does and all this project
# will ever do: notarization is $99 a year. So the image arrives quarantined and
# the reader clears the first open by hand. The README says that above the
# button rather than below it (D-247).
#
# The bundle itself is bundle.sh's, built into a staging directory rather than
# into ~/Applications. Repeating the copy-plist-icon-sign steps here would put
# two definitions of what a Sift.app contains in one repository, and the second
# one goes stale the first time the bundle gains a file.
set -eu
cd "$(dirname "$0")/.."

PLIST=Resources/Info.plist
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")}"
STAGE=build/dmg-stage
DMG="build/Sift-$VERSION.dmg"

rm -rf "$STAGE"
mkdir -p "$STAGE"
scripts/bundle.sh release "$STAGE" >/dev/null
APP="$STAGE/Sift.app"

# Stamp the release version, then sign. This order is the whole reason signing
# happens twice: editing Info.plist after codesign breaks the seal, and a
# broken signature is a launch failure rather than the ordinary Gatekeeper
# refusal the README walks the reader through.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
# `--options runtime` for the reason bundle.sh gives, and it matters more here:
# this is the copy that reaches somebody who did not build it (D-267).
codesign --force --sign - --options runtime "$APP"

# The Applications symlink is what makes the window a drag target. Without it
# the reader is looking at an app they are expected to run from a disk image,
# which works once and then puzzles them when the image is ejected.
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -quiet -volname "Sift $VERSION" -srcfolder "$STAGE" \
    -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"

# There is no notarization, so this checksum is the only thing a reader can
# check the download against. The release notes carry it.
echo "$DMG"
shasum -a 256 "$DMG"
