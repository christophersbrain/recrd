#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/recrd.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
BINARY_PATH="$ROOT_DIR/.build/release/recrd"
RESOURCE_BUNDLE_PATH="$ROOT_DIR/.build/release/recrd_recrd.bundle"
SPARKLE_FRAMEWORK_PATH="$ROOT_DIR/.build/release/Sparkle.framework"
APP_ICON_ICNS_PATH="$ROOT_DIR/Sources/recrd/Resources/AppIcon.icns"
SETUP_SIGNING_SCRIPT="$ROOT_DIR/scripts/setup-local-signing.sh"
APPCAST_URL="${RECRD_APPCAST_URL:-https://raw.githubusercontent.com/christophersbrain/recrd/main/appcast.xml}"
SPARKLE_PUBLIC_KEY="${RECRD_SPARKLE_PUBLIC_KEY:-}"
APP_VERSION="${RECRD_VERSION:-1.0.0}"
APP_BUILD="${RECRD_BUILD:-1}"

if [[ -n "${RECRD_SIGNING_IDENTITY:-}" ]]; then
    SIGNING_IDENTITY="$RECRD_SIGNING_IDENTITY"
else
    if [[ ! -x "$SETUP_SIGNING_SCRIPT" ]]; then
        echo "Missing signing setup script: $SETUP_SIGNING_SCRIPT" >&2
        exit 1
    fi
    SIGNING_IDENTITY="$("$SETUP_SIGNING_SCRIPT")"
fi

cd "$ROOT_DIR"
swift build -c release --product recrd

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
cp "$BINARY_PATH" "$MACOS_DIR/recrd"

if [[ -d "$SPARKLE_FRAMEWORK_PATH" ]]; then
    rm -rf "$FRAMEWORKS_DIR/Sparkle.framework"
    cp -R "$SPARKLE_FRAMEWORK_PATH" "$FRAMEWORKS_DIR/Sparkle.framework"
fi

if ! otool -l "$MACOS_DIR/recrd" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/recrd"
fi

if [[ -d "$RESOURCE_BUNDLE_PATH" ]]; then
    rm -rf "$RESOURCES_DIR/recrd_recrd.bundle"
    cp -R "$RESOURCE_BUNDLE_PATH" "$RESOURCES_DIR/recrd_recrd.bundle"
fi

if [[ -f "$APP_ICON_ICNS_PATH" ]]; then
    cp "$APP_ICON_ICNS_PATH" "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
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
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD}</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUFeedURL</key>
    <string>${APPCAST_URL}</string>
</dict>
</plist>
PLIST

if [[ -n "$SPARKLE_PUBLIC_KEY" ]]; then
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY" "$CONTENTS_DIR/Info.plist"
fi

codesign \
    --force \
    --deep \
    --sign "$SIGNING_IDENTITY" \
    --identifier com.recrd.app \
    "$APP_DIR"

codesign --verify --deep --strict "$APP_DIR"
touch "$APP_DIR"

echo "Built app bundle: $APP_DIR"
