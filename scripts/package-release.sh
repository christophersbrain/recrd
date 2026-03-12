#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/recrd.app"
OUT_DIR="${1:-$ROOT_DIR/release}"
VERSION="${2:-${RECRD_VERSION:-1.0.0}}"

mkdir -p "$OUT_DIR"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Missing app bundle: $APP_PATH" >&2
    echo "Run ./scripts/build-app.sh first." >&2
    exit 1
fi

ZIP_NAME="recrd-v${VERSION}.zip"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"
rm -f "$ZIP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
echo "$ZIP_PATH"
