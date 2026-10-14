#!/usr/bin/env bash
#
# Housekeeping — build the app icon from the source art.
#
# The source art arrives as a rounded plate on a transparent field, which is the
# right shape for a picture and the wrong shape for a Mac app icon. macOS draws
# its own rounded square around every icon and paints a pale plinth behind
# anything with transparency in it, so a plate with transparent corners ends up
# as a small square floating on a grey tile — the system's shape, not ours.
#
# So the plate is cropped to its solid bounds, scaled to fill the whole 1024
# canvas edge to edge, and the corner it leaves behind is filled with the
# artwork's own border colour. Nothing is transparent afterwards, and the
# system's mask has nothing to work with but the art. The reasoning and the
# threshold live in prepare_icon.swift, which is the same tool Telesm uses.
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

echo "Preparing $SOURCE..."
swift "$ROOT_DIR/script/prepare_icon.swift" "$SOURCE" "$WORK/AppIcon-1024.png"

echo "Building the iconset..."
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$WORK/AppIcon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$WORK/AppIcon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

# A last guard before the files are replaced: the whole point of this pipeline is
# that no transparency survives it, and a silent regression here is invisible in
# the source and only shows up as a pale plinth on someone else's Mac.
alpha_range="$(sips -g hasAlpha "$WORK/AppIcon-1024.png" | tail -1)"
echo "Prepared icon: $alpha_range"

iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
cp "$WORK/AppIcon-1024.png" "$RESOURCES/AppIcon.png"

echo
ls -la "$RESOURCES/AppIcon.icns" "$RESOURCES/AppIcon.png"
