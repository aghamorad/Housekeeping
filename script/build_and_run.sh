#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Housekeeping"
BUNDLE_ID="com.housekeeping.app"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
XCODEBUILD="$XCODE_DEVELOPER_DIR/usr/bin/xcodebuild"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
CONFIGURATION="${HOUSEKEEPING_BUILD_CONFIGURATION:-Debug}"
APP_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [[ ! -x "$XCODEBUILD" ]]; then
  echo "Housekeeping requires Xcode at /Applications/Xcode.app." >&2
  exit 1
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" "$XCODEBUILD" \
  -project "$ROOT_DIR/Housekeeping.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build

# Keep the runnable development bundle equivalent to packaged builds. These
# optional Bookbind resources live beside this repository, outside Swift sources.
BOOKBIND_SOURCE="${HOUSEKEEPING_BOOKBIND_SRC:-$ROOT_DIR/../Bookbind}"
if [[ -f "$BOOKBIND_SOURCE/app.py" && -f "$BOOKBIND_SOURCE/bookbind_cli.py" && -d "$BOOKBIND_SOURCE/static" ]]; then
  mkdir -p "$APP_BUNDLE/Contents/Resources/Bookbind"
  cp "$BOOKBIND_SOURCE/app.py" "$BOOKBIND_SOURCE/bookbind_cli.py" "$APP_BUNDLE/Contents/Resources/Bookbind/"
  ditto "$BOOKBIND_SOURCE/static" "$APP_BUNDLE/Contents/Resources/Bookbind/static"
fi
/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    /usr/bin/lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
