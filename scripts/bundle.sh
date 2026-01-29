#!/bin/bash
set -euo pipefail

# Build script that creates a proper .app bundle from the Swift executable
# This is necessary because UNUserNotificationCenter requires an app bundle

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
RESOURCES_DIR="$PROJECT_DIR/Sources/growlrrr/Resources"

# Configuration
APP_NAME="growlrrr"
BUNDLE_ID="com.moltenbits.growlrrr"
BUILD_CONFIG="${1:-release}"

echo "Building $APP_NAME ($BUILD_CONFIG)..."

# Build the executable
cd "$PROJECT_DIR"
swift build -c "$BUILD_CONFIG"

# Create app bundle structure
APP_BUNDLE="$BUILD_DIR/$BUILD_CONFIG/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DEST="$CONTENTS_DIR/Resources"

echo "Creating app bundle at $APP_BUNDLE..."

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DEST"

# Copy executable
cp "$BUILD_DIR/$BUILD_CONFIG/$APP_NAME" "$MACOS_DIR/$APP_NAME"

# Copy Info.plist
cp "$RESOURCES_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

# Copy app icon if it exists
if [[ -f "$RESOURCES_DIR/AppIcon.icns" ]]; then
    cp "$RESOURCES_DIR/AppIcon.icns" "$RESOURCES_DEST/AppIcon.icns"
fi

# Generate shell completion scripts
COMPLETIONS_DIR="$RESOURCES_DEST/completions"
mkdir -p "$COMPLETIONS_DIR"
"$MACOS_DIR/$APP_NAME" --generate-completion-script zsh > "$COMPLETIONS_DIR/_growlrrr"
"$MACOS_DIR/$APP_NAME" --generate-completion-script bash > "$COMPLETIONS_DIR/growlrrr.bash"
"$MACOS_DIR/$APP_NAME" --generate-completion-script fish > "$COMPLETIONS_DIR/growlrrr.fish"

# Create PkgInfo
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Sign the app (ad-hoc signing for local use)
echo "Signing app bundle..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "App bundle created: $APP_BUNDLE"

# Create CLI wrapper script
WRAPPER_SCRIPT="$BUILD_DIR/$BUILD_CONFIG/$APP_NAME-cli"
cat > "$WRAPPER_SCRIPT" << 'EOF'
#!/bin/bash
# CLI wrapper for growlrrr
# This script invokes the app bundle, which is required for UserNotifications

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BUNDLE="$SCRIPT_DIR/growlrrr.app"

if [[ -d "$APP_BUNDLE" ]]; then
    exec "$APP_BUNDLE/Contents/MacOS/growlrrr" "$@"
else
    echo "Error: growlrrr.app not found at $APP_BUNDLE" >&2
    exit 1
fi
EOF
chmod +x "$WRAPPER_SCRIPT"

echo "CLI wrapper created: $WRAPPER_SCRIPT"
echo ""
echo "To test:"
echo "  $APP_BUNDLE/Contents/MacOS/growlrrr \"Hello from growlrrr\""
echo ""
echo "To install:"
echo "  sudo cp -r $APP_BUNDLE /Applications/"
echo "  sudo ln -sf /Applications/growlrrr.app/Contents/MacOS/growlrrr /usr/local/bin/growlrrr"
