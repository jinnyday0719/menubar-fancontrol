#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/Resources/AppIcon.png"
OUTPUT_DIR="${1:-$ROOT/Resources}"
ICONSET="$OUTPUT_DIR/AppIcon.iconset"
ICNS="$OUTPUT_DIR/AppIcon.icns"

if [[ ! -f "$SOURCE" ]]; then
  echo "PNG icon source not found: $SOURCE" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

render_png() {
  local size="$1"
  local name="$2"
  sips -s format png -z "$size" "$size" "$SOURCE" --out "$ICONSET/$name" >/dev/null
}

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

render_png 16 "icon_16x16.png"
render_png 32 "icon_16x16@2x.png"
render_png 32 "icon_32x32.png"
render_png 64 "icon_32x32@2x.png"
render_png 128 "icon_128x128.png"
render_png 256 "icon_128x128@2x.png"
render_png 256 "icon_256x256.png"
render_png 512 "icon_256x256@2x.png"
render_png 512 "icon_512x512.png"
render_png 1024 "icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$ICNS"

echo "$ICNS"
