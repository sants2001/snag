#!/bin/bash
# Ad-hoc re-sign a built Snag.app so it runs on this Mac.
#
# Upstream Cling signs with a Developer ID, which gives every nested binary the same Team ID.
# This fork signs ad-hoc (no Apple Developer account needed), but Xcode leaves some embedded
# binaries carrying their vendor's original signature -- notably Sparkle.framework, which ships
# pre-signed by the Sparkle project. dyld then refuses to load it: "mapping process and mapped
# file (non-platform) have different Team IDs". Re-signing everything ad-hoc, inside-out, gives
# the whole bundle a single (absent) Team ID.
#
# Usage: ./sign-local.sh [/path/to/Snag.app]
set -euo pipefail

APP="${1:-}"
if [[ -z "$APP" ]]; then
	APP=$(ls -td "$HOME"/Library/Developer/Xcode/DerivedData/Cling-*/Build/Products/Release/Snag.app 2>/dev/null | head -1)
fi
[[ -d "$APP" ]] || { echo "No Snag.app found. Build Release first, or pass the path."; exit 1; }
echo "Signing $APP"

# Inside-out: nested code must be sealed before the enclosing bundle is, so `-depth` matters.
# Some of these directories legitimately don't exist, and `find` exits non-zero when one is
# missing; without the `|| true` that failure combines with `pipefail` and aborts the script
# before the app itself ever gets signed.
SEARCH_DIRS=()
for d in Frameworks XPCServices SharedSupport; do
	[[ -d "$APP/Contents/$d" ]] && SEARCH_DIRS+=("$APP/Contents/$d")
done

{ find "${SEARCH_DIRS[@]}" -depth \
	\( -name "*.framework" -o -name "*.app" -o -name "*.xpc" -o -name "*.dylib" -o -type f -perm -u+x \) \
	-print0 2>/dev/null || true; } | while IFS= read -r -d '' item; do
	# Skip executable non-Mach-O files (the bundled .zsh scripts and .fsignore helpers).
	if [[ -f "$item" ]] && ! file -b "$item" | grep -q "Mach-O"; then continue; fi
	codesign --force --sign - --timestamp=none "$item" 2>/dev/null || true
done

codesign --force --sign - --timestamp=none \
	--entitlements "$(dirname "$0")/Cling/Cling.entitlements" "$APP"

codesign --verify --deep --strict "$APP" && echo "Signature OK"
