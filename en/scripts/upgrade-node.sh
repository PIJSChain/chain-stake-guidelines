#!/bin/bash
# ============================================================
# PIJS Consensus Node Upgrade Script
# For hard fork upgrades - updates client and chain config only
# Does NOT delete existing chain data
# ============================================================

set -e

# ==================== Configuration ====================
GITHUB_RELEASE="https://github.com/PIJSChain/pijs/releases/download/v1.25.6k"
GETH_VERSION="v1.25.6k"
GENESIS_URL="https://github.com/PIJSChain/pijs/releases/download/v1.25.6k/genesis.json"

# Default directory
DEFAULT_INSTALL_DIR="$HOME/pijs-node"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==================== Utility Functions ====================

print_banner() {
    echo -e "${BLUE}"
    echo "============================================================"
    echo "    PIJS Consensus Node Upgrade Script"
    echo "    Target Version: $GETH_VERSION"
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

# Detect OS and architecture
detect_platform() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case "$OS" in
        linux)
            OS="linux"
            ;;
        darwin)
            OS="darwin"
            ;;
        *)
            print_error "Unsupported operating system: $OS"
            exit 1
            ;;
    esac

    case "$ARCH" in
        x86_64|amd64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            print_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    PLATFORM="${OS}-${ARCH}"
    print_info "Detected platform: $PLATFORM"
}

# Check if node is running
check_node_running() {
    if pgrep -f "geth.*--datadir.*$INSTALL_DIR" > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Stop running node
stop_node() {
    print_step "1" "Checking node status"

    if check_node_running; then
        print_warn "Node is currently running, stopping..."
        pkill -f "geth.*--datadir.*$INSTALL_DIR" || true
        sleep 3

        if check_node_running; then
            print_error "Failed to stop node, please stop it manually first"
            exit 1
        fi
        print_success "Node stopped"
    else
        print_info "Node is not running"
    fi
}

# Backup current client
backup_client() {
    print_step "2" "Backing up current client"

    local backup_dir="$INSTALL_DIR/backup"
    mkdir -p "$backup_dir"

    if [ -f "$INSTALL_DIR/bin/geth" ]; then
        local backup_name="geth.backup.$(date +%Y%m%d%H%M%S)"
        cp "$INSTALL_DIR/bin/geth" "$backup_dir/$backup_name"
        print_success "Current client backed up to: $backup_dir/$backup_name"
    else
        print_info "No existing client to backup"
    fi
}

# Download new client
download_client() {
    print_step "3" "Downloading new client ($GETH_VERSION)"

    local geth_filename="geth-${PLATFORM}"
    local download_url="${GITHUB_RELEASE}/${geth_filename}"

    print_info "Downloading from: $download_url"

    cd "$INSTALL_DIR/bin"

    # Remove old file
    rm -f geth geth-*

    if command -v curl &> /dev/null; then
        curl -L -o geth "$download_url" --progress-bar
    elif command -v wget &> /dev/null; then
        wget -O geth "$download_url" --show-progress
    else
        print_error "Neither curl nor wget found"
        exit 1
    fi

    chmod +x geth

    # Verify download
    if [ ! -f "geth" ] || [ ! -s "geth" ]; then
        print_error "Download failed or file is empty"
        exit 1
    fi

    # Show version
    local version=$(./geth version 2>/dev/null | grep "Version:" | head -1 || echo "Unknown")
    print_success "New client downloaded: $version"
}

# Download genesis file
download_genesis() {
    print_step "4" "Downloading genesis configuration"

    cd "$INSTALL_DIR"

    # Backup old genesis
    if [ -f "genesis.json" ]; then
        mv genesis.json "genesis.json.backup.$(date +%Y%m%d%H%M%S)"
    fi

    print_info "Downloading from: $GENESIS_URL"

    if command -v curl &> /dev/null; then
        curl -L -o genesis.json "$GENESIS_URL" --progress-bar
    elif command -v wget &> /dev/null; then
        wget -O genesis.json "$GENESIS_URL" --show-progress
    fi

    if [ ! -f "genesis.json" ] || [ ! -s "genesis.json" ]; then
        print_error "Failed to download genesis.json"
        exit 1
    fi

    print_success "Genesis configuration downloaded"
}

# Re-initialize chain config (for hard fork)
reinit_chain() {
    print_step "5" "Re-initializing chain config (hard fork)"

    print_warn "This will update chain config only, existing chain data will be preserved"
    echo ""

    # Run init with new genesis file (using absolute paths consistent with deployment script)
    print_info "Running: geth init --datadir \"$INSTALL_DIR/data\" \"$INSTALL_DIR/genesis.json\""

    "$INSTALL_DIR/bin/geth" init --datadir "$INSTALL_DIR/data" "$INSTALL_DIR/genesis.json"

    if [ $? -eq 0 ]; then
        print_success "Chain config updated successfully"
    else
        print_error "Failed to update chain config"
        exit 1
    fi
}

# Show completion info
show_completion() {
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}        Upgrade Complete!${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "${BLUE}Upgrade Summary:${NC}"
    echo "  New version: $GETH_VERSION"
    echo "  Install directory: $INSTALL_DIR"
    echo "  Chain data: Preserved"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Start node: $INSTALL_DIR/start-node.sh"
    echo "  2. Or background start: $INSTALL_DIR/start-node-bg.sh"
    echo "  3. Check logs: tail -f $INSTALL_DIR/logs/geth.log"
    echo ""
    echo -e "${YELLOW}Important:${NC}"
    echo "  - If upgrade fails, restore backup from: $INSTALL_DIR/backup/"
    echo "  - Monitor logs after restart to ensure node syncs correctly"
    echo ""
}

# ==================== Main Process ====================

main() {
    print_banner

    # Get install directory
    read -p "Enter node installation directory [$DEFAULT_INSTALL_DIR]: " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}

    # Verify directory exists
    if [ ! -d "$INSTALL_DIR" ]; then
        print_error "Directory does not exist: $INSTALL_DIR"
        exit 1
    fi

    if [ ! -d "$INSTALL_DIR/data" ]; then
        print_error "Data directory not found. Is this a valid PIJS node installation?"
        exit 1
    fi

    print_info "Upgrading node at: $INSTALL_DIR"
    echo ""

    # Confirm upgrade
    echo -e "${YELLOW}WARNING: This will upgrade your node to version $GETH_VERSION${NC}"
    echo "Chain data will be preserved, only client and config will be updated."
    echo ""
    read -p "Continue with upgrade? (y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Upgrade cancelled"
        exit 0
    fi

    detect_platform
    stop_node
    backup_client
    download_client
    download_genesis
    reinit_chain

    show_completion
}

# Run main process
main "$@"
