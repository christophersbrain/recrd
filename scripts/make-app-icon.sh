#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <source-image-path>" >&2
    exit 1
fi

SRC_IMAGE="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_ICNS="$ROOT_DIR/Sources/recrd/Resources/AppIcon.icns"
ICONSET_ROOT="$(mktemp -d /tmp/recrd.iconwork.XXXXXX)"
ICONSET_DIR="$ICONSET_ROOT/AppIcon.iconset"
TMP_SRC="$ICONSET_ROOT/source.png"

if [[ ! -f "$SRC_IMAGE" ]]; then
    echo "Source image not found: $SRC_IMAGE" >&2
    exit 2
fi

mkdir -p "$ICONSET_DIR"
cp "$SRC_IMAGE" "$TMP_SRC"

create_icon() {
    local size="$1"
    local out="$2"
    sips -z "$size" "$size" "$TMP_SRC" --out "$ICONSET_DIR/$out" >/dev/null
}

create_icon 16 icon_16x16.png
create_icon 32 icon_16x16@2x.png
create_icon 32 icon_32x32.png
create_icon 64 icon_32x32@2x.png
create_icon 128 icon_128x128.png
create_icon 256 icon_128x128@2x.png
create_icon 256 icon_256x256.png
create_icon 512 icon_256x256@2x.png
create_icon 512 icon_512x512.png
create_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$DEST_ICNS"
rm -rf "$ICONSET_ROOT"

echo "Wrote app icon: $DEST_ICNS"
