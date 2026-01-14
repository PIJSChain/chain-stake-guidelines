#!/bin/bash
# ============================================================
# PIJS Consensus Node One-Click Deployment Script
# Supports: Linux (x86_64/ARM64), macOS (Intel/Apple Silicon)
# ============================================================

set -e

# ==================== Configuration ====================
# Download URLs
GITHUB_RELEASE="https://github.com/PIJSChain/pijs/releases/download/v1.25.6h"
GETH_VERSION="v1.25.6h"
GENESIS_URL="https://github.com/PIJSChain/pijs/releases/download/v1.25.6h/genesis.json"
BOOTNODE_URL="https://github.com/PIJSChain/pijs/releases/download/v1.25.6h/bootnodes.txt"

# Chain configuration
CHAIN_ID="20250521"
NETWORK_NAME="PIJS Testnet"

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
    echo "    PIJS Consensus Node One-Click Deployment Script"
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

# Check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
}

# Check dependencies
check_dependencies() {
    print_step "1" "Checking system dependencies"

    local missing_deps=()

    # Check curl or wget
    if ! check_command curl && ! check_command wget; then
        missing_deps+=("curl or wget")
    fi

    # Check tar
    if ! check_command tar; then
        missing_deps+=("tar")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_error "Missing dependencies, please install first:"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        exit 1
    fi

    print_success "System dependencies check passed"
}

# Download file
download_file() {
    local url="$1"
    local output="$2"

    if check_command curl; then
        curl -fsSL "$url" -o "$output"
    elif check_command wget; then
        wget -q "$url" -O "$output"
    else
        print_error "curl or wget required to download files"
        exit 1
    fi
}

# ==================== Installation Process ====================

# Create directory structure
setup_directories() {
    print_step "2" "Creating directory structure"

    echo -e "Enter installation directory [default: ${DEFAULT_INSTALL_DIR}]: \c"
    read -r INSTALL_DIR
    INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"

    # Expand ~ symbol
    INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

    if [ -d "$INSTALL_DIR/data/PIJSChain/chaindata" ]; then
        print_warn "Existing node data detected: $INSTALL_DIR/data"
        echo -e "Continue? This will preserve existing data (y/n): \c"
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Cancelled"
            exit 0
        fi
    fi

    mkdir -p "$INSTALL_DIR"/{data/PIJSChain,logs,keys}
    cd "$INSTALL_DIR"

    print_success "Directories created: $INSTALL_DIR"
}

# Download geth binary
download_geth() {
    print_step "3" "Downloading node program"

    local geth_tar="geth-${GETH_VERSION}-${PLATFORM}.tar.gz"
    local geth_url="${GITHUB_RELEASE}/${geth_tar}"

    # Check if already installed
    if check_command geth; then
        local current_version=$(geth version 2>/dev/null | head -1 || echo "unknown")
        print_info "Detected installed geth: $current_version"
        echo -e "Download latest version? (y/n) [default: n]: \c"
        read -r redownload
        if [[ ! "$redownload" =~ ^[Yy]$ ]]; then
            print_info "Skipping download, using existing version"
            return
        fi
    fi

    print_info "Downloading geth ($PLATFORM)..."
    print_info "URL: $geth_url"

    # Download file
    cd "$INSTALL_DIR"
    if [ -f "$geth_tar" ]; then
        print_info "Found downloaded file, skipping download"
    else
        download_file "$geth_url" "$geth_tar"
    fi

    # Extract
    print_info "Extracting files..."
    tar -xzf "$geth_tar"

    # Create bin directory and move binaries
    mkdir -p "$INSTALL_DIR/bin"

    # Move all binaries to bin directory
    for binary in geth bootnode abigen clef evm rlpdump; do
        if [ -f "$binary" ]; then
            mv "$binary" "$INSTALL_DIR/bin/"
            chmod +x "$INSTALL_DIR/bin/$binary"
            print_info "Installed: $binary"
        fi
    done

    # Clean up archive
    rm -f "$geth_tar"

    # Add to PATH
    print_info "Configuring environment variables..."
    export PATH="$INSTALL_DIR/bin:$PATH"

    # Add to shell config file
    local shell_rc=""
    if [ -f "$HOME/.zshrc" ]; then
        shell_rc="$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        shell_rc="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
        shell_rc="$HOME/.bash_profile"
    fi

    if [ -n "$shell_rc" ]; then
        # Check if already added
        if ! grep -q "pijs-node/bin" "$shell_rc" 2>/dev/null; then
            echo "" >> "$shell_rc"
            echo "# PIJS Node" >> "$shell_rc"
            echo "export PATH=\"$INSTALL_DIR/bin:\$PATH\"" >> "$shell_rc"
            print_info "Added to $shell_rc"
        fi
    fi

    # Copy to system path
    echo -e "Copy geth and bootnode to /usr/local/bin? (y/n) [default: y]: \c"
    read -r copy_to_system
    if [[ ! "$copy_to_system" =~ ^[Nn]$ ]]; then
        if [ -w "/usr/local/bin" ] || command -v sudo &> /dev/null; then
            print_info "Copying binaries to /usr/local/bin/..."
            if [ -w "/usr/local/bin" ]; then
                cp "$INSTALL_DIR/bin/geth" /usr/local/bin/
                cp "$INSTALL_DIR/bin/bootnode" /usr/local/bin/
            else
                sudo cp "$INSTALL_DIR/bin/geth" /usr/local/bin/
                sudo cp "$INSTALL_DIR/bin/bootnode" /usr/local/bin/
            fi
            print_success "Copied to /usr/local/bin/"
        else
            print_warn "Cannot write to /usr/local/bin/, please copy manually or use sudo"
        fi
    fi

    # Verify installation
    if [ -f "$INSTALL_DIR/bin/geth" ]; then
        "$INSTALL_DIR/bin/geth" version
        print_success "Node program installation complete"
        print_info "Binary location: $INSTALL_DIR/bin/"
    else
        print_error "geth installation failed"
        exit 1
    fi
}

# Download genesis.json
download_genesis() {
    print_step "4" "Downloading genesis configuration"

    if [ -f "genesis.json" ]; then
        print_info "Existing genesis.json detected"
        echo -e "Re-download? (y/n) [default: n]: \c"
        read -r redownload
        if [[ ! "$redownload" =~ ^[Yy]$ ]]; then
            print_info "Skipping download, using existing configuration"
            return
        fi
    fi

    print_info "Downloading genesis.json..."
    print_info "URL: $GENESIS_URL"

    # Try auto download
    if download_file "$GENESIS_URL" "genesis.json"; then
        print_success "genesis.json download complete"
    else
        # Download failed, prompt for manual download
        echo ""
        print_warn "Auto download failed, please download genesis.json manually"
        print_info "URL: $GENESIS_URL"
        print_info "Save to: $INSTALL_DIR/genesis.json"
        echo ""
        echo -e "Is genesis.json ready? (y/n): \c"
        read -r genesis_ready
        if [[ ! "$genesis_ready" =~ ^[Yy]$ ]]; then
            print_error "Please download genesis.json before running this script"
            exit 1
        fi

        if [ ! -f "genesis.json" ]; then
            print_error "genesis.json file does not exist"
            exit 1
        fi
    fi

    print_success "Genesis configuration ready"
}

# Generate nodekey (fixed node identity)
generate_nodekey() {
    print_step "5" "Generating node identity (nodekey)"

    local nodekey_file="$INSTALL_DIR/data/PIJSChain/nodekey"

    # Ensure directory exists
    mkdir -p "$INSTALL_DIR/data/PIJSChain"

    if [ -f "$nodekey_file" ]; then
        print_info "Existing nodekey detected"
        echo -e "Keep existing nodekey? (y/n) [default: y]: \c"
        read -r keep_nodekey
        if [[ "$keep_nodekey" =~ ^[Nn]$ ]]; then
            rm -f "$nodekey_file"
        else
            print_info "Keeping existing nodekey"
            # Show existing enode address
            if [ -f "$INSTALL_DIR/bin/bootnode" ]; then
                local enode_addr=$("$INSTALL_DIR/bin/bootnode" -nodekey "$nodekey_file" -writeaddress 2>/dev/null)
                if [ -n "$enode_addr" ]; then
                    print_info "Node ID: $enode_addr"
                fi
            fi
            return
        fi
    fi

    print_info "Generating new nodekey..."

    # Prefer bootnode tool for generation
    if [ -f "$INSTALL_DIR/bin/bootnode" ]; then
        "$INSTALL_DIR/bin/bootnode" -genkey "$nodekey_file"
        print_success "nodekey generated (using bootnode)"
        # Show enode address
        local enode_addr=$("$INSTALL_DIR/bin/bootnode" -nodekey "$nodekey_file" -writeaddress 2>/dev/null)
        if [ -n "$enode_addr" ]; then
            print_info "Node ID: $enode_addr"
        fi
    elif check_command bootnode; then
        bootnode -genkey "$nodekey_file"
        print_success "nodekey generated (using bootnode)"
    elif check_command openssl; then
        # Fallback: use openssl to generate 32-byte random
        openssl rand -hex 32 > "$nodekey_file"
        print_success "nodekey generated (using openssl)"
    else
        # Last resort: use /dev/urandom
        head -c 32 /dev/urandom | xxd -p -c 64 > "$nodekey_file"
        print_success "nodekey generated (using urandom)"
    fi

    chmod 600 "$nodekey_file"

    print_info "nodekey location: $nodekey_file"
    print_warn "Please backup this file securely, it determines your node identity"
}

# Generate BLS key
generate_bls_key() {
    print_step "6" "Generating BLS key"

    local bls_keyfile="$INSTALL_DIR/keys/bls-keystore.json"
    local bls_password="$INSTALL_DIR/keys/password.txt"

    if [ -f "$bls_keyfile" ]; then
        print_info "Existing BLS key detected"
        echo -e "Keep existing BLS key? (y/n) [default: y]: \c"
        read -r keep_bls
        if [[ "$keep_bls" =~ ^[Nn]$ ]]; then
            rm -f "$bls_keyfile" "$bls_password"
        else
            print_info "Keeping existing BLS key"
            return
        fi
    fi

    echo ""
    print_info "About to generate BLS key, please set a strong password"
    print_warn "This password encrypts your BLS private key, remember it!"
    echo ""

    # Get password
    while true; do
        echo -e "Enter BLS key password: \c"
        read -rs bls_pwd
        echo ""
        echo -e "Confirm password: \c"
        read -rs bls_pwd_confirm
        echo ""

        if [ "$bls_pwd" != "$bls_pwd_confirm" ]; then
            print_error "Passwords do not match, please try again"
            continue
        fi

        if [ ${#bls_pwd} -lt 8 ]; then
            print_error "Password must be at least 8 characters"
            continue
        fi

        break
    done

    # Save password to file
    echo "$bls_pwd" > "$bls_password"
    chmod 600 "$bls_password"

    # Generate BLS key
    print_info "Generating BLS key..."

    # Use expect or direct call (depending on geth implementation)
    echo "$bls_pwd" | geth hybrid bls generate --save "$bls_keyfile" --password "$bls_password" 2>/dev/null || \
    geth hybrid bls generate --save "$bls_keyfile" --password "$bls_password"

    if [ ! -f "$bls_keyfile" ]; then
        print_error "BLS key generation failed"
        exit 1
    fi

    chmod 600 "$bls_keyfile"

    # Show public key
    echo ""
    print_success "BLS key generated successfully"
    print_info "Key file: $bls_keyfile"
    print_info "Password file: $bls_password"
    echo ""
    print_info "Your BLS public key:"
    geth hybrid bls show --keyfile "$bls_keyfile" --password "$bls_password" 2>/dev/null | grep "Public Key" || \
    geth hybrid bls show --keyfile "$bls_keyfile" --password "$bls_password"
    echo ""
    print_warn "Please backup BLS key file and password securely, cannot be recovered if lost!"
}

# Initialize blockchain data
init_blockchain() {
    print_step "7" "Initializing blockchain data"

    local chaindata="$INSTALL_DIR/data/PIJSChain/chaindata"

    if [ -d "$chaindata" ] && [ "$(ls -A $chaindata 2>/dev/null)" ]; then
        print_info "Existing blockchain data detected"
        echo -e "Skip initialization? (y/n) [default: y]: \c"
        read -r skip_init
        if [[ ! "$skip_init" =~ ^[Nn]$ ]]; then
            print_info "Skipping initialization"
            return
        fi
        print_warn "Re-initialization will delete existing data!"
        echo -e "Confirm delete and re-initialize? (yes/no): \c"
        read -r confirm_delete
        if [ "$confirm_delete" != "yes" ]; then
            print_info "Cancelled re-initialization"
            return
        fi
        rm -rf "$INSTALL_DIR/data/PIJSChain/chaindata" "$INSTALL_DIR/data/PIJSChain/lightchaindata"
    fi

    print_info "Initializing blockchain data..."
    geth init --datadir "$INSTALL_DIR/data" "$INSTALL_DIR/genesis.json"

    print_success "Blockchain data initialization complete"
}

# Configure withdrawal address
configure_withdrawal() {
    print_step "8" "Configuring withdrawal address"

    echo ""
    print_info "Withdrawal address receives your staking rewards"
    print_warn "Ensure you have full control of this address's private key"
    echo ""

    while true; do
        echo -e "Enter your withdrawal address (starting with 0x): \c"
        read -r WITHDRAWAL_ADDRESS

        # Validate address format
        if [[ ! "$WITHDRAWAL_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            print_error "Invalid address format, please enter a valid Ethereum address"
            continue
        fi

        echo -e "Confirm withdrawal address: $WITHDRAWAL_ADDRESS (y/n): \c"
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            break
        fi
    done

    print_success "Withdrawal address configured: $WITHDRAWAL_ADDRESS"
}

# Get boot nodes
get_bootnodes() {
    print_step "9" "Configuring boot nodes"

    # Default boot nodes
    DEFAULT_BOOTNODES="enode://6f05512feacca0b15cd94ed2165e8f96b16cf346cb16ba7810a37bea05851b3887ee8ef3ee790090cb3352f37a710bcd035d6b0bfd8961287751532c2b0717fb@54.169.152.20:30303,enode://2d2370d19648032a525287645a38b6f1a87199e282cf9a99ebc25f3387e79780695b6c517bd8180be4e9b6b93c39502185960203c35d1ea067924f40e0fd50f1@104.16.132.181:30303,enode://3fb2f819279b92f256718081af1c26bb94c4056f9938f8f1897666f1612ad478e2d84fc56428d20f99201d958951bde4c3f732d27c52d0c5138d9174e744e115@52.76.128.119:30303"

    echo ""
    print_info "Boot nodes are used to connect to the PIJS network"
    echo ""

    # Try to download bootnodes.txt
    print_info "Fetching boot node list..."
    if download_file "$BOOTNODE_URL" "bootnodes.txt" 2>/dev/null; then
        # Read bootnodes.txt and merge into comma-separated string
        BOOTNODES=$(cat bootnodes.txt | grep -v "^#" | grep -v "^$" | tr '\n' ',' | sed 's/,$//')
        if [ -n "$BOOTNODES" ]; then
            print_success "Boot nodes fetched from bootnodes.txt"
        else
            BOOTNODES="$DEFAULT_BOOTNODES"
            print_info "Using default boot nodes"
        fi
    else
        BOOTNODES="$DEFAULT_BOOTNODES"
        print_info "Using default boot nodes"
    fi

    print_success "Boot nodes configured"
}

# Generate startup script
generate_start_script() {
    print_step "10" "Generating startup scripts"

    local start_script="$INSTALL_DIR/start-node.sh"

    cat > "$start_script" << EOF
#!/bin/bash
# PIJS Node Startup Script
# Generated: $(date)

# ==================== Configuration ====================
INSTALL_DIR="$INSTALL_DIR"
export PATH="\$INSTALL_DIR/bin:\$PATH"

DATADIR="\$INSTALL_DIR/data"
BLS_KEYFILE="\$INSTALL_DIR/keys/bls-keystore.json"
BLS_PASSWORD="\$INSTALL_DIR/keys/password.txt"
WITHDRAWAL_ADDRESS="$WITHDRAWAL_ADDRESS"
BOOTNODES="$BOOTNODES"

# Network configuration
NETWORK_ID="$CHAIN_ID"
HTTP_ADDR="0.0.0.0"
HTTP_PORT="8545"
# Security warning: Only expose safe API modules!
# Safe: eth,net,web3,hybrid
# Dangerous (never add): personal,admin,debug,miner
HTTP_API="eth,net,web3,hybrid"
WS_ADDR="0.0.0.0"
WS_PORT="8546"
# Security warning: Same as HTTP_API, do not add personal/admin/debug/miner
WS_API="eth,net,web3,hybrid"

# Performance configuration
CACHE_SIZE="4096"

# Log configuration
LOG_DIR="\$INSTALL_DIR/logs"
LOG_FILE="\$LOG_DIR/geth.log"
LOG_MAXSIZE="100"
LOG_MAXBACKUPS="10"

# ==================== Startup Checks ====================
echo "========================================"
echo "  PIJS Consensus Node Starting"
echo "========================================"

# Check required files
if [ ! -f "\$BLS_KEYFILE" ]; then
    echo "Error: BLS key file does not exist: \$BLS_KEYFILE"
    exit 1
fi

if [ ! -f "\$BLS_PASSWORD" ]; then
    echo "Error: BLS password file does not exist: \$BLS_PASSWORD"
    exit 1
fi

# Create log directory
mkdir -p "\$LOG_DIR"

# Display configuration
echo ""
echo "Configuration:"
echo "  Data directory: \$DATADIR"
echo "  Network ID: \$NETWORK_ID"
echo "  HTTP RPC: http://\$HTTP_ADDR:\$HTTP_PORT"
echo "  WebSocket: ws://\$WS_ADDR:\$WS_PORT"
echo "  Withdrawal address: \$WITHDRAWAL_ADDRESS"
echo "  Log file: \$LOG_FILE"
echo ""

# Security warning
if [ "\$HTTP_ADDR" == "0.0.0.0" ] || [ "\$WS_ADDR" == "0.0.0.0" ]; then
    echo "========================================"
    echo "Security Warning: RPC interface exposed externally"
    echo "========================================"
    echo "Recommend configuring firewall to restrict access IPs"
    echo ""
fi

# ==================== Start Node ====================
echo "Starting node..."

# Build startup arguments
START_ARGS=(
    --datadir "\$DATADIR"
    --networkid "\$NETWORK_ID"
    --syncmode "full"
    --gcmode "archive"
    --cache "\$CACHE_SIZE"
    --http
    --http.addr "\$HTTP_ADDR"
    --http.port "\$HTTP_PORT"
    --http.api "\$HTTP_API"
    --http.corsdomain "*"
    --http.vhosts "*"
    --ws
    --ws.addr "\$WS_ADDR"
    --ws.port "\$WS_PORT"
    --ws.api "\$WS_API"
    --ws.origins "*"
    --authrpc.vhosts "*"
    --hybrid.liveness
    --hybrid.withdrawal "\$WITHDRAWAL_ADDRESS"
    --hybrid.blskey "\$BLS_KEYFILE"
    --hybrid.blspassword "\$BLS_PASSWORD"
    --bootnodes "\$BOOTNODES"
    --log.file "\$LOG_FILE"
    --log.maxsize "\$LOG_MAXSIZE"
    --log.maxbackups "\$LOG_MAXBACKUPS"
    --log.compress
    --nat "any"
)

# Start geth
exec geth "\${START_ARGS[@]}"
EOF

    chmod +x "$start_script"

    # Generate background startup script
    local start_bg_script="$INSTALL_DIR/start-node-bg.sh"
    cat > "$start_bg_script" << EOF
#!/bin/bash
# PIJS Node Background Startup Script

INSTALL_DIR="$INSTALL_DIR"
LOG_FILE="\$INSTALL_DIR/logs/geth.log"

echo "Starting node in background..."
nohup "\$INSTALL_DIR/start-node.sh" > /dev/null 2>&1 &

echo "Node started in background"
echo "View logs: tail -f \$LOG_FILE"
echo "Stop node: pkill -f 'geth.*--datadir.*pijs-node'"
EOF

    chmod +x "$start_bg_script"

    # Generate stop script
    local stop_script="$INSTALL_DIR/stop-node.sh"
    cat > "$stop_script" << EOF
#!/bin/bash
# PIJS Node Stop Script

echo "Stopping node..."
pkill -f "geth.*--datadir.*$INSTALL_DIR"

if [ \$? -eq 0 ]; then
    echo "Node stopped"
else
    echo "No running node found"
fi
EOF

    chmod +x "$stop_script"

    print_success "Startup scripts generated:"
    echo "  - Foreground start: $start_script"
    echo "  - Background start: $start_bg_script"
    echo "  - Stop node: $stop_script"
}

# Show completion info
show_completion() {
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}        Deployment Complete!${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "${BLUE}Node Information:${NC}"
    echo "  Install directory: $INSTALL_DIR"
    echo "  Data directory: $INSTALL_DIR/data"
    echo "  BLS key: $INSTALL_DIR/keys/bls-keystore.json"
    echo "  Withdrawal address: $WITHDRAWAL_ADDRESS"
    echo ""
    echo -e "${BLUE}Startup Commands:${NC}"
    echo "  Foreground start: $INSTALL_DIR/start-node.sh"
    echo "  Background start: $INSTALL_DIR/start-node-bg.sh"
    echo "  Stop node: $INSTALL_DIR/stop-node.sh"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Start node: cd $INSTALL_DIR && ./start-node.sh"
    echo "  2. Wait for node synchronization to complete"
    echo "  3. Generate staking signature: geth hybrid bls deposit --keyfile ./keys/bls-keystore.json \\"
    echo "       --chainid $CHAIN_ID --address $WITHDRAWAL_ADDRESS --amount 10000 \\"
    echo "       --output deposit_data.json"
    echo "  4. Visit staking platform, upload deposit_data.json to complete staking"
    echo ""
    echo -e "${YELLOW}Important Notes:${NC}"
    echo "  - Please backup key files in $INSTALL_DIR/keys/ directory securely"
    echo "  - Please backup $INSTALL_DIR/data/PIJSChain/nodekey file"
    echo "  - Initial sync may take hours to days (archive mode)"
    echo ""
    echo "============================================================"
}

# ==================== Main Process ====================

main() {
    print_banner

    detect_platform

    check_dependencies
    setup_directories
    download_geth
    download_genesis
    generate_nodekey
    generate_bls_key
    init_blockchain
    configure_withdrawal
    get_bootnodes
    generate_start_script

    show_completion
}

# Run main process
main "$@"
