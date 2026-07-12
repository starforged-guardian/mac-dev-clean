#!/bin/bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
PACKAGE="$ROOT/macos"
CONFIGURATION=${CONFIGURATION:-release}
DEPLOYMENT_TARGET=${MACOS_DEPLOYMENT_TARGET:-14.0}
ARCHS_VALUE=${MACOS_ARCHS:-$(uname -m)}
SIGNING_IDENTITY=${MACOS_SIGNING_IDENTITY:--}
APP="$ROOT/dist/mac-dev-clean.app"
CONTENTS="$APP/Contents"
RESOURCES="$CONTENTS/Resources"
VERSION=${MACOS_VERSION:-$(sed -n 's/^version = "\([0-9][0-9.]*\)"/\1/p' "$ROOT/pyproject.toml" | head -1)}
BUILD_NUMBER=${MACOS_BUILD_NUMBER:-$VERSION}
BUNDLE_IDENTIFIER=${MACOS_BUNDLE_IDENTIFIER:-com.ravenvector.mac-dev-clean}

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Could not determine a valid X.Y.Z app version." >&2
    exit 1
fi

read -r -a ARCHS <<< "$ARCHS_VALUE"
if [ "${#ARCHS[@]}" -eq 0 ]; then
    echo "MACOS_ARCHS must contain at least one architecture." >&2
    exit 1
fi

BINARIES=()
for ARCH in "${ARCHS[@]}"; do
    case "$ARCH" in
        arm64|x86_64) ;;
        *)
            echo "Unsupported macOS architecture: $ARCH" >&2
            exit 1
            ;;
    esac
    TRIPLE="${ARCH}-apple-macosx${DEPLOYMENT_TARGET}"
    swift build --package-path "$PACKAGE" -c "$CONFIGURATION" --triple "$TRIPLE"
    BIN_DIR=$(swift build --package-path "$PACKAGE" -c "$CONFIGURATION" --triple "$TRIPLE" --show-bin-path)
    BINARIES+=("$BIN_DIR/MacDevCleanApp")
done

mkdir -p "$CONTENTS/MacOS" "$RESOURCES/python/mac_dev_clean"
if [ "${#BINARIES[@]}" -eq 1 ]; then
    cp "${BINARIES[0]}" "$CONTENTS/MacOS/MacDevCleanApp"
else
    lipo -create "${BINARIES[@]}" -output "$CONTENTS/MacOS/MacDevCleanApp"
fi
cp "$PACKAGE/AppBundle/Info.plist" "$CONTENTS/Info.plist"
cp "$PACKAGE/AppBundle/AppIcon.icns" "$RESOURCES/AppIcon.icns"
cp "$ROOT/assets/mac-dev-clean-logo.png" "$RESOURCES/mac-dev-clean-logo.png"
cp "$ROOT/raven_vector_logos/raven-vector-dark.png" "$RESOURCES/raven-vector-dark.png"
cp "$ROOT/raven_vector_logos/raven-vector-dark-trans.png" "$RESOURCES/raven-vector-dark-trans.png"
cp "$ROOT/LICENSE" "$RESOURCES/LICENSE"
cp "$ROOT/BRANDING.md" "$RESOURCES/BRANDING.md"
cp "$ROOT"/src/mac_dev_clean/*.py "$RESOURCES/python/mac_dev_clean/"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$CONTENTS/Info.plist"

chmod +x "$CONTENTS/MacOS/MacDevCleanApp"
if [ "$SIGNING_IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
    echo "Signed ad hoc for local use."
else
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$SIGNING_IDENTITY" \
        "$APP"
    echo "Signed with $SIGNING_IDENTITY"
fi

codesign --verify --deep --strict --verbose=2 "$APP"

echo "Built $APP"
echo "Architectures: $(lipo -archs "$CONTENTS/MacOS/MacDevCleanApp")"
echo "Version: $VERSION ($BUILD_NUMBER)"
echo "Bundle identifier: $BUNDLE_IDENTIFIER"
