#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

app="${1:-$PWD/build/Browser Switchboard.app}"
if [[ "$(basename "$app")" != "Browser Switchboard.app" ]]; then
    printf '%s\n' 'Use a bundle named Browser Switchboard.app.' >&2
    exit 2
fi
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
codesign --verify --strict "$app"
architectures=" $(xcrun lipo -archs "$app/Contents/MacOS/BrowserWeiche") "
case "$architectures" in
    " arm64 ") platform="apple-silicon" ;;
    " x86_64 ") platform="intel" ;;
    " arm64 x86_64 "|" x86_64 arm64 ") platform="universal" ;;
    *) printf '%s\n' "Unexpected architectures:$architectures" >&2; exit 2 ;;
esac
if [[ "$architectures" == *" $(uname -m) "* ]]; then
    "$app/Contents/MacOS/BrowserWeiche" --self-test
fi
mkdir -p dist

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    scratch="$(mktemp -d "${TMPDIR:-/tmp}/switchboard-notary.XXXXXX")"
    trap 'rm -rf "$scratch"' EXIT
    ditto -c -k --keepParent "$app" "$scratch/submission.zip"
    xcrun notarytool submit "$scratch/submission.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    archive="Browser-Switchboard-$version-macOS-$platform.zip"
else
    archive="Browser-Switchboard-$version-macOS-$platform-local-test.zip"
fi

ditto -c -k --keepParent "$app" "dist/$archive"
(cd dist && shasum -a 256 "$archive" > "$archive.sha256")
printf '%s\n' "dist/$archive" "dist/$archive.sha256"
