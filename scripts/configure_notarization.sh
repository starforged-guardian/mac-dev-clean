#!/bin/bash
set -euo pipefail

PROFILE=${NOTARYTOOL_PROFILE:-mac-dev-clean-notary}
APPLE_ID=${NOTARY_APPLE_ID:-}
TEAM_ID=${APPLE_TEAM_ID:-}

if [ -z "$APPLE_ID" ]; then
    read -r -p "Apple Account email: " APPLE_ID
fi
if [ -z "$TEAM_ID" ]; then
    read -r -p "Apple Developer Team ID: " TEAM_ID
fi

if [ -z "$APPLE_ID" ] || [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "An Apple Account email and 10-character Team ID are required." >&2
    exit 1
fi

echo "notarytool will securely prompt for an app-specific password."
echo "The password will be stored in your Keychain under profile '$PROFILE'."
xcrun notarytool store-credentials "$PROFILE" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID"

echo
echo "Notarization credentials are ready."
IDENTITIES=$(security find-identity -v -p codesigning)
if ! grep -q 'Developer ID Application:' <<< "$IDENTITIES"; then
    echo "Next: install a Developer ID Application certificate and its private key."
fi
echo "Then run ./scripts/notarize_macos_app.sh"
