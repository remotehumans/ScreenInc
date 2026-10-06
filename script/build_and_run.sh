#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-run}"
pkill -x ScreenInk >/dev/null 2>&1 || true
swift build --disable-sandbox
APP="$PWD/dist/ScreenInc.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
./script/build_icon.sh
cp Assets/ScreenInc.icns "$APP/Contents/Resources/ScreenInc.icns"
cp "$(swift build --show-bin-path)/ScreenInk" "$APP/Contents/MacOS/ScreenInk"
cp Assets/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
case "$MODE" in
  --build-only) ;;
  --debug) lldb "$APP/Contents/MacOS/ScreenInk" ;;
  --logs|--telemetry) open -n "$APP"; /usr/bin/log stream --info --predicate 'process == "ScreenInk"' ;;
  --verify) open -n "$APP"; sleep 1; pgrep -x ScreenInk ;;
  run) open -n "$APP" ;;
  *) echo 'Use run, --build-only, --verify, --debug, --logs or --telemetry'; exit 2 ;;
esac
