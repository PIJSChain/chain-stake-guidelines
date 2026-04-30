#!/bin/bash
# ============================================================
# PIJS Consensus Node Upgrade Script
# For hard fork upgrades - updates client and chain config only
# Does NOT delete existing chain data
# ============================================================

set -e

# ==================== Configuration ====================
GITHUB_RELEASE="https://github.com/PIJSChain/pijs/releases/download/v1.26.0"
GETH_VERSION="v1.26.0"
GENESIS_URL="https://github.com/PIJSChain/pijs/releases/download/v1.26.0/genesis.json"

# Default directory
DEFAULT_INSTALL_DIR="$HOME/pijs-node"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

    # Verify gzip magic bytes (1f 8b)
    local magic
    magic=$(head -c 2 "$path" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
    if [ "$magic" != "1f8b" ]; then
        print_error "Not a valid gzip archive (magic=${magic:-unknown}), download may have been truncated or redirected to an HTML page"
        return 1
    fi

    return 0
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
    # Use ps + grep combo to avoid pgrep -f matching the script itself
    # First check if there's a geth process, then check if it uses target directory
    local geth_pids=$(pgrep -x geth 2>/dev/null)
    if [ -z "$geth_pids" ]; then
        return 1
    fi

    # Check if any geth process uses the target directory
    for pid in $geth_pids; do
        if [ -f "/proc/$pid/cmdline" ]; then
            if tr '\0' ' ' < "/proc/$pid/cmdline" | grep -q "$INSTALL_DIR"; then
                return 0
            fi
        else
            # macOS compatibility: use ps
            if ps -p "$pid" -o args= 2>/dev/null | grep -q "$INSTALL_DIR"; then
                return 0
            fi
        fi
    done
    return 1
}

# Stop running node
stop_node() {
    print_step "1" "Checking node status"

    if check_node_running; then
        print_warn "Node is currently running, stopping..."

        # Only stop geth processes that use the target directory
        local geth_pids=$(pgrep -x geth 2>/dev/null)
        for pid in $geth_pids; do
            local cmdline=""
            if [ -f "/proc/$pid/cmdline" ]; then
                cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline")
            else
                cmdline=$(ps -p "$pid" -o args= 2>/dev/null)
            fi
            if echo "$cmdline" | grep -q "$INSTALL_DIR"; then
                kill "$pid" 2>/dev/null || true
            fi
        done

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

    local geth_tar="geth-${GETH_VERSION}-${PLATFORM}.tar.gz"
    local download_url="${GITHUB_RELEASE}/${geth_tar}"
    local bin_dir="$INSTALL_DIR/bin"

    print_info "Downloading from: $download_url"

    # Change to install directory
    cd "$INSTALL_DIR"

    # Download archive
    rm -f "$geth_tar"

    if command -v curl &> /dev/null; then
        curl -L -o "$geth_tar" "$download_url" --progress-bar
    elif command -v wget &> /dev/null; then
        wget -O "$geth_tar" "$download_url" --show-progress
    else
        print_error "Neither curl nor wget found"
        exit 1
    fi

    # Verify download integrity (size + gzip magic)
    if ! verify_gzip_archive "$geth_tar"; then
        rm -f "$geth_tar"
        print_error "Please check your network and retry, or download manually: $download_url"
        exit 1
    fi

    # Extract (check tar exit code explicitly; abort on failure)
    print_info "Extracting files..."
    if ! tar -xzf "$geth_tar"; then
        print_error "Extraction failed, archive may be corrupted"
        rm -f "$geth_tar"
        exit 1
    fi

    # Ensure bin directory exists
    mkdir -p "$bin_dir"

    # Move all binaries to bin directory
    for binary in geth bootnode abigen clef evm rlpdump devp2p ethkey p2psim; do
        if [ -f "$binary" ]; then
            mv "$binary" "$bin_dir/"
            chmod +x "$bin_dir/$binary"
        fi
    done

    # Clean up archive
    rm -f "$geth_tar"

    # Verify geth was extracted
    if [ ! -x "$bin_dir/geth" ]; then
        print_error "Extraction completed but $bin_dir/geth was not found; archive contents are abnormal"
        exit 1
    fi

    # Verify geth runs
    if ! "$bin_dir/geth" version >/dev/null 2>&1; then
        print_error "geth failed to run — binary may be corrupted"
        "$bin_dir/geth" version || true
        exit 1
    fi

    # Update binaries in /usr/local/bin
    if [ -f "/usr/local/bin/geth" ]; then
        print_info "Detected /usr/local/bin/geth, updating..."
        if [ -w "/usr/local/bin" ]; then
            cp "$bin_dir/geth" /usr/local/bin/geth
            [ -f "$bin_dir/bootnode" ] && cp "$bin_dir/bootnode" /usr/local/bin/bootnode
            [ -f "$bin_dir/devp2p" ] && cp "$bin_dir/devp2p" /usr/local/bin/devp2p
            print_success "Updated binaries in /usr/local/bin"
        elif command -v sudo &> /dev/null; then
            sudo cp "$bin_dir/geth" /usr/local/bin/geth
            [ -f "$bin_dir/bootnode" ] && sudo cp "$bin_dir/bootnode" /usr/local/bin/bootnode
            [ -f "$bin_dir/devp2p" ] && sudo cp "$bin_dir/devp2p" /usr/local/bin/devp2p
            print_success "Updated binaries in /usr/local/bin"
        else
            print_warn "Cannot update /usr/local/bin, please copy manually"
        fi
    fi

    # Show version
    local version=$("$bin_dir/geth" version 2>/dev/null | grep "Version:" | head -1 || echo "Unknown")
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
        curl -fL -o genesis.json "$GENESIS_URL" --progress-bar || true
    elif command -v wget &> /dev/null; then
        wget -O genesis.json "$GENESIS_URL" --show-progress || true
    fi

    local genesis_size
    genesis_size=$(wc -c < genesis.json 2>/dev/null | tr -d ' ' || echo 0)
    if [ ! -f "genesis.json" ] || [ "${genesis_size:-0}" -lt 100 ]; then
        print_error "Failed to download genesis.json or file is too small (${genesis_size:-0} bytes)"
        rm -f genesis.json
        exit 1
    fi

    # Validate JSON syntax
    if command -v python3 &> /dev/null; then
        if ! python3 -c "import json,sys; json.load(open('genesis.json'))" 2>/dev/null; then
            print_error "genesis.json is not valid JSON, download may have been truncated"
            rm -f genesis.json
            exit 1
        fi
    elif command -v python &> /dev/null; then
        if ! python -c "import json,sys; json.load(open('genesis.json'))" 2>/dev/null; then
            print_error "genesis.json is not valid JSON, download may have been truncated"
            rm -f genesis.json
            exit 1
        fi
    fi

    print_success "Genesis configuration downloaded"
}

# Re-initialize chain config (for hard fork)
reinit_chain() {
    print_step "5" "Re-initializing chain config (hard fork)"

    print_warn "This will update chain config only, existing chain data will be preserved"
    echo ""

    # Run init with new genesis file (consistent with deployment script)
    print_info "Running: geth init --datadir \"$INSTALL_DIR/data\" \"$INSTALL_DIR/genesis.json\""

    geth init --datadir "$INSTALL_DIR/data" "$INSTALL_DIR/genesis.json"

    if [ $? -eq 0 ]; then
        print_success "Chain config updated successfully"
    else
        print_error "Failed to update chain config"
        exit 1
    fi
}

# Interactive NAT mode selection (consistent with setup)
choose_nat_mode() {
    echo ""
    echo "Please select your network environment:"
    echo ""
    echo "  1) Static public IP - Server has a static public IP address"
    echo "  2) NAT environment  - Behind a router/NAT gateway (home networks, some cloud VMs)"
    echo "  3) Auto-detect      - Detect public IP on every startup (recommended)"
    echo ""

    while true; do
        read -p "Please choose [1-3] (default: 3): " network_choice
        network_choice=${network_choice:-3}

        case $network_choice in
            1)
                echo ""
                echo "Detecting your public IP..."
                local detected_ip=""
                for service in "https://ip.sb" "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com" "https://ipinfo.io/ip"; do
                    detected_ip=$(curl -sA "curl/7" --connect-timeout 3 --max-time 5 "$service" 2>/dev/null | tr -d '[:space:]')
                    if [[ "$detected_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                        break
                    fi
                done

                if [ -n "$detected_ip" ]; then
                    echo "Detected IP: $detected_ip"
                    read -p "Use this IP? (y/n, or enter a different IP): " ip_confirm
                    if [ "$ip_confirm" = "y" ] || [ "$ip_confirm" = "Y" ] || [ -z "$ip_confirm" ]; then
                        NAT_MODE="extip"
                        PUBLIC_IP="$detected_ip"
                    elif [[ "$ip_confirm" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                        NAT_MODE="extip"
                        PUBLIC_IP="$ip_confirm"
                    else
                        echo "Invalid input, please try again"
                        continue
                    fi
                else
                    read -p "Failed to detect public IP, please enter your public IP manually: " PUBLIC_IP
                    if [[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                        NAT_MODE="extip"
                    else
                        print_error "Invalid IP address format"
                        continue
                    fi
                fi
                break
                ;;
            2)
                NAT_MODE="any"
                PUBLIC_IP=""
                print_info "NAT mode selected, will use UPnP/NAT-PMP for automatic port mapping"
                break
                ;;
            3)
                NAT_MODE="auto"
                PUBLIC_IP=""
                print_info "Auto-detect mode, will detect public IP on every startup"
                break
                ;;
            *)
                echo "Invalid choice, please enter 1, 2 or 3"
                ;;
        esac
    done
}

# Emit NAT configuration block based on NAT_MODE, for embedding into start-node.sh
emit_nat_section() {
    if [ "$NAT_MODE" = "extip" ]; then
        cat << EOF
# Static public IP mode
NAT_CONFIG="extip:$PUBLIC_IP"
echo "NAT config: \$NAT_CONFIG (static public IP)"
EOF
    elif [ "$NAT_MODE" = "any" ]; then
        cat << EOF
# NAT environment mode (UPnP/NAT-PMP)
NAT_CONFIG="any"
echo "NAT config: \$NAT_CONFIG (automatic port mapping)"
EOF
    else
        cat << 'AUTODETECT'
# Auto-detect public IP
detect_public_ip() {
    local ip=""
    for service in "https://ip.sb" "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com" "https://ipecho.net/plain" "https://ipinfo.io/ip"; do
        ip=$(curl -sA "curl/7" --connect-timeout 3 --max-time 5 "$service" 2>/dev/null | tr -d '[:space:]')
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    return 1
}

echo "Detecting public IP..."
DETECTED_IP=$(detect_public_ip)
if [ -n "$DETECTED_IP" ]; then
    NAT_CONFIG="extip:$DETECTED_IP"
    echo "  Detected public IP: $DETECTED_IP"
    echo "  NAT config: $NAT_CONFIG"
else
    NAT_CONFIG="any"
    echo "  Failed to detect public IP, using NAT: any"
fi
AUTODETECT
    fi
}

# Optional: reconfigure network
reconfigure_network() {
    print_step "6" "Network configuration (optional)"

    echo ""
    echo "This step reconfigures the node's NAT network mode"
    echo "Only needed in the following cases:"
    echo "  - Server IP changed"
    echo "  - Migrated from home network to cloud (or vice versa)"
    echo "  - NAT was misconfigured (e.g. peerCount stays at 0)"
    echo ""

    read -p "Reconfigure network? (y/N): " reset_network
    if [ "$reset_network" != "y" ] && [ "$reset_network" != "Y" ]; then
        print_info "Skipping network configuration (keeping current settings)"
        return
    fi

    local start_script="$INSTALL_DIR/start-node.sh"
    if [ ! -f "$start_script" ]; then
        print_error "Not found: $start_script"
        print_error "Please re-run setup-node-testnet.sh to redeploy"
        return
    fi

    # Require new-format start-node.sh with explicit NAT markers
    if ! grep -q "^# ==================== NAT Configuration ====================$" "$start_script" || \
       ! grep -q "^# ==================== Start Node ====================$" "$start_script"; then
        print_error "start-node.sh format incompatible (may be generated by an older setup script)"
        print_error "Please re-run setup-node-testnet.sh to redeploy"
        return
    fi

    # Ask for NAT mode
    choose_nat_mode

    # Emit new NAT block to a temp file
    local nat_block_file
    nat_block_file=$(mktemp)
    emit_nat_section > "$nat_block_file"

    # Back up current start-node.sh
    local backup_dir="$INSTALL_DIR/backup"
    mkdir -p "$backup_dir"
    local backup_file="$backup_dir/start-node.sh.$(date +%Y%m%d%H%M%S)"
    cp "$start_script" "$backup_file"
    print_info "Backed up original start-node.sh to: $backup_file"

    # Replace content between the two marker lines using awk
    local temp_script
    temp_script=$(mktemp)
    awk -v nat_file="$nat_block_file" '
        /^# ==================== NAT Configuration ====================$/ {
            in_nat = 1
            print
            while ((getline line < nat_file) > 0) print line
            close(nat_file)
            next
        }
        /^# ==================== Start Node ====================$/ {
            in_nat = 0
        }
        !in_nat { print }
    ' "$start_script" > "$temp_script"

    mv "$temp_script" "$start_script"
    rm -f "$nat_block_file"
    chmod +x "$start_script"

    print_success "Network configuration updated to: $NAT_MODE"
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
    echo -e "${BLUE}Network Diagnostics:${NC}"
    echo "  If peerCount stays at 0 after startup, use devp2p to test bootnode connectivity:"
    echo -e "  ${CYAN}devp2p discv4 ping <enode-url>${NC}"
    echo "  Example: devp2p discv4 ping enode://6f05...fb@54.169.152.20:30303"
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
    reconfigure_network

    show_completion
}

# Run main process
main "$@"
