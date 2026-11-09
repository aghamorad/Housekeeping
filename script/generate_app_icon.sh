#!/usr/bin/env bash
# Regenerate a macOS icon directly from the checked-in octopus mascot.
# No image generator, third-party library, network request, or hard-coded home path.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
OUT_DIR="${1:-$ROOT_DIR/.build/generated-app-icon}"
MASCOT="$ROOT_DIR/Housekeeping/Resources/BenignMonster/housekeeper_octopus_maid.png"
[[ -f "$MASCOT" ]] || { echo "Missing canonical mascot: $MASCOT" >&2; exit 1; }
command -v swift >/dev/null || { echo "Xcode Command Line Tools are required." >&2; exit 1; }
command -v iconutil >/dev/null || { echo "macOS iconutil is required." >&2; exit 1; }
command -v sips >/dev/null || { echo "macOS sips is required." >&2; exit 1; }

mkdir -p "$OUT_DIR"
swift "$ROOT_DIR/script/render_app_icon.swift" "$MASCOT" "$OUT_DIR"

ICONSET="$OUT_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$OUT_DIR/AppIcon-1024.png" \
        --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    twice=$((size * 2))
    sips -s format png -z "$twice" "$twice" "$OUT_DIR/AppIcon-1024.png" \
        --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$OUT_DIR/AppIcon.icns"
[[ -s "$OUT_DIR/AppIcon.icns" ]] || { echo "Icon generation failed." >&2; exit 1; }
echo "New legacy icon: $OUT_DIR/AppIcon.icns"
echo "Icon Composer layers: $OUT_DIR/Icon-01-Background.png and Icon-02-Octopus-Foreground.png"
