#!/bin/bash
set -euo pipefail

# Release script for growlrrr
# Creates a distributable archive of the app bundle

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
DIST_DIR="$PROJECT_DIR/dist"

# Get version from Package.swift or use provided version
VERSION="${1:-$(grep -o 'version: "[^"]*"' "$PROJECT_DIR/Sources/growlrrr/Growlrrr.swift" | head -1 | cut -d'"' -f2)}"

if [[ -z "$VERSION" ]]; then
    echo "Error: Could not determine version"
    exit 1
fi

echo "Building growlrrr v$VERSION for release..."

# Build release bundle
"$SCRIPT_DIR/bundle.sh" release

# Create dist directory
mkdir -p "$DIST_DIR"

# Create archive
APP_BUNDLE="$BUILD_DIR/release/growlrrr.app"
ARCHIVE_NAME="growlrrr-${VERSION}-macos.tar.gz"
ARCHIVE_PATH="$DIST_DIR/$ARCHIVE_NAME"

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
