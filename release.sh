#!/bin/bash
#
# Build a signed, notarised, distributable Snag.dmg.
#
#   ./release.sh 1.0.0
#
# Produces a DMG anyone can download and open. This is the only path that avoids Gatekeeper
# refusing the app with a message that reads like file corruption; `install.sh` exists precisely
# because ad-hoc signed builds cannot be distributed.
#
# One-time setup, both of which need your Apple ID and so cannot be scripted:
#
#   1. Create a "Developer ID Application" certificate at
#      https://developer.apple.com/account/resources/certificates/add
#      This is NOT the same as the "Apple Distribution" certificate used for the App Store.
#      It is free with an existing paid account.
#
#   2. Store notarisation credentials, using an app-specific password from appleid.apple.com:
#      xcrun notarytool store-credentials "notarytool" \
#        --apple-id "<your-apple-id>" --team-id "<TEAMID>" --password "<app-specific-password>"
#
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-}"
[[ -n "$VERSION" ]] || { echo "Usage: ./release.sh <version>   e.g. ./release.sh 1.0.0"; exit 1; }

NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool}"
DIST="dist"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[31mError: %s\033[0m\n' "$1" >&2; exit 1; }

step "Checking signing setup"

# The `|| true` matters: with `set -e` and `pipefail`, grep finding nothing kills the script
# right here, so the helpful message below never prints and the user sees silence.
IDENTITY=$( { /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
  | /usr/bin/grep "Developer ID Application" | /usr/bin/head -1 \
  | /usr/bin/sed -E 's/.*"(.*)"/\1/'; } || true)

if [[ -z "$IDENTITY" ]]; then
	fail "No \"Developer ID Application\" certificate found.

An \"Apple Distribution\" certificate is NOT sufficient: that one is for the App Store.
Create a Developer ID Application certificate here, free with your existing account:
  https://developer.apple.com/account/resources/certificates/add"
fi
echo "  $IDENTITY"

/usr/bin/xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || fail "No notarisation credentials stored under profile '$NOTARY_PROFILE'. See the header of this script."
echo "  notary profile: $NOTARY_PROFILE"

TEAM_ID=$(echo "$IDENTITY" | /usr/bin/sed -E 's/.*\(([A-Z0-9]+)\)$/\1/')

step "Building $VERSION"
/usr/bin/xcodebuild \
	-project Snag.xcodeproj \
	-scheme Snag \
	-configuration Release \
	-destination 'platform=macOS' \
	MARKETING_VERSION="$VERSION" \
	CODE_SIGN_STYLE=Manual \
	CODE_SIGN_IDENTITY="$IDENTITY" \
	DEVELOPMENT_TEAM="$TEAM_ID" \
	OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
	build 2>&1 | /usr/bin/grep -E "error:|BUILD" || true

APP=$(/bin/ls -td "$HOME"/Library/Developer/Xcode/DerivedData/Snag-*/Build/Products/Release/Snag.app 2>/dev/null | /usr/bin/head -1)
[[ -d "$APP" ]] || fail "Build produced no Snag.app."

step "Signing"
# Inside-out, and every nested binary needs the hardened runtime too: notarisation rejects a
# bundle where anything is unsigned or missing --options=runtime, and reports it as a generic
# failure rather than naming the file.
/usr/bin/find "$APP/Contents/Frameworks" "$APP/Contents/SharedSupport" \
	-depth \( -name "*.framework" -o -name "*.app" -o -name "*.xpc" -o -name "*.dylib" -o -type f -perm -u+x \) \
	-print0 2>/dev/null | while IFS= read -r -d '' item; do
	if [[ -f "$item" ]] && ! /usr/bin/file -b "$item" | /usr/bin/grep -q "Mach-O"; then continue; fi
	/usr/bin/codesign --force --sign "$IDENTITY" --timestamp --options=runtime "$item" 2>/dev/null || true
done

/usr/bin/codesign --force --sign "$IDENTITY" --timestamp --options=runtime \
	--entitlements Snag/Snag.entitlements "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP" || fail "Signature verification failed."

step "Packaging"
/bin/rm -rf "$DIST"; /bin/mkdir -p "$DIST/stage"
/usr/bin/ditto "$APP" "$DIST/stage/Snag.app"
/bin/ln -s /Applications "$DIST/stage/Applications"
DMG="$DIST/Snag-$VERSION.dmg"
/usr/bin/hdiutil create -volname "Snag" -srcfolder "$DIST/stage" -ov -format UDZO "$DMG" >/dev/null
/bin/rm -rf "$DIST/stage"
echo "  $DMG"

step "Notarising (usually 1-5 minutes)"
/usr/bin/xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait \
	|| fail "Notarisation failed. Run: xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"

step "Stapling"
# Staples the ticket into the DMG so it opens on a machine with no network.
/usr/bin/xcrun stapler staple "$DMG"
/usr/bin/spctl -a -t open --context context:primary-signature -v "$DMG" 2>&1 | /usr/bin/tail -2

step "Done"
cat <<EOS

  $DMG

Verified signed, notarised and stapled. It will open on any Mac without a Gatekeeper warning.

Next:
  gh release create v$VERSION "$DMG" --title "Snag $VERSION" --notes "..."

EOS
