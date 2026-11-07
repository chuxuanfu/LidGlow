#!/bin/bash
# Isolated installer regression tests: no app launch and no /Applications changes.
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/build/LidGlow.app"
[[ -d "$APP" ]] || { echo 'Run ./build.sh first.' >&2; exit 1; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/lidglow-installer-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
./install.sh --help >/dev/null
if ./install.sh --unknown >/dev/null 2>&1; then echo 'Unknown option accepted'; exit 1; fi
if ./install.sh --app >/dev/null 2>&1; then echo 'Missing argument accepted'; exit 1; fi
./install.sh --app "$APP" --destination "$TMP/Applications" --no-open
./install.sh --app "$APP" --destination "$TMP/Applications" --no-open > "$TMP/reinstall.log"
grep -q 'already installed' "$TMP/reinstall.log"
[[ -z "$(find "$TMP/Applications" -maxdepth 1 -name '.LidGlow-backup-*' -type d)" ]]
diff -rq "$APP" "$TMP/Applications/LidGlow.app"
# A valid different build must preserve the existing bundle when upgrading.
ditto "$APP" "$TMP/update.app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName LidGlow Installer Test' "$TMP/update.app/Contents/Info.plist"
codesign --force --sign - "$TMP/update.app"
./install.sh --app "$TMP/update.app" --destination "$TMP/Applications" --no-open > "$TMP/update.log"
grep -q 'changes the app code signature' "$TMP/update.log"
find "$TMP/Applications" -maxdepth 1 -name '.LidGlow-backup-*' -type d | grep -q .
# Put the original fixture back before the corruption checks.
./install.sh --app "$APP" --destination "$TMP/Applications" --no-open
ditto "$APP" "$TMP/broken.app"
printf '\ncorruption-test\n' >> "$TMP/broken.app/Contents/Resources/AppIcon.icns"
if ./install.sh --app "$TMP/broken.app" --destination "$TMP/Applications" --no-open; then echo 'Corrupt app accepted'; exit 1; fi
diff -rq "$APP" "$TMP/Applications/LidGlow.app"
[[ ! -e "$TMP/Applications/.lidglow-install.lock" ]]
ln -s "$APP" "$TMP/Symlink.app"
if ./install.sh --app "$TMP/Symlink.app" --destination "$TMP/Applications" --no-open; then echo 'Symlink accepted'; exit 1; fi
mkdir "$TMP/Applications/.lidglow-install.lock"
if ./install.sh --app "$APP" --destination "$TMP/Applications" --no-open; then echo 'Concurrent lock ignored'; exit 1; fi
[[ -d "$TMP/Applications/.lidglow-install.lock" ]]
rmdir "$TMP/Applications/.lidglow-install.lock"
echo 'PASS: interface, install, identical-build no-op, signature-change warning, upgrade, backup, corrupt/symlink rejection and concurrent lock'
