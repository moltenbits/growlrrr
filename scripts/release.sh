#!/bin/bash
set -euo pipefail

# Release script for growlrrr
# Creates a distributable archive of the app bundle

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
DIST_DIR="$PROJECT_DIR/dist"

# Use the provided version (CI passes the tag), or derive one from git
VERSION="${1:-$(git -C "$PROJECT_DIR" describe --tags --always --dirty 2>/dev/null | sed 's/^v//')}"

if [[ -z "$VERSION" ]]; then
    echo "Error: Could not determine version"
    exit 1
fi

echo "Building growlrrr v$VERSION for release..."

# Build release bundle (signs with Developer ID if TEAM_NAME/TEAM_ID env vars set).
# bundle.sh stamps $VERSION into the bundle's Info.plist, which is where the
# binary's --version comes from.
VERSION="$VERSION" "$SCRIPT_DIR/bundle.sh" release

APP_BUNDLE="$BUILD_DIR/release/growlrrr.app"

# Notarize if credentials are available, otherwise skip (e.g. for source builds).
if [[ -n "${TEAM_ID:-}" && -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    echo ""
    echo "Notarizing app bundle..."
    ZIP_FOR_NOTARY="$BUILD_DIR/release/growlrrr-notary.zip"

    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

    rm -f "$ZIP_FOR_NOTARY"
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_FOR_NOTARY"

    xcrun notarytool submit "$ZIP_FOR_NOTARY" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait

    xcrun stapler staple "$APP_BUNDLE"
    xcrun stapler validate "$APP_BUNDLE"

    rm -f "$ZIP_FOR_NOTARY"
    echo "Notarization complete."
else
    echo "Skipping notarization (APPLE_ID / APPLE_APP_PASSWORD / TEAM_ID not set)."
fi

# Create dist directory
mkdir -p "$DIST_DIR"

# Create archive
ARCHIVE_NAME="growlrrr-${VERSION}-macos.tar.gz"
ARCHIVE_PATH="$DIST_DIR/$ARCHIVE_NAME"

echo ""
echo "Creating archive: $ARCHIVE_NAME"

# Create tarball from the release directory
cd "$BUILD_DIR/release"
tar -czf "$ARCHIVE_PATH" growlrrr.app

# Calculate SHA256
SHA256=$(shasum -a 256 "$ARCHIVE_PATH" | cut -d' ' -f1)

echo ""
echo "=== Release Build Complete ==="
echo "Archive: $ARCHIVE_PATH"
echo "SHA256:  $SHA256"
echo ""
echo "To create a GitHub release:"
echo "  gh release create v$VERSION $ARCHIVE_PATH --title \"v$VERSION\" --notes \"Release v$VERSION\""
echo ""
echo "Homebrew formula URL (after release):"
echo "  https://github.com/moltenbits/growlrrr/releases/download/v$VERSION/$ARCHIVE_NAME"
echo ""

# Output for CI
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "archive_path=$ARCHIVE_PATH" >> "$GITHUB_OUTPUT"
    echo "archive_name=$ARCHIVE_NAME" >> "$GITHUB_OUTPUT"
    echo "sha256=$SHA256" >> "$GITHUB_OUTPUT"
    echo "version=$VERSION" >> "$GITHUB_OUTPUT"
fi
