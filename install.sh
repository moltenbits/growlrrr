#!/bin/bash
set -euo pipefail

# growlrrr installer
# Usage: curl -fsSL https://raw.githubusercontent.com/moltenbits/growlrrr/main/install.sh | bash
#
# Options (via environment variables):
#   GROWLRRR_VERSION  - Install specific version (default: latest)
#   GROWLRRR_INSTALL_DIR - App installation directory (default: /Applications or ~/Applications)
#   GROWLRRR_BIN_DIR  - Binary symlink directory (default: /usr/local/bin or ~/bin)
#   GROWLRRR_NO_MODIFY_PATH - Set to 1 to skip PATH modification

REPO="moltenbits/growlrrr"
APP_NAME="growlrrr"

# Colors (disabled if not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

info() {
    echo -e "${BLUE}==>${NC} ${BOLD}$1${NC}"
}

success() {
    echo -e "${GREEN}==>${NC} ${BOLD}$1${NC}"
}

warn() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

error() {
    echo -e "${RED}Error:${NC} $1" >&2
    exit 1
}

# Check for required commands
check_dependencies() {
    local missing=()
    for cmd in curl tar; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required commands: ${missing[*]}"
    fi
}

# Get the latest release version from GitHub
get_latest_version() {
    local version
    version=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    if [[ -z "$version" ]]; then
        error "Failed to fetch latest version from GitHub"
    fi
    echo "$version"
}

# Detect architecture
get_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            echo "x86_64"
            ;;
        arm64|aarch64)
            echo "arm64"
            ;;
        *)
            error "Unsupported architecture: $arch"
            ;;
    esac
}

# Check if we can write to a directory (with sudo if needed)
can_write() {
    local dir="$1"
    if [[ -w "$dir" ]] || [[ -w "$(dirname "$dir")" ]]; then
        return 0
    fi
    return 1
}

# Determine installation directories
determine_install_dirs() {
    # App directory
    if [[ -n "${GROWLRRR_INSTALL_DIR:-}" ]]; then
        INSTALL_DIR="$GROWLRRR_INSTALL_DIR"
    elif can_write "/Applications"; then
        INSTALL_DIR="/Applications"
    elif [[ -d "$HOME/Applications" ]] || can_write "$HOME"; then
        INSTALL_DIR="$HOME/Applications"
    else
        INSTALL_DIR="/Applications"
        USE_SUDO=1
    fi

    # Binary directory
    if [[ -n "${GROWLRRR_BIN_DIR:-}" ]]; then
        BIN_DIR="$GROWLRRR_BIN_DIR"
    elif can_write "/usr/local/bin"; then
        BIN_DIR="/usr/local/bin"
    elif [[ -d "$HOME/bin" ]] || [[ -d "$HOME/.local/bin" ]]; then
        BIN_DIR="${HOME}/.local/bin"
    else
        BIN_DIR="/usr/local/bin"
        USE_SUDO=1
    fi
}

# Create directory if it doesn't exist
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        if [[ "${USE_SUDO:-}" == "1" ]]; then
            sudo mkdir -p "$dir"
        else
            mkdir -p "$dir"
        fi
    fi
}

# Run a command with sudo if needed
run_cmd() {
    if [[ "${USE_SUDO:-}" == "1" ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

# Install shell completions
install_completions() {
    local completions_src="$INSTALL_DIR/growlrrr.app/Contents/Resources/completions"

    if [[ ! -d "$completions_src" ]]; then
        warn "Completions not found in app bundle"
        return
    fi

    # Zsh completions
    if command -v zsh &>/dev/null; then
        local zsh_completions_dir="${ZDOTDIR:-$HOME}/.zsh/completions"
        if [[ -d "$zsh_completions_dir" ]] || mkdir -p "$zsh_completions_dir" 2>/dev/null; then
            cp "$completions_src/_growlrrr" "$zsh_completions_dir/" 2>/dev/null && \
                info "Installed zsh completions to $zsh_completions_dir"
        fi
    fi

    # Bash completions
    if command -v bash &>/dev/null; then
        local bash_completions_dir="$HOME/.bash_completion.d"
        if [[ -d "$bash_completions_dir" ]] || mkdir -p "$bash_completions_dir" 2>/dev/null; then
            cp "$completions_src/growlrrr.bash" "$bash_completions_dir/" 2>/dev/null && \
                info "Installed bash completions to $bash_completions_dir"
        fi
    fi

    # Fish completions
    if command -v fish &>/dev/null; then
        local fish_completions_dir="$HOME/.config/fish/completions"
        if [[ -d "$fish_completions_dir" ]] || mkdir -p "$fish_completions_dir" 2>/dev/null; then
            cp "$completions_src/growlrrr.fish" "$fish_completions_dir/" 2>/dev/null && \
                info "Installed fish completions to $fish_completions_dir"
        fi
    fi
}

# Check if directory is in PATH
in_path() {
    local dir="$1"
    [[ ":$PATH:" == *":$dir:"* ]]
}

# Suggest PATH addition if needed
suggest_path() {
    if in_path "$BIN_DIR"; then
        return
    fi

    if [[ "${GROWLRRR_NO_MODIFY_PATH:-}" == "1" ]]; then
        warn "$BIN_DIR is not in your PATH"
        return
    fi

    echo ""
    warn "$BIN_DIR is not in your PATH"
    echo ""
    echo "Add it to your shell configuration:"
    echo ""

    local shell_name
    shell_name=$(basename "${SHELL:-bash}")

    case "$shell_name" in
        zsh)
            echo "  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc"
            echo "  source ~/.zshrc"
            ;;
        bash)
            echo "  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.bashrc"
            echo "  source ~/.bashrc"
            ;;
        fish)
            echo "  fish_add_path $BIN_DIR"
            ;;
        *)
            echo "  export PATH=\"$BIN_DIR:\$PATH\""
            ;;
    esac
}

# Main installation
main() {
    echo ""
    echo -e "${BOLD}growlrrr installer${NC}"
    echo ""

    # Check macOS
    if [[ "$(uname -s)" != "Darwin" ]]; then
        error "growlrrr only supports macOS"
    fi

    check_dependencies

    # Get version
    VERSION="${GROWLRRR_VERSION:-}"
    if [[ -z "$VERSION" ]]; then
        info "Fetching latest version..."
        VERSION=$(get_latest_version)
    fi
    info "Installing growlrrr v$VERSION"

    # Determine directories
    USE_SUDO=""
    determine_install_dirs

    if [[ "${USE_SUDO:-}" == "1" ]]; then
        info "Installation requires administrator privileges"
        sudo -v || error "Failed to obtain sudo privileges"
    fi

    # Create temp directory
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf '$TEMP_DIR'" EXIT

    # Download
    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${VERSION}/growlrrr-${VERSION}-macos.tar.gz"
    info "Downloading from $DOWNLOAD_URL"

    if ! curl -fsSL "$DOWNLOAD_URL" -o "$TEMP_DIR/growlrrr.tar.gz"; then
        error "Failed to download growlrrr v$VERSION"
    fi

    # Extract
    info "Extracting..."
    tar -xzf "$TEMP_DIR/growlrrr.tar.gz" -C "$TEMP_DIR"

    if [[ ! -d "$TEMP_DIR/growlrrr.app" ]]; then
        error "Archive does not contain growlrrr.app"
    fi

    # Install app bundle
    ensure_dir "$INSTALL_DIR"

    # Remove existing installation
    if [[ -d "$INSTALL_DIR/growlrrr.app" ]]; then
        info "Removing existing installation..."
        run_cmd rm -rf "$INSTALL_DIR/growlrrr.app"
    fi

    info "Installing to $INSTALL_DIR/growlrrr.app"
    run_cmd cp -R "$TEMP_DIR/growlrrr.app" "$INSTALL_DIR/"

    # Create symlinks
    ensure_dir "$BIN_DIR"

    info "Creating symlinks in $BIN_DIR"
    run_cmd ln -sf "$INSTALL_DIR/growlrrr.app/Contents/MacOS/growlrrr" "$BIN_DIR/growlrrr"
    run_cmd ln -sf "$INSTALL_DIR/growlrrr.app/Contents/MacOS/growlrrr" "$BIN_DIR/grrr"

    # Install completions
    install_completions

    # Update custom app bundles if they exist
    CUSTOM_APPS_DIR="$HOME/.growlrrr/apps"
    if [[ -d "$CUSTOM_APPS_DIR" ]] && [[ -n "$(ls -A "$CUSTOM_APPS_DIR" 2>/dev/null)" ]]; then
        info "Updating custom app bundles..."
        "$BIN_DIR/growlrrr" apps update 2>/dev/null || true
    fi

    # Success message
    echo ""
    success "growlrrr v$VERSION installed successfully!"
    echo ""
    echo "  App:      $INSTALL_DIR/growlrrr.app"
    echo "  Commands: $BIN_DIR/growlrrr, $BIN_DIR/grrr"
    echo ""

    # Check PATH
    suggest_path

    # Usage hint
    echo ""
    echo "Get started:"
    echo ""
    echo "  grrr \"Hello from growlrrr!\""
    echo "  grrr --title \"My App\" \"Build complete\""
    echo "  grrr --help"
    echo ""
}

main "$@"
