#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != Darwin ]]; then echo 'Build on macOS 13+ with Xcode Command Line Tools.' >&2; exit 1; fi
xcrun --find clang >/dev/null
# Stage first, so a failed build never damages the previous output.
mkdir -p build
STAGE="$(mktemp -d "$PWD/build/.compile.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/LidGlow.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
xcrun clang -arch arm64 -mmacosx-version-min=13.0 -fobjc-arc -fblocks -Wall -Wextra \
    main.m Hardware.m AudioMeter.m Signal.c Lifecycle.c \
    -framework Cocoa -framework IOKit -framework ScreenCaptureKit \
    -framework CoreMedia -framework AudioToolbox -framework QuartzCore -framework CoreAudio -framework ServiceManagement \
    -o "$APP/Contents/MacOS/LidGlow"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    # Local ad-hoc signature only, neither Developer ID signing nor notarization.
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
# Only generated build output is replaced; installed apps and user data are untouched.
if [[ -e build/LidGlow.app ]]; then mv build/LidGlow.app "$STAGE/previous.app"; fi
if ! mv "$APP" build/LidGlow.app; then
    [[ ! -e "$STAGE/previous.app" ]] || mv "$STAGE/previous.app" build/LidGlow.app
    exit 1
fi
echo "Built and signature verified (not launched): $PWD/build/LidGlow.app"
echo 'Install: ./install.sh --app "$PWD/build/LidGlow.app"'
