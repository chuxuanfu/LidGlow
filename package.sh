#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
[[ "$(uname -s)" == Darwin ]] || { echo 'Package on macOS.' >&2; exit 1; }
./test.sh
if [[ $# == 0 ]]; then
  ./build.sh
  APP="$PWD/build/LidGlow.app"
elif [[ $# == 2 && "$1" == --app ]]; then
  # Package the exact already-tested signed app; never rebuild or re-sign it.
  APP="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
else
  echo 'Usage: ./package.sh [--app /absolute/path/LidGlow.app]' >&2; exit 1
fi
[[ -d "$APP" && ! -L "$APP" ]] || { echo 'App bundle not found.' >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == local.lidglow.lab ]] || { echo 'Wrong app identifier.' >&2; exit 1; }
codesign --verify --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid release version.' >&2; exit 1; }
INSTALLER_VERSION="$(sed -n 's/^VERSION=//p' install.sh)"
[[ "$VERSION" == "$INSTALLER_VERSION" ]] || { echo 'Selected app version does not match install.sh VERSION.' >&2; exit 1; }
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/lidglow-package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p dist
# No personal state, .DS_Store, build logs, recovery files or old backups are included.
ditto --norsrc --noextattr "$APP" "$STAGE/LidGlow.app"
codesign --verify --strict "$STAGE/LidGlow.app"
diff -rq "$APP" "$STAGE/LidGlow.app"
cp install.sh "$STAGE/install.sh"
cat > "$STAGE/Install LidGlow.command" <<'INSTALL'
#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
/bin/bash "$HERE/install.sh" --app "$HERE/LidGlow.app"
INSTALL
chmod +x "$STAGE/Install LidGlow.command" "$STAGE/install.sh"
cp QUICKSTART.md "$STAGE/Quick Start.md"
ln -s /Applications "$STAGE/Applications"
ZIP="LidGlow-${VERSION}-macos-arm64.zip"
DMG="LidGlow-${VERSION}-macos-arm64.dmg"
# ditto can replace files atomically via a new temporary output, without retaining old entries.
ditto -c -k --norsrc --noextattr --keepParent "$STAGE/LidGlow.app" "$STAGE/$ZIP"
mv "$STAGE/$ZIP" "dist/$ZIP"
hdiutil create -volname "LidGlow $VERSION" -srcfolder "$STAGE" -format UDZO -ov "dist/$DMG"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "dist/$DMG"
fi
(cd dist; shasum -a 256 "$ZIP" "$DMG" > SHA256SUMS)
hdiutil verify "dist/$DMG"
echo "Created dist/$DMG, dist/$ZIP and dist/SHA256SUMS"
echo 'Ad-hoc is the default. See DISTRIBUTION.md for Developer ID signing and notarization.'
