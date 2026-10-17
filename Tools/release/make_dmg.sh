#!/bin/bash
# Packs LaneKeep.app from build_app.sh into the .dmg to hand out: the app, a shortcut to Applications,
# "設定を開く" (opens the screen with "Open Anyway"), はじめに読む.txt / Read Me First.txt, and the
# window picture with the first-launch steps (dmg/background.html).
#
#   bash Tools/release/build_app.sh
#   bash Tools/release/make_dmg.sh   # -> build/dist/LaneKeep_<version>_universal.dmg and .sha256
#
# LaneKeep is not notarized (that needs the paid Apple Developer Program), so on another Mac the first
# launch needs macOS's "Open Anyway"; the window picture and the readme files show how. The window is
# written by dmgbuild, without scripting Finder. dmgbuild is pinned to 1.6.7: 1.6.5 and older store the
# background by the path it had when made, and macOS 26's Finder then shows no picture.
# The app's signature is checked before and after (inside the .dmg): with a broken signature macOS
# calls the app damaged and offers no way to open it.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORK="${LANEKEEP_BUILD_DIR:-$HOME/Library/Caches/LaneKeep-build}"
APP="$WORK/out/LaneKeep.app"
OUT="$ROOT/build/dist"
DMGBUILD="$WORK/tools/dmgbuild/bin/dmgbuild"

[ -d "$APP" ] || { echo "Build the app first: bash Tools/release/build_app.sh"; exit 1; }
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
NAME="LaneKeep_${VERSION}_universal.dmg"
if [ ! -x "$DMGBUILD" ]; then
  python3 -m venv "$WORK/tools/dmgbuild"
  "$WORK/tools/dmgbuild/bin/pip" install --quiet --disable-pip-version-check dmgbuild==1.6.7 ds_store==1.3.1 mac_alias==2.2.2
fi
codesign --verify --deep --strict "$APP"

mkdir -p "$OUT"
rm -f "$OUT/$NAME" "$OUT/$NAME.sha256"
"$DMGBUILD" -s "$HERE/dmg/dmgbuild_settings.py" -D app="$APP" -D dir="$HERE/dmg" "LaneKeep $VERSION" "$OUT/$NAME" >/dev/null
(cd "$OUT" && shasum -a 256 "$NAME" >"$NAME.sha256")

# Open the .dmg read-only (not shown in Finder) and check what is in it and the app's signature.
MNT="$(mktemp -d)"
hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$OUT/$NAME" >/dev/null
fail=""
for f in LaneKeep.app はじめに読む.txt "Read Me First.txt" .background.tiff .DS_Store; do
  [ -e "$MNT/$f" ] || fail="$fail no $f."
done
[ "$(readlink "$MNT/アプリケーション" || true)" = /Applications ] || fail="$fail no shortcut to Applications."
[ "$(readlink "$MNT/設定を開く" || true)" = /System/Library/PreferencePanes/Security.prefPane ] || fail="$fail no 設定を開く."
codesign --verify --deep --strict "$MNT/LaneKeep.app" || fail="$fail the signature of LaneKeep.app is broken."
hdiutil detach "$MNT" >/dev/null
rmdir "$MNT" 2>/dev/null || true
[ -z "$fail" ] || { echo "The .dmg is not right:$fail"; exit 1; }

echo "The .dmg has the app, the shortcuts, the readme files and the window picture; the app's signature is intact"
echo "$OUT/$NAME ($(du -h "$OUT/$NAME" | cut -f1))"
cat "$OUT/$NAME.sha256"
