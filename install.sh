#!/bin/bash
# Installs the published prebuilt app using only tools included with macOS.
set -euo pipefail
VERSION=0.2.1
BASE="https://raw.githubusercontent.com/chuxuanfu/LidGlow/main/dist"
DEST=/Applications
SOURCE_APP=
OPEN_APP=1
TMP=
STAGE=
LOCK=
BACKUP=
TARGET=
COMMITTED=0
fail() { printf 'LidGlow: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'HELP'
Usage: install.sh [--user | --destination DIR] [--app PATH] [--no-open]
  Default: download the published release, verify it, install to /Applications, open.
  --user             Install in ~/Applications instead (no administrator access).
  --destination DIR  Install in this absolute directory.
  --app PATH         Install an already downloaded/built LidGlow.app (offline).
  --no-open          Install without launching or requesting audio permission.
  --help             Show this help.
No sudo, security bypass, permission reset, login-item or system-setting changes.
HELP
}
cleanup() {
  # A signal/error can land between the two renames. Restore on every exit path.
  if [[ "$COMMITTED" == 0 && -n "$BACKUP" && -d "$BACKUP" && ! -e "$TARGET" ]]; then
    if /bin/mv "$BACKUP" "$TARGET"; then
      printf 'Previous app restored: %s\n' "$TARGET" >&2
    else
      printf 'Could not restore automatically. Previous app is safe at: %s\n' "$BACKUP" >&2
    fi
  fi
  [[ -z "$STAGE" || ! -d "$STAGE" ]] || /bin/rm -rf "$STAGE"
  [[ -z "$TMP" || ! -d "$TMP" ]] || /bin/rm -rf "$TMP"
  [[ -z "$LOCK" || ! -d "$LOCK" ]] || /bin/rmdir "$LOCK" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
while (($#)); do
  case "$1" in
    --user) DEST="$HOME/Applications"; shift ;;
    --destination|--app)
      (($# >= 2)) || fail "Missing value for $1"
      if [[ "$1" == --destination ]]; then DEST="$2"; else SOURCE_APP="$2"; fi
      shift 2 ;;
    --no-open) OPEN_APP=0; shift ;;
    --help|-h) usage; exit 0 ;;
    *) fail "Unknown option: $1 (see --help)" ;;
  esac
done
[[ "$(/usr/bin/uname -s)" == Darwin ]] || fail 'macOS is required.'
[[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]] || fail 'This experimental release requires Apple Silicon. Intel Macs are not supported.'
OS_MAJOR="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)"
[[ "$OS_MAJOR" =~ ^[0-9]+$ && "$OS_MAJOR" -ge 13 ]] || fail 'macOS 13 or newer is required.'
[[ "$EUID" -ne 0 ]] || fail 'Run this as your regular user, without sudo.'
[[ "$DEST" == /* && "$DEST" != / ]] || fail '--destination must name an absolute directory, not /.'
/bin/mkdir -p "$DEST" || fail 'Cannot create destination. Try --user.'
DEST="$(cd "$DEST" && /bin/pwd -P)"
[[ -w "$DEST" ]] || fail "Cannot write to $DEST. Try --user or install the DMG with Finder."
TARGET="$DEST/LidGlow.app"
[[ ! -L "$TARGET" ]] || fail 'Refusing to replace a symlink at LidGlow.app.'
[[ ! -e "$TARGET" || -d "$TARGET" ]] || fail 'The destination LidGlow.app is not a directory.'
# mkdir is an atomic, per-destination lock. Never remove someone else's lock.
if /bin/mkdir "$DEST/.lidglow-install.lock" 2>/dev/null; then LOCK="$DEST/.lidglow-install.lock"; else fail "Another installation may be in progress ($DEST/.lidglow-install.lock)."; fi
TMP="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/lidglow-download.XXXXXX")"
if [[ -z "$SOURCE_APP" ]]; then
  printf 'Downloading LidGlow %s (Apple Silicon)…\n' "$VERSION"
  for name in SHA256SUMS "LidGlow-${VERSION}-macos-arm64.zip"; do
    /usr/bin/curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 15 --max-time 180 "$BASE/$name" -o "$TMP/$name"
  done
  ZIP="LidGlow-${VERSION}-macos-arm64.zip"
  HASH="$(/usr/bin/awk -v name="$ZIP" '$2 == name { print $1 }' "$TMP/SHA256SUMS")"
  [[ "$HASH" =~ ^[0-9a-f]{64}$ ]] || fail 'Missing or invalid archive checksum.'
  (cd "$TMP"; printf '%s  %s\n' "$HASH" "$ZIP" | /usr/bin/shasum -a 256 -c -) || fail 'Archive checksum mismatch; nothing installed.'
  # Accept only this app bundle, with no traversal or absolute archive paths.
  /usr/bin/unzip -Z1 "$TMP/$ZIP" > "$TMP/entries"
  /usr/bin/awk 'BEGIN { ok=1; count=0 } { count++; if ($0 !~ /^LidGlow\.app\// || $0 ~ /(^|\/)\.\.(\/|$)/ || $0 ~ /\\/) ok=0 } END { exit !(ok && count) }' "$TMP/entries" || fail 'Unexpected archive layout.'
  /usr/bin/ditto -x -k "$TMP/$ZIP" "$TMP/unpacked"
  SOURCE_APP="$TMP/unpacked/LidGlow.app"
fi
validate_app() {
  local app="$1"
  [[ -d "$app" && ! -L "$app" && -f "$app/Contents/Info.plist" ]] || fail 'The app bundle is missing or invalid.'
  [[ -z "$(/usr/bin/find "$app" -type l -print -quit)" ]] || fail 'Unexpected symlink in app bundle.'
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == local.lidglow.lab ]] || fail 'Unexpected app bundle identifier.'
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$VERSION" ]] || fail 'App version does not match this installer.'
  [[ -x "$app/Contents/MacOS/LidGlow" ]] || fail 'The app executable is missing.'
  /usr/bin/file "$app/Contents/MacOS/LidGlow" | /usr/bin/grep -q 'arm64' || fail 'App executable is not built for Apple Silicon.'
  /usr/bin/codesign --verify --strict "$app" || fail 'App signature verification failed.'
}
validate_app "$SOURCE_APP"
# Reinstalling the same validated bundle must not replace/re-sign it or churn TCC.
if [[ -d "$TARGET" ]] && /usr/bin/codesign --verify --strict "$TARGET" 2>/dev/null && /usr/bin/diff -rq "$SOURCE_APP" "$TARGET" >/dev/null 2>&1; then
  printf 'This exact LidGlow build is already installed: %s\nNo files or permissions were changed.\n' "$TARGET"
  if [[ "$OPEN_APP" == 1 ]]; then /usr/bin/open "$TARGET"; fi
  exit 0
fi
if [[ -d "$TARGET" ]]; then
  OLD_HASH="$(/usr/bin/codesign -dv --verbose=4 "$TARGET" 2>&1 | /usr/bin/awk -F= '/^CDHash=/ {print $2}' || true)"
  NEW_HASH="$(/usr/bin/codesign -dv --verbose=4 "$SOURCE_APP" 2>&1 | /usr/bin/awk -F= '/^CDHash=/ {print $2}' || true)"
  if [[ "$OLD_HASH" != "$NEW_HASH" ]]; then
    printf '%s\n' \
      'This update changes the app code signature.' \
      'With ad-hoc builds, an enabled recording-permission switch may still refer to the old signature.' \
      'After installation, quit/reopen the installed app and follow native macOS permission prompts.' \
      'If permission remains stale, review QUICKSTART.md; renew only LidGlow through System Settings.' \
      'This installer never grants or resets privacy permissions.'
  fi
fi
# Check before replacing, never force-quit a lighting controller with pending recovery.
set +e
/usr/bin/pgrep -x LidGlow >/dev/null
RUNNING=$?
set -e
[[ "$RUNNING" -le 1 ]] || fail 'Cannot check whether LidGlow is running. Nothing installed.'
[[ "$RUNNING" == 1 ]] || fail 'Choose Restore & Quit in LidGlow, then run this installer again.'
STAGE="$(/usr/bin/mktemp -d "$DEST/.lidglow-stage.XXXXXX")"
/usr/bin/ditto "$SOURCE_APP" "$STAGE/LidGlow.app"
validate_app "$STAGE/LidGlow.app"
# Keep the complete previous bundle, and roll it back if the final rename fails.
if [[ -e "$TARGET" ]]; then
  BACKUP="$DEST/.LidGlow-backup-$(/bin/date -u +%Y%m%dT%H%M%SZ)-$$"
  /bin/mv "$TARGET" "$BACKUP"
fi
if ! /bin/mv "$STAGE/LidGlow.app" "$TARGET"; then
  fail 'Installation failed; attempting to restore the previous app when present.'
fi
COMMITTED=1
printf '\nInstalled: %s\n' "$TARGET"
[[ -z "$BACKUP" ]] || printf 'Previous app retained at: %s\n' "$BACKUP"
printf '%s\n' \
  'Check release provenance: ad-hoc signatures are not Developer ID signing or Apple notarization.' \
  'Only compatible logo-backlight hardware can light up; installation does not add hardware.' \
  'Music/Auto asks for Screen & System Audio Recording permission in macOS.' \
  'No microphone, Accessibility or Full Disk Access permission is needed.' \
  'If macOS blocks opening, review Privacy & Security and use the supported Open Anyway flow only if you trust this app.'
if [[ "$OPEN_APP" == 1 ]]; then
  /usr/bin/open "$TARGET" || printf 'Installed, but could not open. Open %s in Finder.\n' "$TARGET" >&2
fi
