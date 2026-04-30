#!/bin/bash
# ============================================================
# PIJS Binary Update Script
# Downloads the latest binary release and adds it to PATH
# Does not touch chain data or genesis config
# ============================================================

set -euo pipefail

# ==================== Configuration ====================
GITHUB_REPO="PIJSChain/pijs"
LATEST_RELEASE_API="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
DEFAULT_INSTALL_DIR="$HOME/pijs-node"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==================== Utility Functions ====================

print_banner() {
    echo -e "${BLUE}"
    echo "============================================================"
    echo "    PIJS Binary Update Script"
    echo "    Automatically updates the latest geth / bootnode tools"
    echo "============================================================"
    echo -e "${NC}"
}

print_step() {
    echo -e "\n${GREEN}[Step $1]${NC} $2"
    echo "------------------------------------------------------------"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

# Validate that a file is a complete gzip archive (guards against truncated downloads or HTML error pages)
# Usage: verify_gzip_archive <path> [min_bytes]
verify_gzip_archive() {
    local path="$1"
    local min_size="${2:-1048576}"

    if [ ! -f "$path" ]; then
        print_error "Downloaded file not found: $path"
        return 1
    fi

    local size
    size=$(wc -c < "$path" 2>/dev/null | tr -d ' ')
    if [ -z "$size" ] || [ "$size" -lt "$min_size" ]; then
        print_error "Downloaded file too small (${size:-0} bytes, expected >= ${min_size}), likely truncated"
        return 1
    fi

    local magic
    magic=$(head -c 2 "$path" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
    if [ "$magic" != "1f8b" ]; then
        print_error "Not a valid gzip archive (magic=${magic:-unknown}), download may have been truncated or redirected to an HTML page"
        return 1
    fi

    return 0
}

check_command() {
    command -v "$1" >/dev/null 2>&1
}

expand_path() {
    local path="$1"
    echo "${path/#\~/$HOME}"
}

download_file() {
    local url="$1"
    local output="$2"

    if check_command curl; then
        curl -fsSL "$url" -o "$output"
    elif check_command wget; then
        wget -q "$url" -O "$output"
    else
        print_error "Neither curl nor wget was found"
        exit 1
    fi
}

download_text() {
    local url="$1"

    if check_command curl; then
        curl -fsSL "$url"
    elif check_command wget; then
        wget -qO- "$url"
    else
        print_error "Neither curl nor wget was found"
        exit 1
    fi
}

# ==================== Main Workflow ====================

detect_platform() {
    local os arch
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)

    case "$os" in
        linux)
            os="linux"
            ;;
        darwin)
            os="darwin"
            ;;
        *)
            print_error "Unsupported operating system: $os"
            exit 1
            ;;
    esac

    case "$arch" in
        x86_64|amd64)
            arch="amd64"
            ;;
        aarch64|arm64)
            arch="arm64"
            ;;
        *)
            print_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac

    PLATFORM="${os}-${arch}"
    print_info "Detected platform: $PLATFORM"
}

fetch_latest_version() {
    print_step "1" "Checking the latest release"

    local response
    response=$(download_text "$LATEST_RELEASE_API")
    LATEST_VERSION=$(printf '%s' "$response" | tr -d '\n' | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    if [ -z "$LATEST_VERSION" ]; then
        print_error "Failed to resolve latest release tag"
        exit 1
    fi

    GITHUB_RELEASE="https://github.com/${GITHUB_REPO}/releases/download/${LATEST_VERSION}"
    print_success "Latest version: $LATEST_VERSION"
}

backup_binaries() {
    print_step "2" "Backing up existing binaries"

    local bin_dir="$INSTALL_DIR/bin"
    local backup_dir="$INSTALL_DIR/backup/binaries-$(date +%Y%m%d%H%M%S)"
    local found=0

    mkdir -p "$INSTALL_DIR/bin"

    for binary in geth bootnode abigen clef evm rlpdump devp2p ethkey p2psim; do
        if [ -f "$bin_dir/$binary" ]; then
            if [ $found -eq 0 ]; then
                mkdir -p "$backup_dir"
                found=1
            fi
            cp "$bin_dir/$binary" "$backup_dir/$binary"
        fi
    done

    if [ $found -eq 1 ]; then
        print_success "Backed up to: $backup_dir"
    else
        print_info "No existing binaries found to back up"
    fi
}

install_latest_binaries() {
    print_step "3" "Downloading and installing the latest binaries"

    local archive_name="geth-${LATEST_VERSION}-${PLATFORM}.tar.gz"
    local download_url="${GITHUB_RELEASE}/${archive_name}"
    local tmp_dir
    local installed=0

    tmp_dir=$(mktemp -d)
    trap "rm -rf '$tmp_dir'" EXIT

    print_info "Download URL: $download_url"
    download_file "$download_url" "$tmp_dir/$archive_name"

    # Verify download integrity (size + gzip magic)
    if ! verify_gzip_archive "$tmp_dir/$archive_name"; then
        print_error "Please check your network and retry, or download manually: $download_url"
        exit 1
    fi

    if ! tar -xzf "$tmp_dir/$archive_name" -C "$tmp_dir"; then
        print_error "Extraction failed, archive may be corrupted"
        exit 1
    fi
    mkdir -p "$INSTALL_DIR/bin"

    for binary in geth bootnode abigen clef evm rlpdump devp2p ethkey p2psim; do
        if [ -f "$tmp_dir/$binary" ]; then
            mv "$tmp_dir/$binary" "$INSTALL_DIR/bin/$binary"
            chmod +x "$INSTALL_DIR/bin/$binary"
            installed=1
            print_info "Updated: $binary"
        fi
    done

    if [ $installed -eq 0 ]; then
        print_error "No installable binaries were found in the archive"
        exit 1
    fi

    # Verify geth runs
    if [ ! -x "$INSTALL_DIR/bin/geth" ]; then
        print_error "Extraction completed but geth was not found; archive contents are abnormal"
        exit 1
    fi
    if ! "$INSTALL_DIR/bin/geth" version >/dev/null 2>&1; then
        print_error "geth failed to run — binary may be corrupted"
        "$INSTALL_DIR/bin/geth" version || true
        exit 1
    fi

    CURRENT_VERSION=$("$INSTALL_DIR/bin/geth" version 2>/dev/null | awk '/Version:/ {print $2; exit}')
    CURRENT_VERSION=${CURRENT_VERSION:-}

    if [ -n "$CURRENT_VERSION" ] && [ "$CURRENT_VERSION" != "${LATEST_VERSION#v}" ] && [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
        print_success "Binary update complete, release tag: $LATEST_VERSION, geth version: $CURRENT_VERSION"
    elif [ -n "$CURRENT_VERSION" ]; then
        print_success "Binary update complete, current version: $CURRENT_VERSION"
    else
        print_success "Binary update complete, release tag: $LATEST_VERSION"
    fi
}

detect_shell_rc() {
    local shell_name
    shell_name=$(basename "${SHELL:-}")

    case "$shell_name" in
        zsh)
            echo "$HOME/.zshrc"
            ;;
        bash)
            if [ -f "$HOME/.bashrc" ]; then
                echo "$HOME/.bashrc"
            else
                echo "$HOME/.bash_profile"
            fi
            ;;
        *)
            if [ -f "$HOME/.zshrc" ]; then
                echo "$HOME/.zshrc"
            elif [ -f "$HOME/.bashrc" ]; then
                echo "$HOME/.bashrc"
            elif [ -f "$HOME/.bash_profile" ]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.profile"
            fi
            ;;
    esac
}

configure_path() {
    print_step "4" "Updating PATH"

    local bin_dir="$INSTALL_DIR/bin"
    local shell_rc
    local path_line="export PATH=\"$bin_dir:\$PATH\""

    export PATH="$bin_dir:$PATH"
    shell_rc=$(detect_shell_rc)
    mkdir -p "$(dirname "$shell_rc")"
    touch "$shell_rc"

    if grep -Fqs "$bin_dir" "$shell_rc"; then
        print_info "PATH entry already exists in $shell_rc"
    else
        {
            echo ""
            echo "# PIJS Node"
            echo "$path_line"
        } >> "$shell_rc"
        print_success "PATH entry added to: $shell_rc"
    fi
}

show_completion() {
    local shell_rc="$1"

    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}        Binary Update Complete!${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "${BLUE}Summary:${NC}"
    echo "  Latest version: $LATEST_VERSION"
    echo "  Install directory: $INSTALL_DIR"
    echo "  Binary directory: $INSTALL_DIR/bin"
    echo "  Chain data: unchanged"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Reload your shell config: source $shell_rc"
    echo "  2. Verify the version: geth version"
    echo "  3. If this release includes a hard fork, use upgrade-node.sh instead"
    echo ""
}

main() {
    print_banner

    print_warn "This script only updates binaries and PATH. It does not update genesis.json or re-run init."
    echo ""
    read -r -p "Enter the binary install directory [$DEFAULT_INSTALL_DIR]: " INSTALL_DIR
    INSTALL_DIR=$(expand_path "${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}")

    mkdir -p "$INSTALL_DIR"
    print_info "Target directory: $INSTALL_DIR"

    detect_platform
    fetch_latest_version
    backup_binaries
    install_latest_binaries
    configure_path

    local shell_rc
    shell_rc=$(detect_shell_rc)
    show_completion "$shell_rc"
}

main "$@"
