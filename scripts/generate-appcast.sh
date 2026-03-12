#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_BIN="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
ARCHIVES_DIR="${RECRD_RELEASE_DIR:-$ROOT_DIR/release}"
TAG="${RECRD_RELEASE_TAG:-}"
OUTPUT_APPCAST="${RECRD_APPCAST_OUTPUT:-$ROOT_DIR/appcast.xml}"
DOWNLOAD_PREFIX="${RECRD_DOWNLOAD_URL_PREFIX:-}"
EXISTING_APPCAST="${RECRD_EXISTING_APPCAST:-$OUTPUT_APPCAST}"

usage() {
    cat <<EOF
Usage: $0 --tag <vX.Y.Z> [--archives-dir <dir>] [--output <appcast.xml>] [--download-prefix <url>]

Environment:
  SPARKLE_PRIVATE_KEY    Optional private Ed25519 key used to sign appcast entries.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)
            TAG="${2:-}"
            shift 2
            ;;
        --archives-dir)
            ARCHIVES_DIR="${2:-}"
            shift 2
            ;;
        --output)
            OUTPUT_APPCAST="${2:-}"
            shift 2
            ;;
        --download-prefix)
            DOWNLOAD_PREFIX="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

if [[ -z "$TAG" ]]; then
    echo "Missing --tag <vX.Y.Z>" >&2
    exit 2
fi

if [[ ! -x "$SPARKLE_BIN" ]]; then
    echo "Sparkle tool not found: $SPARKLE_BIN" >&2
    echo "Run swift build once to fetch Sparkle artifacts." >&2
    exit 1
fi

if [[ ! -d "$ARCHIVES_DIR" ]]; then
    echo "Archives dir not found: $ARCHIVES_DIR" >&2
    exit 1
fi

if [[ -z "$DOWNLOAD_PREFIX" ]]; then
    DOWNLOAD_PREFIX="https://github.com/christophersbrain/recrd/releases/download/${TAG}/"
fi

if [[ -f "$EXISTING_APPCAST" ]]; then
    target_existing="$ARCHIVES_DIR/appcast.xml"
    if [[ "$EXISTING_APPCAST" != "$target_existing" ]]; then
        cp "$EXISTING_APPCAST" "$target_existing"
    fi
fi

cmd=("$SPARKLE_BIN" "--download-url-prefix" "$DOWNLOAD_PREFIX" "$ARCHIVES_DIR")
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    echo "$SPARKLE_PRIVATE_KEY" | "${cmd[@]}" --ed-key-file -
else
    "${cmd[@]}"
fi

generated_appcast="$ARCHIVES_DIR/appcast.xml"
if [[ "$generated_appcast" != "$OUTPUT_APPCAST" ]]; then
    cp "$generated_appcast" "$OUTPUT_APPCAST"
fi
echo "Generated appcast: $OUTPUT_APPCAST"
