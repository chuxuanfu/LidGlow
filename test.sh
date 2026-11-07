#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cc -std=c11 -Wall -Wextra -Werror Signal.c test_signal.c -lm -o "$tmp/test_signal"
"$tmp/test_signal"
cc -std=c11 -Wall -Wextra -Werror Lifecycle.c test_lifecycle.c -o "$tmp/test_lifecycle"
"$tmp/test_lifecycle"
if [[ "$(uname -s)" == Darwin ]]; then
  xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-function -mmacosx-version-min=13.0 \
    test_recovery.m Hardware.m Signal.c -framework Foundation -framework IOKit -o "$tmp/test_recovery"
  "$tmp/test_recovery"
  xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-function -mmacosx-version-min=13.0 \
    test_app_lifecycle.m Hardware.m AudioMeter.m Signal.c Lifecycle.c \
    -framework Cocoa -framework IOKit -framework ScreenCaptureKit -framework CoreMedia \
    -framework AudioToolbox -framework QuartzCore -framework CoreAudio -framework ServiceManagement \
    -o "$tmp/test_app_lifecycle"
  "$tmp/test_app_lifecycle"
fi
for script in build.sh install.sh package.sh test.sh test_install.sh; do bash -n "$script"; done
