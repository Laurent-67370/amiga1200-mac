#!/usr/bin/env bash
# Application Mac : build/Amiga 1200.app et build/amiga1200-mac.dmg (après native/build-core.sh)
#
#   scripts/build-app.sh [numéro de compilation]
#
# L'application est un seul exécutable (Swift + cœur Amiberry), signée sans certificat (signature « ad hoc ») avec
# le droit au JIT. Sans compte développeur Apple, macOS demande une confirmation au premier lancement.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD=${1:-${GITHUB_RUN_NUMBER:-1}}
OUT="$ROOT/build"
APP="$OUT/Amiga 1200.app"
CORE="$ROOT/native/out"
[ -f "$CORE/libcore.a" ] || { echo "native/out/libcore.a absent : lancez native/build-core.sh" >&2; exit 1; }
rm -rf "$OUT"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -target arm64-apple-macos13.0 -module-name Amiga1200 \
  -import-objc-header "$ROOT/native/bridge.h" "$ROOT"/app/Sources/*.swift \
  -Xlinker -force_load -Xlinker "$CORE/libcore.a" \
  -lc++ -lz -liconv -framework CoreFoundation -framework DiskArbitration -framework AudioToolbox \
  -framework AppKit -framework GameController -framework QuartzCore -framework CoreMIDI \
  -o "$APP/Contents/MacOS/Amiga1200"

sed "s/@BUILD@/$BUILD/g" "$ROOT/app/Info.plist" > "$APP/Contents/Info.plist"
cp -R "$CORE/resources/"* "$APP/Contents/Resources/"
# Icône : toutes les tailles depuis l'image de 1024 points
ICONSET="$OUT/AppIcon.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ROOT/app/Resources/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$ROOT/app/Resources/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

codesign --force --deep --sign - --entitlements "$ROOT/app/amiga1200.entitlements" "$APP"
codesign --verify --verbose "$APP"

# Image disque : l'application et un raccourci vers Applications
DMG="$OUT/dmg"; mkdir -p "$DMG"
cp -R "$APP" "$DMG/"
ln -s /Applications "$DMG/Applications"
hdiutil create -volname "Amiga 1200" -srcfolder "$DMG" -ov -format UDZO "$OUT/amiga1200-mac.dmg" >/dev/null
rm -rf "$DMG"
echo "OK : $OUT/amiga1200-mac.dmg"
