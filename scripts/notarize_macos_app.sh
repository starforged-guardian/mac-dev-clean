#!/bin/bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
PROFILE=${NOTARYTOOL_PROFILE:-mac-dev-clean-notary}
TIMEOUT=${NOTARY_TIMEOUT:-60m}
IDENTITY=${MACOS_SIGNING_IDENTITY:-}
VERSION=${MACOS_VERSION:-$(sed -n 's/^version = "\([0-9][0-9.]*\)"/\1/p' "$ROOT/pyproject.toml" | head -1)}
APP="$ROOT/dist/mac-dev-clean.app"
SUBMISSION="$ROOT/dist/mac-dev-clean-$VERSION-notarization.zip"
FINAL_ARCHIVE="$ROOT/dist/mac-dev-clean-$VERSION-macos.zip"

if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
        | sed -n '1p')
fi

if [[ "$IDENTITY" != "Developer ID Application:"* ]]; then
    echo "No Developer ID Application certificate with a private key was found." >&2
    echo "Install it in Keychain Access, or set MACOS_SIGNING_IDENTITY explicitly." >&2
    exit 1
fi

if ! xcrun notarytool history \
    --keychain-profile "$PROFILE" \
    --output-format json >/dev/null; then
    echo "Could not authenticate with notarytool Keychain profile '$PROFILE'." >&2
    echo "Run ./scripts/configure_notarization.sh first." >&2
    exit 1
fi

echo "Building a universal Developer ID release..."
MACOS_ARCHS="${MACOS_ARCHS:-arm64 x86_64}" \
MACOS_SIGNING_IDENTITY="$IDENTITY" \
MACOS_VERSION="$VERSION" \
    "$ROOT/scripts/build_macos_app.sh"

rm -f "$SUBMISSION" "$FINAL_ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$SUBMISSION"

echo
echo "Submitting $SUBMISSION to Apple's notary service..."
set +e
RESULT=$(xcrun notarytool submit "$SUBMISSION" \
    --keychain-profile "$PROFILE" \
    --wait \
    --timeout "$TIMEOUT" \
    --output-format json)
SUBMIT_STATUS=$?
set -e
printf '%s\n' "$RESULT"

STATUS=$(printf '%s' "$RESULT" | plutil -extract status raw -o - -- - 2>/dev/null || true)
SUBMISSION_ID=$(printf '%s' "$RESULT" | plutil -extract id raw -o - -- - 2>/dev/null || true)
if [ "$SUBMIT_STATUS" -ne 0 ] || [ "$STATUS" != "Accepted" ]; then
    echo "Notarization was not accepted." >&2
    if [ -n "$SUBMISSION_ID" ]; then
        LOG="$ROOT/dist/notary-log-$SUBMISSION_ID.json"
        xcrun notarytool log "$SUBMISSION_ID" \
            --keychain-profile "$PROFILE" \
            "$LOG" || true
        echo "Notary log: $LOG" >&2
    fi
    exit 1
fi

echo
echo "Stapling and validating the notarization ticket..."
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=4 "$APP"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$FINAL_ARCHIVE"
rm -f "$SUBMISSION"

echo
echo "Notarized release: $FINAL_ARCHIVE"
shasum -a 256 "$FINAL_ARCHIVE"
