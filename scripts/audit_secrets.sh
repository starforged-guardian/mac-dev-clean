#!/bin/bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

echo "Checking public candidate filenames..."
UNSAFE_FILES=$(
    git ls-files --cached --others --exclude-standard | awk '
        /(^|\/)xcuserdata(\/|$)/ ||
        /(^|\/)\.swiftpm(\/|$)/ ||
        /\.xcuserstate$/ ||
        /\.xcarchive(\/|$)/ ||
        /\.xcresult(\/|$)/ ||
        /\.dSYM(\/|$)/ ||
        /(^|\/)notary-log-[^\/]*\.json$/ ||
        /\.(p8|p12|pem|cer|key|keychain|mobileprovision|provisionprofile)$/ ||
        (/(^|\/)\.env(\.|$)/ && $0 !~ /(^|\/)\.env\.example$/) {
            print
        }
    '
)
if [ -n "$UNSAFE_FILES" ]; then
    echo "Secret audit failed because sensitive/generated filenames are visible:" >&2
    echo "$UNSAFE_FILES" >&2
    exit 1
fi

echo "Sensitive filename audit passed."
