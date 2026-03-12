#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/recrd.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BINARY_PATH="$ROOT_DIR/.build/release/recrd"
RESOURCE_BUNDLE_PATH="$ROOT_DIR/.build/release/recrd_recrd.bundle"
APP_ICON_ICNS_PATH="$ROOT_DIR/Sources/recrd/Resources/AppIcon.icns"
SETUP_SIGNING_SCRIPT="$ROOT_DIR/scripts/setup-local-signing.sh"

if [[ ! -x "$SETUP_SIGNING_SCRIPT" ]]; then
    echo "Missing signing setup script: $SETUP_SIGNING_SCRIPT" >&2
    exit 1
fi

SIGNING_IDENTITY="$("$SETUP_SIGNING_SCRIPT")"

cd "$ROOT_DIR"
swift build -c release --product recrd

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY_PATH" "$MACOS_DIR/recrd"

if [[ -d "$RESOURCE_BUNDLE_PATH" ]]; then
    rm -rf "$RESOURCES_DIR/recrd_recrd.bundle"
    cp -R "$RESOURCE_BUNDLE_PATH" "$RESOURCES_DIR/recrd_recrd.bundle"
fi

if [[ -f "$APP_ICON_ICNS_PATH" ]]; then
    cp "$APP_ICON_ICNS_PATH" "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>recrd</string>
    <key>CFBundleIdentifier</key>
    <string>com.recrd.app</string>
    <key>CFBundleName</key>
    <string>recrd</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign \
    --force \
    --deep \
    --sign "$SIGNING_IDENTITY" \
    --identifier com.recrd.app \
    "$APP_DIR"

codesign --verify --deep --strict "$APP_DIR"
touch "$APP_DIR"

echo "Built app bundle: $APP_DIR"
