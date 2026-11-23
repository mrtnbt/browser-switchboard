#!/bin/bash
set -euo pipefail

app="${1:-$PWD/build/Browser Switchboard.app}"
if [[ "$app" != /* ]]; then app="$PWD/$app"; fi
cd "$(dirname "$0")"

cache="$(mktemp -d "${TMPDIR:-/tmp}/browser-switchboard.XXXXXX")"
trap 'rm -rf "$cache"' EXIT
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
plutil -lint Sources/Info.plist Sources/Resources/{en,de}.lproj/InfoPlist.strings \
    Sources/Resources/de.lproj/Localizable.strings
cp Sources/Info.plist "$app/Contents/Info.plist"
cp LICENSE Sources/Resources/BrowserWeiche.icns "$app/Contents/Resources/"
for language in en de; do
    ditto "Sources/Resources/$language.lproj" "$app/Contents/Resources/$language.lproj"
done

compile() {
    xcrun swiftc -module-cache-path "$cache" -swift-version 6 -O \
        -target "$1-apple-macosx13.0" Sources/*.swift -o "$2"
}

executable="$app/Contents/MacOS/BrowserWeiche"
case "${BUILD_ARCH:-$(uname -m)}" in
    universal)
        compile arm64 "$cache/arm64"
        compile x86_64 "$cache/x86_64"
        xcrun lipo -create "$cache/arm64" "$cache/x86_64" -output "$executable"
        ;;
    arm64|x86_64)
        compile "${BUILD_ARCH:-$(uname -m)}" "$executable"
        ;;
    *)
        printf '%s\n' 'BUILD_ARCH must be arm64, x86_64, or universal.' >&2
        exit 2
        ;;
esac
if [[ -n "${DEVELOPER_ID:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --strict "$app"
