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
RELEASE_ARTIFACT_NAME="$(read_swift_constant releaseArtifactName)"
BUNDLE_ID="$(read_swift_constant appBundleIdentifier)"
HELPER_ID="$(read_swift_constant helperBundleIdentifier)"
EXPECTED_TEAM_ID="$(read_swift_constant developerTeamIdentifier)"
HELPER_EXECUTABLE="$(read_swift_constant helperExecutableName)"
LEGACY_APP_BUNDLE_ID="$(read_swift_constant legacyAppBundleIdentifier)"
LEGACY_CLEANUP_APP_NAME="$(read_swift_constant legacyCleanupAppName)"
LEGACY_CLEANUP_EXECUTABLE="$(read_swift_constant legacyCleanupExecutableName)"
APP="$ROOT/.build/$APP_NAME.app"
HELPER="$APP/Contents/Library/LaunchServices/$HELPER_EXECUTABLE"
LEGACY_CLEANUP_APP="$APP/Contents/Library/Helpers/$LEGACY_CLEANUP_APP_NAME.app"
LEGACY_CLEANUP="$LEGACY_CLEANUP_APP/Contents/MacOS/$LEGACY_CLEANUP_EXECUTABLE"
DIST="$ROOT/dist"

APP_VERSION="${APP_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

usage() {
    cat <<EOF
Usage: scripts/package-release.sh [options]

Options:
  --identity NAME          Developer ID Application identity.
  --notary-profile NAME   notarytool keychain profile name.
  --version VERSION       CFBundleShortVersionString. Required.
  --build NUMBER          CFBundleVersion. Required.

Environment:
  DEVELOPER_ID_APPLICATION  Same as --identity.
  NOTARY_PROFILE            Same as --notary-profile.
  APP_VERSION               Same as --version.
  BUILD_NUMBER              Same as --build.

Signing, app/DMG notarization, stapling, and Gatekeeper assessment are
mandatory. For an unsigned local bundle, run scripts/package-menubar-app.sh.
EOF
}

require_option_value() {
    local option="$1"
    local value="${2:-}"
    if [[ -z "$value" || "$value" == --* ]]; then
        echo "Missing value for $option" >&2
        exit 2
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --identity)
            require_option_value "$1" "${2:-}"
            IDENTITY="$2"
            shift 2
            ;;
        --notarize)
            echo "Note: --notarize is no longer needed; release notarization is mandatory." >&2
            shift
            ;;
        --notary-profile)
            require_option_value "$1" "${2:-}"
            NOTARY_PROFILE="$2"
            shift 2
            ;;
        --version)
            require_option_value "$1" "${2:-}"
            APP_VERSION="$2"
            shift 2
            ;;
        --build)
            require_option_value "$1" "${2:-}"
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

if [[ ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    echo "Invalid release version: $APP_VERSION (expected two or three numeric components)" >&2
    exit 2
fi

if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "Invalid build number: $BUILD_NUMBER (expected a positive integer)" >&2
    exit 2
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
    cat >&2 <<EOF
Missing notarytool keychain profile. Release notarization cannot be skipped.

Create a profile without putting a password in shell history:
  xcrun notarytool store-credentials PROFILE_NAME --apple-id APPLE_ID --team-id TEAM_ID

notarytool will request the app-specific password with a secure prompt. Then run:
  scripts/package-release.sh --version $APP_VERSION --build $BUILD_NUMBER --notary-profile PROFILE_NAME
EOF
    exit 2
fi

for command_name in codesign ditto hdiutil lipo plutil security spctl xcrun; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Required release tool is unavailable: $command_name" >&2
        exit 1
    fi
done

detect_identity() {
    security find-identity -v -p codesigning |
        sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' |
        sed -n '1p'
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
  scripts/package-release.sh --version $APP_VERSION --build $BUILD_NUMBER --notary-profile PROFILE_NAME
EOF
    exit 1
fi

mkdir -p "$DIST"
APP_ZIP="$DIST/.$RELEASE_ARTIFACT_NAME-$APP_VERSION-notary.zip"
DMG="$DIST/$RELEASE_ARTIFACT_NAME-$APP_VERSION.dmg"
PREVIOUS_DMG="$DMG.previous"
STAGED_DMG="$DIST/.$RELEASE_ARTIFACT_NAME-$APP_VERSION-staging.dmg"
DMG_ROOT=""
RELEASE_SUCCEEDED=false

cleanup() {
    if [[ -n "$DMG_ROOT" ]]; then
        rm -rf "$DMG_ROOT"
    fi
    rm -f "$APP_ZIP"
    rm -f "$STAGED_DMG"
    if [[ "$RELEASE_SUCCEEDED" == "true" ]]; then
        rm -f "$PREVIOUS_DMG"
    elif [[ -f "$PREVIOUS_DMG" ]]; then
        echo "Previous successful DMG retained separately after release failure: $PREVIOUS_DMG" >&2
    fi
}
trap cleanup EXIT

# Remove the old artifact from the final path before any build/signing work.
# If anything below fails, the previous known-good DMG remains recoverable as
# `.previous` and cannot be mistaken for the attempted release.
if [[ -f "$DMG" ]]; then
    if [[ -e "$PREVIOUS_DMG" ]]; then
        echo "Cannot isolate the existing DMG because a previous backup already exists: $PREVIOUS_DMG" >&2
        exit 1
    fi
    mv "$DMG" "$PREVIOUS_DMG"
fi

cd "$ROOT"
APP_VERSION="$APP_VERSION" \
BUILD_NUMBER="$BUILD_NUMBER" \
BUILD_CONFIGURATION=release \
PACKAGING_MODE=release \
    "$ROOT/scripts/package-menubar-app.sh" >/dev/null

BUILT_DSYM_DIR="$ROOT/.build/dSYMs/$APP_VERSION-$BUILD_NUMBER"
RELEASE_DSYM_DIR="$DIST/$RELEASE_ARTIFACT_NAME-$APP_VERSION-$BUILD_NUMBER.dSYMs"
if [[ ! -d "$BUILT_DSYM_DIR" ]]; then
    echo "Release packaging did not produce dSYMs: $BUILT_DSYM_DIR" >&2
    exit 1
fi
rm -rf "$RELEASE_DSYM_DIR"
ditto "$BUILT_DSYM_DIR" "$RELEASE_DSYM_DIR"

if [[ ! -x "$APP/Contents/MacOS/$APP_EXECUTABLE" ||
      ! -x "$HELPER" ||
      ! -x "$LEGACY_CLEANUP" ]]; then
    echo "Release bundle is missing an expected executable." >&2
    exit 1
fi

codesign --force --timestamp --options runtime \
    --sign "$IDENTITY" \
    --identifier "$LEGACY_APP_BUNDLE_ID" \
    "$LEGACY_CLEANUP_APP"

codesign --force --timestamp --options runtime \
    --sign "$IDENTITY" \
    --identifier "$HELPER_ID" \
    "$HELPER"

codesign --force --timestamp --options runtime \
    --sign "$IDENTITY" \
    --identifier "$BUNDLE_ID" \
    "$APP"

codesign --verify --strict --verbose=2 "$HELPER"
codesign --verify --deep --strict --verbose=2 "$LEGACY_CLEANUP_APP"
codesign --verify --deep --strict --verbose=2 "$APP"

signature_details() {
    codesign --display --verbose=4 "$1" 2>&1
}

signature_value() {
    local details="$1"
    local key="$2"
    sed -n "s/^$key=//p" <<<"$details" | sed -n '1p'
}

verify_signature() {
    local path="$1"
    local expected_identifier="$2"
    local details identifier team
    details="$(signature_details "$path")"
    identifier="$(signature_value "$details" Identifier)"
    team="$(signature_value "$details" TeamIdentifier)"

    if [[ "$identifier" != "$expected_identifier" ]]; then
        echo "Unexpected signing identifier for $path: '$identifier'" >&2
        exit 1
    fi
    if [[ -z "$team" || "$team" == "not set" ]]; then
        echo "Missing signing team identifier for $path" >&2
        exit 1
    fi
    if [[ "$details" != *"Authority=Developer ID Application:"* ]]; then
        echo "Artifact is not signed with a Developer ID Application certificate: $path" >&2
        exit 1
    fi
    if [[ "$details" != *"(runtime)"* || "$details" != *"Timestamp="* ]]; then
        echo "Artifact is missing hardened runtime or a trusted timestamp: $path" >&2
        exit 1
    fi

    printf '%s\n' "$team"
}

APP_TEAM="$(verify_signature "$APP" "$BUNDLE_ID")"
HELPER_TEAM="$(verify_signature "$HELPER" "$HELPER_ID")"
LEGACY_CLEANUP_TEAM="$(
    verify_signature "$LEGACY_CLEANUP_APP" "$LEGACY_APP_BUNDLE_ID"
)"
if [[ "$APP_TEAM" != "$HELPER_TEAM" ||
      "$APP_TEAM" != "$LEGACY_CLEANUP_TEAM" ]]; then
    echo "Signing team mismatch: app='$APP_TEAM', helper='$HELPER_TEAM', cleanup='$LEGACY_CLEANUP_TEAM'" >&2
    exit 1
fi
if [[ "$APP_TEAM" != "$EXPECTED_TEAM_ID" ]]; then
    echo "Unexpected signing team: '$APP_TEAM' (expected '$EXPECTED_TEAM_ID')" >&2
    exit 1
fi

DMG_ROOT="$(mktemp -d "$DIST/dmg-root.XXXXXX")"

submit_for_notarization() {
    local artifact="$1"
    local result status submission_id

    if ! result="$(xcrun notarytool submit "$artifact" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait \
        --output-format json)"; then
        echo "Notarization request failed for $artifact" >&2
        printf '%s\n' "$result" >&2
        exit 1
    fi

    status="$(plutil -extract status raw -o - - <<<"$result" 2>/dev/null || true)"
    submission_id="$(plutil -extract id raw -o - - <<<"$result" 2>/dev/null || true)"
    if [[ "$status" != "Accepted" ]]; then
        echo "Notarization was not accepted for $artifact (status='$status', id='$submission_id')." >&2
        printf '%s\n' "$result" >&2
        exit 1
    fi
}

rm -f "$APP_ZIP"
ditto -c -k --keepParent "$APP" "$APP_ZIP"
submit_for_notarization "$APP_ZIP"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=4 "$APP"

ditto "$APP" "$DMG_ROOT/$APP_NAME.app"
cp "$ROOT/LICENSE" "$DMG_ROOT/LICENSE.txt"
ln -s /Applications "$DMG_ROOT/Applications"
codesign --verify --deep --strict --verbose=2 "$DMG_ROOT/$APP_NAME.app"
xcrun stapler validate "$DMG_ROOT/$APP_NAME.app"

rm -f "$STAGED_DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$STAGED_DMG" >/dev/null

codesign --force --timestamp --sign "$IDENTITY" "$STAGED_DMG"
codesign --verify --strict --verbose=2 "$STAGED_DMG"

submit_for_notarization "$STAGED_DMG"
xcrun stapler staple "$STAGED_DMG"
xcrun stapler validate "$STAGED_DMG"
codesign --verify --strict --verbose=2 "$STAGED_DMG"
spctl --assess --type open --context context:primary-signature --verbose "$STAGED_DMG"

mv -f "$STAGED_DMG" "$DMG"
RELEASE_SUCCEEDED=true

echo "$DMG"
