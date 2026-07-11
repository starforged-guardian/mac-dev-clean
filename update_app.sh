#!/bin/bash

set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SOURCE_APP="$ROOT/dist/mac-dev-clean.app"
APP_NAME="mac-dev-clean.app"
INSTALL_DIR=${MACOS_INSTALL_DIR:-/Applications}
OPEN_AFTER_INSTALL=1
WORK_DIR=""
DESTINATION=""
BACKUP_APP=""
INSTALLED_EXECUTABLE_PATTERN=""

usage() {
    cat <<'EOF'
Usage: ./update_app.sh [--no-open]

Build the native mac-dev-clean app from this checkout, replace the installed
copy, and launch the updated app.

Options:
  --no-open  Install the app without launching it afterward.
  -h, --help Show this help.

Environment:
  MACOS_INSTALL_DIR  Destination directory (default: /Applications).

The build-related environment variables accepted by
scripts/build_macos_app.sh can also be used here.
EOF
}

is_installed_app_running() {
    pgrep -f "$INSTALLED_EXECUTABLE_PATTERN" >/dev/null 2>&1
}

stop_installed_app() {
    local pid

    while IFS= read -r pid; do
        if [ -n "$pid" ]; then
            kill -TERM "$pid" || true
        fi
    done < <(pgrep -f "$INSTALLED_EXECUTABLE_PATTERN" 2>/dev/null || true)
}

cleanup() {
    local status=$?
    trap - EXIT

    if [ -n "$BACKUP_APP" ] && [ -e "$BACKUP_APP" ] && [ ! -e "$DESTINATION" ]; then
        echo "Restoring the previously installed app after an interrupted update." >&2
        if ! mv "$BACKUP_APP" "$DESTINATION"; then
            echo "Automatic restore failed; the previous app remains at $BACKUP_APP" >&2
            WORK_DIR=""
            status=1
        fi
    fi

    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi

    exit "$status"
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-open)
            OPEN_AFTER_INSTALL=0
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
    shift
done

if [ "$(uname -s)" != "Darwin" ]; then
    echo "This updater only runs on macOS." >&2
    exit 1
fi

case "$INSTALL_DIR" in
    /) ;;
    */) INSTALL_DIR=${INSTALL_DIR%/} ;;
esac

if [ ! -d "$INSTALL_DIR" ]; then
    echo "Install directory does not exist: $INSTALL_DIR" >&2
    exit 1
fi

if [ ! -w "$INSTALL_DIR" ]; then
    echo "Install directory is not writable: $INSTALL_DIR" >&2
    echo "Use a writable directory, for example:" >&2
    echo "  MACOS_INSTALL_DIR=\"\$HOME/Applications\" ./update_app.sh" >&2
    exit 1
fi

DESTINATION="$INSTALL_DIR/$APP_NAME"
INSTALLED_EXECUTABLE="$DESTINATION/Contents/MacOS/MacDevCleanApp"
ESCAPED_EXECUTABLE=$(printf '%s\n' "$INSTALLED_EXECUTABLE" | sed 's/[][(){}.^$*+?|\\]/\\&/g')
INSTALLED_EXECUTABLE_PATTERN="^${ESCAPED_EXECUTABLE}([[:space:]]|$)"

echo "Building the latest app from $ROOT..."
"$ROOT/scripts/build_macos_app.sh"

if [ ! -d "$SOURCE_APP" ]; then
    echo "Build completed without producing $SOURCE_APP" >&2
    exit 1
fi

codesign --verify --deep --strict "$SOURCE_APP"

if ! WORK_DIR=$(mktemp -d "$INSTALL_DIR/.mac-dev-clean-update.XXXXXX"); then
    echo "Could not create a temporary update directory in $INSTALL_DIR" >&2
    exit 1
fi

STAGED_APP="$WORK_DIR/$APP_NAME"
BACKUP_APP="$WORK_DIR/previous-$APP_NAME"

ditto "$SOURCE_APP" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

if [ -e "$DESTINATION" ] && is_installed_app_running; then
    echo "Closing the installed app before updating it..."
    stop_installed_app

    for _ in {1..20}; do
        if ! is_installed_app_running; then
            break
        fi
        sleep 0.25
    done

    if is_installed_app_running; then
        echo "mac-dev-clean is still running. Quit it and run the updater again." >&2
        exit 1
    fi
fi

if [ -e "$DESTINATION" ]; then
    mv "$DESTINATION" "$BACKUP_APP"
fi

mv "$STAGED_APP" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DESTINATION/Contents/Info.plist")
echo "Installed mac-dev-clean $VERSION at $DESTINATION"

if [ "$OPEN_AFTER_INSTALL" -eq 1 ]; then
    open "$DESTINATION"
    echo "Launched the updated app."
fi
