#!/bin/bash
# Draws the .dmg window picture (background.png 1920×1200 and background@2x.png 3840×2400) from
# background.html. The pictures are kept with the sources; run this only after changing the page.
#
#   bash Tools/release/dmg/render_background.sh
#
# Uses Google Chrome without a window, with a throwaway profile each time and without touching the
# keychain (--use-mock-keychain). Chrome sometimes keeps running after writing the picture, so it is
# stopped once the file is there.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[ -x "$CHROME" ] || { echo "Google Chrome not found (pass its path in CHROME)"; exit 1; }

render() { # scale output-file
  local out="$2" profile pid
  profile="$(mktemp -d)"
  rm -f "$out"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --no-first-run --no-default-browser-check \
    --use-mock-keychain --user-data-dir="$profile" --window-size=1920,1200 --force-device-scale-factor="$1" \
    --screenshot="$out" "file://$DIR/background.html" >/dev/null 2>&1 &
  pid=$!
  for _ in $(seq 120); do
    [ -s "$out" ] && { sleep 1; break; }
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.25
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  rm -rf "$profile"
  [ -s "$out" ] || { echo "Could not draw $out"; exit 1; }
}

render 1 "$DIR/background.png"
render 2 "$DIR/background@2x.png"
sips -g pixelWidth -g pixelHeight "$DIR/background.png" "$DIR/background@2x.png" | grep -v '^/' | paste - - | sed 's/^ *//'
