#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /path/to/developer-id.p12" >&2
    exit 1
fi

P12_PATH="$1"
if [[ ! -f "$P12_PATH" ]]; then
    echo "File not found: $P12_PATH" >&2
    exit 1
fi

base64 < "$P12_PATH" | tr -d '\n'
echo
