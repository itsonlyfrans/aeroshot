#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Aeroshot"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="/private/tmp/aeroshot-codex-derived-data"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

xcodebuild -quiet \
  -project "$ROOT_DIR/Aeroshot.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build

open_app() {
  /usr/bin/open "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    if pgrep -x "$APP_NAME" >/dev/null; then
      echo "$APP_NAME is already running; quit it before starting LLDB." >&2
      exit 1
    fi
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.aeroshot"'
    ;;
  --verify|verify)
    open_app
    sleep 1
    test "$(pgrep -f "^$APP_BINARY$" | wc -l | tr -d ' ')" -eq 1
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
