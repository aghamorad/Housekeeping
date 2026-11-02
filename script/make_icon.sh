#!/usr/bin/env bash
#
# Housekeeping — build the app icon from the source art.
#
# Generates unboxed, transparent-background iconset and AppIcon.icns
# for clean floating display across macOS.
#
#   ./script/make_icon.sh <source.png>
#
# Writes Housekeeping/Resources/AppIcon.png and AppIcon.icns in place.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${1:-}"

if [[ -z "$SOURCE" || ! -f "$SOURCE" ]]; then
  echo "usage: $0 <source.png>" >&2
  exit 1
fi

RESOURCES="$ROOT_DIR/Housekeeping/Resources"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/housekeeping-icon.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

echo "Preparing transparent unboxed icon from $SOURCE..."
swift "$ROOT_DIR/script/prepare_icon.swift" "$SOURCE" "$WORK/AppIcon-1024.png"

echo "Building the iconset..."
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$WORK/AppIcon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$WORK/AppIcon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
cp "$WORK/AppIcon-1024.png" "$RESOURCES/AppIcon.png"

echo "Generated unboxed AppIcon.icns and AppIcon.png with transparent background:"
ls -la "$RESOURCES/AppIcon.icns" "$RESOURCES/AppIcon.png"
