#!/usr/bin/env bash
# Baut "Billy Desktop.app" nach build/ (ad-hoc signiert, läuft lokal ohne Apple-Developer-Account).
#   UNIVERSAL=1  -> arm64 + x86_64 (braucht Xcode)
#   CONFIG=debug -> Debug-Build
#   CODESIGN_IDENTITY="Developer ID Application: …" -> echte Signatur statt ad-hoc
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP="$ROOT/build/Billy Desktop.app"
cd "$ROOT"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/BillyDesktop" "$APP/Contents/MacOS/BillyDesktop"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/Sprites "$APP/Contents/Resources/Sprites"
if [[ -f Resources/PhotoSprites/sprites.json ]]; then
  cp -R Resources/PhotoSprites "$APP/Contents/Resources/PhotoSprites"
fi
if [[ -d Resources/Sounds ]]; then
  cp -R Resources/Sounds "$APP/Contents/Resources/Sounds"
fi
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --verbose=1 "$APP"
echo "✔ Fertig: $APP"
