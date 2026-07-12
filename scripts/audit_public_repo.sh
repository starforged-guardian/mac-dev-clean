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

echo "Checking protected brand-asset declarations..."
BRAND_ASSETS=(
    "assets/mac-dev-clean-logo.png"
    "macos/AppBundle/AppIcon.icns"
    "raven_vector_logos/raven-vector-dark.png"
    "raven_vector_logos/raven-vector-dark-trans.png"
)
for ASSET in "${BRAND_ASSETS[@]}"; do
    if [ ! -f "$ASSET" ]; then
        echo "Protected brand asset is missing: $ASSET" >&2
        exit 1
    fi
    if ! grep -Fq -- "- \`$ASSET\`" BRANDING.md; then
        echo "Protected brand asset is not declared in BRANDING.md: $ASSET" >&2
        exit 1
    fi
done
if ! grep -Fq 'The Brand Assets are not part of the "Software"' LICENSE; then
    echo "LICENSE is missing the Brand Asset exclusion." >&2
    exit 1
fi
if ! grep -Fq 'All rights reserved.' BRANDING.md; then
    echo "BRANDING.md is missing the rights reservation." >&2
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
