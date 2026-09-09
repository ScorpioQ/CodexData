#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexData"
PROJECT="CodexData.xcodeproj"
SCHEME="CodexData"
VERSION="${1:-0.1.0}"
ARCH_ARGS=(-arch arm64 -arch x86_64)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.releaseDerivedData"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/CodexPulse-$VERSION-universal.dmg"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ -n "$NOTARY_PROFILE" && -z "$SIGNING_IDENTITY" ]]; then
    echo "NOTARY_PROFILE requires SIGNING_IDENTITY." >&2
    exit 2
fi

mkdir -p "$DIST_DIR"
/bin/rm -rf "$APP_PATH"
/bin/rm -f "$DMG_PATH"

xcodebuild \
    -project "$ROOT_DIR/$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    "${ARCH_ARGS[@]}" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    clean build

BUILD_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
ditto "$BUILD_APP" "$APP_PATH"

MAIN_BINARY="$APP_PATH/Contents/MacOS/$APP_NAME"
ARCH_INFO="$(lipo -info "$MAIN_BINARY")"
if ! [[ "$ARCH_INFO" =~ arm64.*x86_64|x86_64.*arm64 ]]; then
    echo "Expected arm64 and x86_64 slices, got: $ARCH_INFO" >&2
    exit 1
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
    codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_PATH"
fi

DMG_CONTENTS="$(mktemp -d)"
RW_DMG="$DIST_DIR/.CodexPulse-$VERSION-rw.dmg"
VOL_NAME="Codex Pulse"
MOUNT_POINT=""

cleanup() {
    if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
        hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi
    /bin/rm -rf "$DMG_CONTENTS"
    /bin/rm -f "$RW_DMG"
}
trap cleanup EXIT

ditto "$APP_PATH" "$DMG_CONTENTS/$APP_NAME.app"
ln -s /Applications "$DMG_CONTENTS/Applications"

hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$DMG_CONTENTS" \
    -ov \
    -format UDRW \
    "$RW_DMG" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)"
MOUNT_POINT="$(printf '%s\n' "$ATTACH_OUTPUT" | sed -n 's#.*\(/Volumes/.*\)$#\1#p' | head -n 1)"
if [[ -z "$MOUNT_POINT" ]]; then
    echo "Unable to determine the mounted DMG path." >&2
    exit 1
fi
MOUNT_NAME="${MOUNT_POINT##*/}"

# Best-effort Finder layout: the DMG remains a normal drag-and-drop image if
# Finder automation is unavailable (for example in a headless build runner).
if ! osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$MOUNT_NAME"
        open
        delay 1
        set theWindow to container window
        set current view of theWindow to icon view
        set toolbar visible of theWindow to false
        set statusbar visible of theWindow to false
        set bounds of theWindow to {120, 120, 920, 620}
        set viewOptions to icon view options of theWindow
        set icon size of viewOptions to 128
        set arrangement of viewOptions to not arranged
        set shows item info of viewOptions to false
        set position of item "$APP_NAME.app" to {220, 270}
        set position of item "Applications" to {600, 270}
        close theWindow
    end tell
end tell
APPLESCRIPT
then
    echo "Warning: Finder DMG layout was skipped; using the standard drag-and-drop view." >&2
fi

hdiutil detach "$MOUNT_POINT" >/dev/null
MOUNT_POINT=""
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG_PATH" >/dev/null

if [[ -n "$SIGNING_IDENTITY" ]]; then
    codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
else
    echo "Warning: unsigned/not notarized build; set SIGNING_IDENTITY and NOTARY_PROFILE for public distribution." >&2
fi

echo "Universal binary: $ARCH_INFO"
echo "DMG: $DMG_PATH"
