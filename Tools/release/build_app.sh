#!/bin/bash
# Builds LaneKeep.app with the Command Line Tools only (no Xcode), signed for handing out.
# make_dmg.sh then packs it into the .dmg.
#
#   bash Tools/release/make_cert.sh   # once per Mac: the signing certificate
#   bash Tools/release/build_app.sh   # -> ~/Library/Caches/LaneKeep-build/out/LaneKeep.app
#
# With Xcode, `make build` is the regular way. This stands in for it on a Mac without Xcode and
# matches what the Xcode target makes:
# - one binary for Apple silicon and Intel, like Xcode's Release configuration;
# - the colors of Assets.xcassets as code with the same values (support/gen_asset_colors.py), since
#   the asset catalog compiler (actool) ships only with Xcode;
# - KeyboardShortcuts 2.4.0, what Xcode 16 resolves (the Command Line Tools' Swift 6.1 cannot build
#   3.x), patched by support/patch_keyboardshortcuts.py;
# - signed with "LaneKeep Self-Signed", the hardened runtime and Config/LaneKeep.entitlements, so the
#   accessibility permission survives rebuilds;
# - no paths of this Mac left in the binary (-file-prefix-map, strip).
# The work folder is outside the project on purpose: SwiftPM's build folder is large, and the project
# lives in Google Drive.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORK="${LANEKEEP_BUILD_DIR:-$HOME/Library/Caches/LaneKeep-build}"
SRC="$WORK/src"
OUT="$WORK/out"
APP="$OUT/LaneKeep.app"
IDENTITY="${LANEKEEP_SIGN_IDENTITY:-LaneKeep Self-Signed}"
KS_VERSION=2.4.0
KS_COMMIT=1aef85578fdd4f9eaeeb8d53b7b4fc31bf08fe27

setting() { # a build setting from Config/LaneKeep.xcconfig
  sed -n "s/^$1 *= *//p" "$ROOT/Config/LaneKeep.xcconfig" | head -1
}
VERSION="$(setting MARKETING_VERSION)"
BUILD="$(setting CURRENT_PROJECT_VERSION)"
BUNDLE_ID="$(setting PRODUCT_BUNDLE_IDENTIFIER)"
DEPLOYMENT="$(sed -n 's/.*MACOSX_DEPLOYMENT_TARGET = \(.*\);/\1/p' "$ROOT/LaneKeep.xcodeproj/project.pbxproj" | sort -u)"
[ "$(printf '%s\n' "$DEPLOYMENT" | wc -l | tr -d ' ')" = 1 ] || { echo "More than one MACOSX_DEPLOYMENT_TARGET: $DEPLOYMENT"; exit 1; }
security find-identity -p codesigning | grep -q "\"$IDENTITY\"" ||
  { echo "No \"$IDENTITY\" certificate in the keychain: run Tools/release/make_cert.sh first"; exit 1; }

# 1. A copy of the project to build from. SwiftPM's .build stays between runs.
mkdir -p "$SRC" "$OUT"
rsync -a --delete --exclude .DS_Store --exclude /build/ --exclude /.build/ --exclude /Vendor/ \
  --exclude /Package.swift --exclude /Package.resolved "$ROOT/" "$SRC/"

# 2. KeyboardShortcuts, pinned to the commit of its 2.4.0 tag, and patched.
KS_CLONE="$WORK/KeyboardShortcuts-$KS_VERSION"
[ -d "$KS_CLONE" ] || git clone --quiet --depth 1 --branch "$KS_VERSION" https://github.com/sindresorhus/KeyboardShortcuts "$KS_CLONE"
[ "$(git -C "$KS_CLONE" rev-parse HEAD)" = "$KS_COMMIT" ] ||
  { echo "KeyboardShortcuts $KS_VERSION in $KS_CLONE is not commit $KS_COMMIT"; exit 1; }
rm -rf "$SRC/Vendor/KeyboardShortcuts"
mkdir -p "$SRC/Vendor"
rsync -a --exclude .git "$KS_CLONE/" "$SRC/Vendor/KeyboardShortcuts/"
python3 "$HERE/support/patch_keyboardshortcuts.py" "$SRC/Vendor/KeyboardShortcuts" "$HERE/support/KeyboardShortcutsLocalizations.swift"

# 3. The package manifest, and the asset catalog's colors as code.
cp "$HERE/support/Package.swift" "$SRC/Package.swift"
python3 "$HERE/support/gen_asset_colors.py" "$SRC/LaneKeep/Assets.xcassets" "$SRC/LaneKeep/Support/AssetCatalogColor.swift"
sed -i '' -E 's/= Color\("([A-Za-z0-9]+)"\)/= AssetCatalogColor.named("\1")/' "$SRC/LaneKeep/Views/Theme/Theme.swift"
if grep -rn 'Color("' "$SRC/LaneKeep" --include='*.swift' | grep -v AssetCatalogColor; then
  echo "Color(\"…\") lookups left: they would find nothing without the asset catalog"; exit 1
fi

# 4. Both architectures, made into one binary.
for arch in arm64 x86_64; do
  triple="$arch-apple-macosx$DEPLOYMENT"
  echo "Building for ${arch}..."
  # The linker then looks for the clang module caches under the mapped path and warns; the debug
  # information it wanted them for is stripped below anyway.
  swift build --package-path "$SRC" -c release --product LaneKeep --triple "$triple" \
    -Xswiftc -file-prefix-map -Xswiftc "$SRC=/LaneKeep" 2>&1 |
    grep -E "error|warning: |Build of product" | grep -v "ModuleCache/.*\.pcm: No such file" || true
  bin="$(swift build --package-path "$SRC" -c release --product LaneKeep --triple "$triple" --show-bin-path)/LaneKeep"
  [ -x "$bin" ] || { echo "The $arch build failed"; exit 1; }
  cp "$bin" "$OUT/LaneKeep-$arch"
  # SwiftPM adds an rpath into the Command Line Tools (for its test frameworks). LaneKeep loads no
  # library from an rpath, so any absolute one goes.
  otool -l "$OUT/LaneKeep-$arch" | awk '/cmd LC_RPATH/ { getline; getline; print $2 }' | grep '^/' |
    while read -r rpath; do install_name_tool -delete_rpath "$rpath" "$OUT/LaneKeep-$arch" 2>/dev/null; done
done
lipo -create -output "$OUT/LaneKeep" "$OUT/LaneKeep-arm64" "$OUT/LaneKeep-x86_64"
rm "$OUT/LaneKeep-arm64" "$OUT/LaneKeep-x86_64"
strip -S -x "$OUT/LaneKeep" # debug map (object file paths) and local symbols

# 5. The app bundle, laid out like the Xcode target's.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv "$OUT/LaneKeep" "$APP/Contents/MacOS/LaneKeep"
printf 'APPL????' >"$APP/Contents/PkgInfo"
python3 - "$ROOT/Config/Info.plist" "$APP/Contents/Info.plist" "$BUNDLE_ID" "$VERSION" "$BUILD" "$DEPLOYMENT" <<'PY'
import plistlib, re, sys
source, target, bundle_id, version, build, deployment = sys.argv[1:7]
settings = {
    "EXECUTABLE_NAME": "LaneKeep",
    "PRODUCT_NAME": "LaneKeep",
    "PRODUCT_BUNDLE_PACKAGE_TYPE": "APPL",
    "PRODUCT_BUNDLE_IDENTIFIER": bundle_id,
    "MARKETING_VERSION": version,
    "CURRENT_PROJECT_VERSION": build,
    "MACOSX_DEPLOYMENT_TARGET": deployment,
}
def fill(match):
    if match.group(1) not in settings:
        raise SystemExit(f"Info.plist uses an unknown build setting: {match.group(1)}")
    return settings[match.group(1)]
info = plistlib.loads(re.sub(r"\$\((\w+)\)", fill, open(source, encoding="utf-8").read()).encode())
info["CFBundleIconFile"] = "AppIcon"  # what actool adds for the AppIcon set
with open(target, "wb") as f:
    plistlib.dump(info, f)
PY
ICONSET="$OUT/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir "$ICONSET"
cp "$SRC"/LaneKeep/Assets.xcassets/AppIcon.appiconset/icon_*.png "$ICONSET/"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
rm -rf "$ICONSET"
KS_BUNDLE="$APP/Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle"
mkdir -p "$KS_BUNDLE/Contents/Resources"
cp -R "$SRC"/Vendor/KeyboardShortcuts/Sources/KeyboardShortcuts/Localization/*.lproj "$KS_BUNDLE/Contents/Resources/"
plutil -create xml1 "$KS_BUNDLE/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string "com.sindresorhus.KeyboardShortcuts.resources" "$KS_BUNDLE/Contents/Info.plist"
plutil -insert CFBundleDevelopmentRegion -string en "$KS_BUNDLE/Contents/Info.plist"
plutil -insert CFBundlePackageType -string BNDL "$KS_BUNDLE/Contents/Info.plist"
plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$KS_BUNDLE/Contents/Info.plist"
{
  echo "LaneKeep includes KeyboardShortcuts $KS_VERSION (https://github.com/sindresorhus/KeyboardShortcuts):"
  echo
  cat "$KS_CLONE/license"
} >"$APP/Contents/Resources/ThirdPartyNotices.txt"

# 6. Sign, then check what was made.
codesign --force --sign "$IDENTITY" --options runtime --timestamp=none \
  --entitlements "$ROOT/Config/LaneKeep.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
REQUIREMENT="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"
case "$REQUIREMENT" in
  *"identifier \"$BUNDLE_ID\""*"certificate leaf"*) ;;
  *) echo "Unexpected designated requirement: $REQUIREMENT"; exit 1 ;;
esac
[ "$(lipo -archs "$APP/Contents/MacOS/LaneKeep")" = "x86_64 arm64" ] || { echo "Not a universal binary"; exit 1; }
if LC_ALL=C grep -a -q -F -e "$HOME" -e "$WORK" "$APP/Contents/MacOS/LaneKeep"; then
  echo "Paths of this Mac are left in the binary"; exit 1
fi
plutil -lint -s "$APP/Contents/Info.plist" "$KS_BUNDLE/Contents/Info.plist"

echo "$APP"
echo "LaneKeep $VERSION ($BUILD) for $(lipo -archs "$APP/Contents/MacOS/LaneKeep"), signed by \"$IDENTITY\""
echo "Designated requirement: $REQUIREMENT"
