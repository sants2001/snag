#!/bin/bash
#
# Build and install Snag.
#
#   git clone https://github.com/sants2001/snag && cd snag && ./install.sh
#
# Builds from source on purpose. Snag has no Apple Developer ID, so a downloaded binary would be
# quarantined and refused by Gatekeeper with a message that reads like file corruption. Building
# locally sidesteps that: the app is ad-hoc signed by the machine that will run it. It also means
# nobody has to trust a stranger's binary to run something that asks for Full Disk Access.
#
set -euo pipefail

cd "$(dirname "$0")"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[31mError: %s\033[0m\n' "$1" >&2; exit 1; }

step "Checking prerequisites"

[[ "$(uname -s)" == "Darwin" ]] || fail "Snag is macOS only."

# Needs the full Xcode, not just Command Line Tools: the project builds a SwiftUI app target.
if ! /usr/bin/xcodebuild -version >/dev/null 2>&1; then
	fail "xcodebuild is not usable. Install Xcode from the App Store, then run:
  sudo xcode-select -s /Applications/Xcode.app"
fi

XCODE_MAJOR=$(/usr/bin/xcodebuild -version 2>/dev/null | /usr/bin/awk 'NR==1 {split($2, v, "."); print v[1]}')
if [[ -n "$XCODE_MAJOR" && "$XCODE_MAJOR" -lt 26 ]]; then
	fail "Xcode $XCODE_MAJOR found, but Snag needs 26 or newer."
fi
echo "  $(/usr/bin/xcodebuild -version | /usr/bin/head -1)"

step "Building (a few minutes on first run)"
/usr/bin/xcodebuild \
	-project Snag.xcodeproj \
	-scheme Snag \
	-configuration Release \
	-destination 'platform=macOS' \
	build 2>&1 | /usr/bin/grep -E "error:|warning: .*deprecated|BUILD" || true

APP=$(/bin/ls -td "$HOME"/Library/Developer/Xcode/DerivedData/Snag-*/Build/Products/Release/Snag.app 2>/dev/null | /usr/bin/head -1)
[[ -d "$APP" ]] || fail "Build did not produce Snag.app. Scroll up for the compiler error."

step "Signing and installing"
./sign-local.sh --install

[[ -d /Applications/Snag.app ]] || fail "Install failed; /Applications/Snag.app is missing."

step "Done"
cat <<'EOS'

Snag is installed at /Applications/Snag.app and starting now.

  1. Grant Full Disk Access
     System Settings > Privacy & Security > Full Disk Access > + > /Applications/Snag.app
     Without it, only part of your Home folder is indexed.

  2. Press Right Command + /  to summon it
     There is no Dock icon and no menu bar icon, so the hotkey is the only way in.
     If another app owns that combination, rebind it on the first-run screen.

  3. First index takes a few minutes and uses noticeable CPU. After that it is idle.

Snag indexes file NAMES and PATHS only, never contents. Nothing leaves your machine.
Details, with commands to verify each claim: SECURITY.md

EOS

/usr/bin/open -a /Applications/Snag.app
