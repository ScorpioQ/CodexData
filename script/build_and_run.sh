#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CodexData"
PROJECT="CodexData.xcodeproj"
SCHEME="CodexData"
ARCH_ARGS=(-arch arm64 -arch x86_64)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.derivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
xcodebuild -project "$ROOT_DIR/$PROJECT" -scheme "$SCHEME" -configuration Debug -derivedDataPath "$DERIVED_DATA" "${ARCH_ARGS[@]}" ONLY_ACTIVE_ARCH=NO ENABLE_DEBUG_DYLIB=NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

# Use an ad-hoc signature so LaunchServices can open the local personal build.
/usr/bin/codesign --force --deep --sign - "$APP_PATH" >/dev/null

open_app() {
    /usr/bin/open -n "$APP_PATH"
}

case "$MODE" in
    run)
        open_app
        ;;
    --debug|debug)
        lldb -- "$APP_PATH/Contents/MacOS/$APP_NAME"
        ;;
    --logs|logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
        ;;
    --telemetry|telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"com.czyw.CodexData\""
        ;;
    --verify|verify)
        open_app
        sleep 1
        pgrep -x "$APP_NAME" >/dev/null
        ;;
    *)
        echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
        exit 2
        ;;
esac
