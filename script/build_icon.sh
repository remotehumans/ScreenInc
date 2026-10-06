#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ICONSET="$(mktemp -d)/ScreenInc.iconset"
mkdir -p "$ICONSET"
trap 'rm -rf "$(dirname "$ICONSET")"' EXIT
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" Assets/ScreenInc-icon.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" Assets/ScreenInc-icon.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Assets/ScreenInc.icns
