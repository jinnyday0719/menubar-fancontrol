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
HELPER="$APP/Contents/Library/LaunchServices/$HELPER_EXECUTABLE"
DIST="$ROOT/dist"
DMG_ROOT="$DIST/dmg-root"

APP_VERSION="${APP_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
NOTARIZE=0

usage() {
    cat <<EOF
Usage: scripts/package-release.sh [options]

Options:
  --identity NAME          Developer ID Application identity.
  --notarize              Submit the DMG to Apple's notary service.
  --notary-profile NAME   notarytool keychain profile name.
  --version VERSION       CFBundleShortVersionString. Required.
  --build NUMBER          CFBundleVersion. Required.

Environment:
  DEVELOPER_ID_APPLICATION  Same as --identity.
  NOTARY_PROFILE            Same as --notary-profile.
  APP_VERSION               Same as --version.
  BUILD_NUMBER              Same as --build.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --identity)
            IDENTITY="$2"
            shift 2
            ;;
        --notarize)
            NOTARIZE=1
            shift
            ;;
        --notary-profile)
            NOTARY_PROFILE="$2"
            shift 2
            ;;
        --version)
            APP_VERSION="$2"
            shift 2
            ;;
        --build)
            BUILD_NUMBER="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$APP_VERSION" || -z "$BUILD_NUMBER" ]]; then
    cat >&2 <<EOF
Missing release version or build number.

Run:
  scripts/package-release.sh --version VERSION --build NUMBER
EOF
    exit 2
fi

detect_identity() {
    security find-identity -v -p codesigning |
        sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' |
        head -n 1
}

if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(detect_identity)"
fi

if [[ -z "$IDENTITY" ]]; then
    cat >&2 <<EOF
No Developer ID Application certificate was found in your keychain.

Create one in Xcode:
  Xcode > Settings > Accounts > Manage Certificates... > + > Developer ID Application

Then run:
  scripts/package-release.sh --notarize --notary-profile PROFILE_NAME
EOF
    exit 1
fi

cd "$ROOT"
APP_VERSION="$APP_VERSION" BUILD_NUMBER="$BUILD_NUMBER" BUILD_CONFIGURATION=release "$ROOT/scripts/package-menubar-app.sh" >/dev/null

codesign --force --timestamp --options runtime \
    --sign "$IDENTITY" \
    --identifier "$HELPER_ID" \
    "$HELPER"

codesign --force --timestamp --options runtime \
    --sign "$IDENTITY" \
    --identifier "$BUNDLE_ID" \
    "$APP"

codesign --verify --strict --verbose=2 "$APP"

mkdir -p "$DIST"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
cp -R "$APP" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"

DMG="$DIST/$APP_NAME-$APP_VERSION.dmg"
rm -f "$DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG" >/dev/null
rm -rf "$DMG_ROOT"

codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [[ "$NOTARIZE" == "1" ]]; then
    if [[ -z "$NOTARY_PROFILE" ]]; then
        cat >&2 <<EOF
Missing notarytool profile.

Store credentials once:
  xcrun notarytool store-credentials PROFILE_NAME --apple-id APPLE_ID --team-id TEAM_ID --password APP_SPECIFIC_PASSWORD

Then rerun:
  scripts/package-release.sh --notarize --notary-profile PROFILE_NAME
EOF
        exit 1
    fi

    xcrun notarytool submit "$DMG" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

echo "$DMG"
