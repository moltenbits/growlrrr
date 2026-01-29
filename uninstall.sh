#!/bin/bash
set -euo pipefail

# growlrrr uninstaller

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

# Check if we need sudo for a path
needs_sudo() {
    local path="$1"
    [[ -e "$path" ]] && [[ ! -w "$path" ]]
}

# Run command with sudo if needed
run_cmd() {
    local path="$1"
    shift
    if needs_sudo "$path"; then
        sudo "$@"
    else
        "$@"
    fi
}

main() {
    echo ""
    echo -e "${BOLD}growlrrr uninstaller${NC}"
    echo ""

    local found=0

    # Remove app bundle from common locations
    for app_dir in "/Applications" "$HOME/Applications"; do
        if [[ -d "$app_dir/growlrrr.app" ]]; then
            info "Removing $app_dir/growlrrr.app"
            run_cmd "$app_dir/growlrrr.app" rm -rf "$app_dir/growlrrr.app"
            found=1
        fi
    done

    # Remove symlinks from common locations
    for bin_dir in "/usr/local/bin" "$HOME/bin" "$HOME/.local/bin"; do
        for cmd in growlrrr grrr; do
            if [[ -L "$bin_dir/$cmd" ]]; then
                info "Removing $bin_dir/$cmd"
                run_cmd "$bin_dir/$cmd" rm -f "$bin_dir/$cmd"
                found=1
            fi
        done
    done

    # Remove shell completions
    local completions_removed=0

    # Zsh
    local zsh_comp="${ZDOTDIR:-$HOME}/.zsh/completions/_growlrrr"
    if [[ -f "$zsh_comp" ]]; then
        rm -f "$zsh_comp"
        completions_removed=1
    fi

    # Bash
    local bash_comp="$HOME/.bash_completion.d/growlrrr.bash"
    if [[ -f "$bash_comp" ]]; then
        rm -f "$bash_comp"
        completions_removed=1
    fi

    # Fish
    local fish_comp="$HOME/.config/fish/completions/growlrrr.fish"
    if [[ -f "$fish_comp" ]]; then
        rm -f "$fish_comp"
        completions_removed=1
    fi

    if [[ "$completions_removed" == "1" ]]; then
        info "Removed shell completions"
    fi

    # Ask about custom apps
    CUSTOM_APPS_DIR="$HOME/.growlrrr"
    if [[ -d "$CUSTOM_APPS_DIR" ]]; then
        echo ""
        echo "Custom apps directory found: $CUSTOM_APPS_DIR"
        read -p "Remove custom apps and settings? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            info "Removing $CUSTOM_APPS_DIR"
            rm -rf "$CUSTOM_APPS_DIR"
        else
            warn "Kept $CUSTOM_APPS_DIR"
        fi
    fi

    echo ""
    if [[ "$found" == "1" ]]; then
        success "growlrrr has been uninstalled"
    else
        warn "growlrrr installation not found"
    fi

    echo ""
    echo "Note: Notification settings in System Settings may persist until you log out."
    echo "To clear them immediately, run: killall NotificationCenter"
    echo ""
}

main "$@"
