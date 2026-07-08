#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY_SOURCE="$ROOT/Sources/FanCtlHelperXPC/HelperProtocol.swift"

read_swift_constant() {
    local name="$1"
    local value
    value="$(sed -n "s/^[[:space:]]*public static let $name = \"\\(.*\\)\"[[:space:]]*$/\\1/p" "$IDENTITY_SOURCE" | head -n 1)"
    if [[ -z "$value" ]]; then
        echo "Could not read Swift constant: $name" >&2
        exit 1
    fi
    printf '%s\n' "$value"
}

APP_NAME="$(read_swift_constant appName)"
APP_EXECUTABLE="$(read_swift_constant appExecutableName)"
BUNDLE_ID="$(read_swift_constant appBundleIdentifier)"
HELPER_ID="$(read_swift_constant machServiceName)"
HELPER_EXECUTABLE="$(read_swift_constant helperExecutableName)"

APP="$ROOT/.build/$APP_NAME.app"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"
BIN="$ROOT/.build/$BUILD_CONFIGURATION/mfanctl-menubar"
HELPER_BIN="$ROOT/.build/$BUILD_CONFIGURATION/mfanctl-helper"
APP_VERSION="${APP_VERSION:-0.0.0-dev}"
BUILD_NUMBER="${BUILD_NUMBER:-0}"

cd "$ROOT"
swift build -c "$BUILD_CONFIGURATION" --product mfanctl-menubar
swift build -c "$BUILD_CONFIGURATION" --product mfanctl-helper
"$ROOT/scripts/generate-app-icon.sh" >/dev/null

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Library/LaunchDaemons"
mkdir -p "$APP/Contents/Library/LaunchServices"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_EXECUTABLE"
chmod +x "$APP/Contents/MacOS/$APP_EXECUTABLE"
cp "$HELPER_BIN" "$APP/Contents/Library/LaunchServices/$HELPER_EXECUTABLE"
chmod +x "$APP/Contents/Library/LaunchServices/$HELPER_EXECUTABLE"
cp "$ROOT/Resources/AppIcon.png" "$APP/Contents/Resources/AppIcon.png"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Library/LaunchDaemons/$HELPER_ID.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$HELPER_ID</string>
  <key>BundleProgram</key>
  <string>Contents/Library/LaunchServices/$HELPER_EXECUTABLE</string>
  <key>MachServices</key>
  <dict>
    <key>$HELPER_ID</key>
    <true/>
  </dict>
  <key>AssociatedBundleIdentifiers</key>
  <array>
    <string>$BUNDLE_ID</string>
  </array>
  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
PLIST

/usr/libexec/PlistBuddy -c "Clear dict" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_EXECUTABLE" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $APP_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$APP/Contents/Info.plist"

echo "$APP"
