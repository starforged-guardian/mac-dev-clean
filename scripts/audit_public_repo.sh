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
    echo "Refusing publication because sensitive/generated filenames are visible:" >&2
    echo "$UNSAFE_FILES" >&2
    exit 1
fi

echo "Checking for machine-specific absolute home paths..."
if rg -n --pcre2 '/Users/(?!test(?:/|$)|example(?:/|$)|<local-user>)' \
    --glob '!scripts/audit_public_repo.sh' \
    --glob '!*.png' \
    --glob '!*.icns' \
    .; then
    echo "Replace or redact the machine-specific paths above before publishing." >&2
    exit 1
fi

git diff --check

if command -v gitleaks >/dev/null 2>&1; then
    echo "Scanning candidate files with Gitleaks..."
    gitleaks detect --source . --no-git --redact --no-banner
    echo "Scanning Git history with Gitleaks..."
    gitleaks detect --source . --redact --no-banner
else
    echo "Gitleaks is not installed; filename, path, and diff checks passed."
fi

echo "Public repository audit passed."
