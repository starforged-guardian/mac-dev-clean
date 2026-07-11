#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
APP="$ROOT/dist/mac-dev-clean.app"
BINARY="$APP/Contents/MacOS/MacDevCleanApp"
NEEDS_BUILD=0

if [ ! -x "$BINARY" ]; then
    NEEDS_BUILD=1
elif find \
    "$ROOT/macos" \
    "$ROOT/src/mac_dev_clean" \
    "$ROOT/assets/mac-dev-clean-logo.png" \
    "$ROOT/raven_vector_logos" \
    "$ROOT/scripts/build_macos_app.sh" \
    -type f -newer "$BINARY" -print -quit | grep -q .; then
    NEEDS_BUILD=1
fi

if [ "$NEEDS_BUILD" -eq 1 ]; then
    "$ROOT/scripts/build_macos_app.sh"
fi

exec open "$APP"
