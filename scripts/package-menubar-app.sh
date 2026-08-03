#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY_SOURCE="$ROOT/Sources/FanCtlHelperXPC/HelperProtocol.swift"

read_swift_constant() {
    local name="$1"
    local value
    value="$(sed -n "s/^[[:space:]]*public static let $name = \"\\(.*\\)\"[[:space:]]*$/\\1/p" "$IDENTITY_SOURCE" | sed -n '1p')"
    if [[ -z "$value" ]]; then
        echo "Could not read Swift constant: $name" >&2
        exit 1
    fi
    printf '%s\n' "$value"
}

APP_NAME="$(read_swift_constant appName)"
APP_EXECUTABLE="$(read_swift_constant appExecutableName)"
BUNDLE_ID="$(read_swift_constant appBundleIdentifier)"
HELPER_BUNDLE_ID="$(read_swift_constant helperBundleIdentifier)"
HELPER_ID="$HELPER_BUNDLE_ID"
HELPER_EXECUTABLE="$(read_swift_constant helperExecutableName)"
LEGACY_APP_BUNDLE_ID="$(read_swift_constant legacyAppBundleIdentifier)"
LEGACY_HELPER_ID="$(read_swift_constant legacyMachServiceName)"
LEGACY_CLEANUP_APP_NAME="$(read_swift_constant legacyCleanupAppName)"
LEGACY_CLEANUP_EXECUTABLE="$(read_swift_constant legacyCleanupExecutableName)"

APP="$ROOT/.build/$APP_NAME.app"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"
PACKAGING_MODE="${PACKAGING_MODE:-development}"
IS_DISTRIBUTION_BUILD=false
BIN="$ROOT/.build/$BUILD_CONFIGURATION/menubar-fancontrol"
HELPER_BIN="$ROOT/.build/$BUILD_CONFIGURATION/menubar-fancontrol-helper"
LEGACY_CLEANUP_BIN="$ROOT/.build/$BUILD_CONFIGURATION/menubar-fancontrol-legacy-cleanup"
LEGACY_CLEANUP_APP="$APP/Contents/Library/Helpers/$LEGACY_CLEANUP_APP_NAME.app"
APP_VERSION="${APP_VERSION:-0.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-0}"
GENERATED_ASSETS="$ROOT/.build/packaging-assets"
GENERATED_ICON="$GENERATED_ASSETS/AppIcon.icns"
DSYM_OUTPUT_DIR="$ROOT/.build/dSYMs/$APP_VERSION-$BUILD_NUMBER"

case "$BUILD_CONFIGURATION" in
    debug|release) ;;
    *)
        echo "Unsupported BUILD_CONFIGURATION: $BUILD_CONFIGURATION (expected debug or release)" >&2
        exit 2
        ;;
esac

case "$PACKAGING_MODE" in
    development|release) ;;
    *)
        echo "Unsupported PACKAGING_MODE: $PACKAGING_MODE (expected development or release)" >&2
        exit 2
        ;;
esac

if [[ ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    echo "Invalid APP_VERSION: $APP_VERSION" >&2
    exit 2
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Invalid BUILD_NUMBER: $BUILD_NUMBER" >&2
    exit 2
fi

if [[ "$PACKAGING_MODE" == "release" ]]; then
    IS_DISTRIBUTION_BUILD=true
    if [[ "$BUILD_CONFIGURATION" != "release" ]]; then
        echo "Release packaging requires BUILD_CONFIGURATION=release." >&2
        exit 2
    fi
    if [[ "$BUILD_NUMBER" == "0" ]]; then
        echo "Release packaging requires a numeric release version and a positive build number." >&2
        exit 2
    fi
else
    cat >&2 <<EOF
Creating an unsigned development bundle.
This output supports UI/sensor testing only; privileged fan control requires a signed build.
Use scripts/package-release.sh for distribution.
EOF
fi

for required_file in \
    "$ROOT/Resources/AppIcon.png" \
    "$ROOT/LICENSE"; do
    if [[ ! -f "$required_file" ]]; then
        echo "Required packaging input is missing: $required_file" >&2
        exit 1
    fi
done

cd "$ROOT"
"$ROOT/scripts/generate-app-icon.sh" "$GENERATED_ASSETS" >/dev/null
if [[ ! -f "$GENERATED_ICON" ]]; then
    echo "App icon generation did not produce: $GENERATED_ICON" >&2
    exit 1
fi

swift build -c "$BUILD_CONFIGURATION" --product menubar-fancontrol
swift build -c "$BUILD_CONFIGURATION" --product menubar-fancontrol-helper
swift build -c "$BUILD_CONFIGURATION" --product menubar-fancontrol-legacy-cleanup

for executable in "$BIN" "$HELPER_BIN" "$LEGACY_CLEANUP_BIN"; do
    if [[ ! -f "$executable" || ! -x "$executable" ]]; then
        echo "Expected executable was not produced: $executable" >&2
        exit 1
    fi
done

if [[ "$PACKAGING_MODE" == "release" ]]; then
    for command_name in dsymutil strip; do
        if ! xcrun --find "$command_name" >/dev/null 2>&1; then
            echo "Required release tool is unavailable: $command_name" >&2
            exit 1
        fi
    done

    # The directory is keyed by release version/build. Recreate it so a renamed
    # executable or a repeated build cannot carry obsolete dSYMs into the
    # distributable archive.
    rm -rf "$DSYM_OUTPUT_DIR"
    mkdir -p "$DSYM_OUTPUT_DIR"
    xcrun dsymutil "$BIN" -o "$DSYM_OUTPUT_DIR/$APP_EXECUTABLE.dSYM"
    xcrun dsymutil "$HELPER_BIN" -o "$DSYM_OUTPUT_DIR/$HELPER_EXECUTABLE.dSYM"
    xcrun dsymutil \
        "$LEGACY_CLEANUP_BIN" \
        -o "$DSYM_OUTPUT_DIR/$LEGACY_CLEANUP_EXECUTABLE.dSYM"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Library/LaunchDaemons"
mkdir -p "$APP/Contents/Library/LaunchServices"
mkdir -p "$LEGACY_CLEANUP_APP/Contents/Library/LaunchDaemons"
mkdir -p "$LEGACY_CLEANUP_APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_EXECUTABLE"
chmod +x "$APP/Contents/MacOS/$APP_EXECUTABLE"
cp "$HELPER_BIN" "$APP/Contents/Library/LaunchServices/$HELPER_EXECUTABLE"
chmod +x "$APP/Contents/Library/LaunchServices/$HELPER_EXECUTABLE"
cp "$LEGACY_CLEANUP_BIN" \
    "$LEGACY_CLEANUP_APP/Contents/MacOS/$LEGACY_CLEANUP_EXECUTABLE"
chmod +x "$LEGACY_CLEANUP_APP/Contents/MacOS/$LEGACY_CLEANUP_EXECUTABLE"
cp "$GENERATED_ICON" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"

if [[ "$PACKAGING_MODE" == "release" ]]; then
    xcrun strip -Sx "$APP/Contents/MacOS/$APP_EXECUTABLE"
    xcrun strip -Sx "$APP/Contents/Library/LaunchServices/$HELPER_EXECUTABLE"
    xcrun strip -Sx \
        "$LEGACY_CLEANUP_APP/Contents/MacOS/$LEGACY_CLEANUP_EXECUTABLE"
fi

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

cat > "$LEGACY_CLEANUP_APP/Contents/Library/LaunchDaemons/$LEGACY_HELPER_ID.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LEGACY_HELPER_ID</string>
  <key>BundleProgram</key>
  <string>Contents/MacOS/$LEGACY_CLEANUP_EXECUTABLE</string>
  <key>MachServices</key>
  <dict>
    <key>$LEGACY_HELPER_ID</key>
    <true/>
  </dict>
  <key>AssociatedBundleIdentifiers</key>
  <array>
    <string>$LEGACY_APP_BUNDLE_ID</string>
  </array>
  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
PLIST

/usr/libexec/PlistBuddy -c "Clear dict" \
    "$LEGACY_CLEANUP_APP/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c \
    "Add :CFBundleExecutable string $LEGACY_CLEANUP_EXECUTABLE" \
    "$LEGACY_CLEANUP_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c \
    "Add :CFBundleIdentifier string $LEGACY_APP_BUNDLE_ID" \
    "$LEGACY_CLEANUP_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c \
    "Add :CFBundleName string $LEGACY_CLEANUP_APP_NAME" \
    "$LEGACY_CLEANUP_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c \
    "Add :CFBundleDisplayName string $LEGACY_CLEANUP_APP_NAME" \
    "$LEGACY_CLEANUP_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c \
    "Add :CFBundlePackageType string APPL" \
    "$LEGACY_CLEANUP_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c \
    "Add :CFBundleVersion string $BUILD_NUMBER" \
    "$LEGACY_CLEANUP_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c \
    "Add :CFBundleShortVersionString string $APP_VERSION" \
    "$LEGACY_CLEANUP_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c \
    "Add :LSMinimumSystemVersion string 14.0" \
    "$LEGACY_CLEANUP_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c \
    "Add :LSUIElement bool true" \
    "$LEGACY_CLEANUP_APP/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Clear dict" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_EXECUTABLE" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $APP_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :FanControlDistributionBuild bool $IS_DISTRIBUTION_BUILD" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$APP/Contents/Info.plist"

require_plist_value() {
    local plist="$1"
    local key="$2"
    local expected="$3"
    local actual
    actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null || true)"
    if [[ "$actual" != "$expected" ]]; then
        echo "Invalid plist value in $plist: $key is '$actual', expected '$expected'" >&2
        exit 1
    fi
}

APP_PLIST="$APP/Contents/Info.plist"
HELPER_PLIST="$APP/Contents/Library/LaunchDaemons/$HELPER_ID.plist"
LEGACY_CLEANUP_PLIST="$LEGACY_CLEANUP_APP/Contents/Info.plist"
LEGACY_HELPER_PLIST="$LEGACY_CLEANUP_APP/Contents/Library/LaunchDaemons/$LEGACY_HELPER_ID.plist"

plutil -lint "$APP_PLIST" >/dev/null
plutil -lint "$HELPER_PLIST" >/dev/null
plutil -lint "$LEGACY_CLEANUP_PLIST" >/dev/null
plutil -lint "$LEGACY_HELPER_PLIST" >/dev/null
require_plist_value "$APP_PLIST" CFBundleExecutable "$APP_EXECUTABLE"
require_plist_value "$APP_PLIST" CFBundleIdentifier "$BUNDLE_ID"
require_plist_value "$APP_PLIST" CFBundleVersion "$BUILD_NUMBER"
require_plist_value "$APP_PLIST" CFBundleShortVersionString "$APP_VERSION"
require_plist_value "$APP_PLIST" CFBundlePackageType APPL
require_plist_value "$APP_PLIST" FanControlDistributionBuild "$IS_DISTRIBUTION_BUILD"
require_plist_value "$HELPER_PLIST" Label "$HELPER_ID"
require_plist_value "$HELPER_PLIST" BundleProgram "Contents/Library/LaunchServices/$HELPER_EXECUTABLE"
require_plist_value "$HELPER_PLIST" "MachServices:$HELPER_ID" true
require_plist_value "$HELPER_PLIST" "AssociatedBundleIdentifiers:0" "$BUNDLE_ID"
require_plist_value \
    "$LEGACY_CLEANUP_PLIST" \
    CFBundleExecutable \
    "$LEGACY_CLEANUP_EXECUTABLE"
require_plist_value \
    "$LEGACY_CLEANUP_PLIST" \
    CFBundleIdentifier \
    "$LEGACY_APP_BUNDLE_ID"
require_plist_value "$LEGACY_HELPER_PLIST" Label "$LEGACY_HELPER_ID"
require_plist_value \
    "$LEGACY_HELPER_PLIST" \
    BundleProgram \
    "Contents/MacOS/$LEGACY_CLEANUP_EXECUTABLE"
require_plist_value \
    "$LEGACY_HELPER_PLIST" \
    "MachServices:$LEGACY_HELPER_ID" \
    true
require_plist_value \
    "$LEGACY_HELPER_PLIST" \
    "AssociatedBundleIdentifiers:0" \
    "$LEGACY_APP_BUNDLE_ID"

APP_ARCHS="$(lipo -archs "$APP/Contents/MacOS/$APP_EXECUTABLE")"
HELPER_ARCHS="$(lipo -archs "$APP/Contents/Library/LaunchServices/$HELPER_EXECUTABLE")"
LEGACY_CLEANUP_ARCHS="$(
    lipo -archs "$LEGACY_CLEANUP_APP/Contents/MacOS/$LEGACY_CLEANUP_EXECUTABLE"
)"
if [[ "$APP_ARCHS" != "$HELPER_ARCHS" ||
      "$APP_ARCHS" != "$LEGACY_CLEANUP_ARCHS" ]]; then
    echo "Executable architecture mismatch: app='$APP_ARCHS', helper='$HELPER_ARCHS', cleanup='$LEGACY_CLEANUP_ARCHS'" >&2
    exit 1
fi
if [[ "$PACKAGING_MODE" == "release" && "$APP_ARCHS" != "arm64" ]]; then
    echo "Release artifacts must be arm64-only for the supported Apple Silicon target; found '$APP_ARCHS'." >&2
    exit 1
fi

echo "$APP"
