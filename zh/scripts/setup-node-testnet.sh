#!/bin/bash
# ============================================================
# PIJS 共识节点一键部署脚本
# 支持: Linux (x86_64/ARM64), macOS (Intel/Apple Silicon)
# ============================================================

set -e

# ==================== 配置区域 ====================
# 下载地址
GITHUB_RELEASE="https://github.com/PIJSChain/pijs/releases/download/v1.25.6h"
GETH_VERSION="v1.25.6h"
GENESIS_URL="https://github.com/PIJSChain/pijs/releases/download/v1.25.6h/genesis.json"
BOOTNODE_URL="https://github.com/PIJSChain/pijs/releases/download/v1.25.6h/bootnodes.txt"

# 链配置
CHAIN_ID="20250521"
NETWORK_NAME="PIJS Testnet"

# 默认目录
DEFAULT_INSTALL_DIR="$HOME/pijs-node"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==================== 工具函数 ====================

print_banner() {
    echo -e "${BLUE}"
    echo "============================================================"
    echo "        PIJS 共识节点一键部署脚本"
    echo "============================================================"
    echo -e "${NC}"
}

print_step() {
    echo -e "\n${GREEN}[步骤 $1]${NC} $2"
    echo "------------------------------------------------------------"
}

print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

# 检测操作系统和架构
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
            print_error "不支持的操作系统: $OS"
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
            print_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac

    PLATFORM="${OS}-${ARCH}"
    print_info "检测到平台: $PLATFORM"
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
}

# 检查依赖
check_dependencies() {
    print_step "1" "检查系统依赖"

    local missing_deps=()

    # 检查 curl 或 wget
    if ! check_command curl && ! check_command wget; then
        missing_deps+=("curl 或 wget")
    fi

    # 检查 tar
    if ! check_command tar; then
        missing_deps+=("tar")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_error "缺少以下依赖，请先安装："
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        exit 1
    fi

    print_success "系统依赖检查通过"
}

# 下载文件
download_file() {
    local url="$1"
    local output="$2"

    if check_command curl; then
        curl -fsSL "$url" -o "$output"
    elif check_command wget; then
        wget -q "$url" -O "$output"
    else
        print_error "需要 curl 或 wget 来下载文件"
        exit 1
    fi
}

# ==================== 安装流程 ====================

# 创建目录结构
setup_directories() {
    print_step "2" "创建目录结构"

    echo -e "请输入安装目录 [默认: ${DEFAULT_INSTALL_DIR}]: \c"
    read -r INSTALL_DIR
    INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"

    # 展开 ~ 符号
    INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

    if [ -d "$INSTALL_DIR/data/PIJSChain/chaindata" ]; then
        print_warn "检测到已存在的节点数据: $INSTALL_DIR/data"
        echo -e "是否继续？这将保留现有数据 (y/n): \c"
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "已取消"
            exit 0
        fi
    fi

    mkdir -p "$INSTALL_DIR"/{data/PIJSChain,logs,keys}
    cd "$INSTALL_DIR"

    print_success "目录创建完成: $INSTALL_DIR"
}

# 下载 geth 二进制文件
download_geth() {
    print_step "3" "下载节点程序"

    local geth_tar="geth-${GETH_VERSION}-${PLATFORM}.tar.gz"
    local geth_url="${GITHUB_RELEASE}/${geth_tar}"

    # 检查是否已安装
    if check_command geth; then
        local current_version=$(geth version 2>/dev/null | head -1 || echo "unknown")
        print_info "检测到已安装的 geth: $current_version"
        echo -e "是否重新下载最新版本? (y/n) [默认: n]: \c"
        read -r redownload
        if [[ ! "$redownload" =~ ^[Yy]$ ]]; then
            print_info "跳过下载，使用现有版本"
            return
        fi
    fi

    print_info "正在下载 geth ($PLATFORM)..."
    print_info "下载地址: $geth_url"

    # 下载文件
    cd "$INSTALL_DIR"
    if [ -f "$geth_tar" ]; then
        print_info "发现已下载的文件，跳过下载"
    else
        download_file "$geth_url" "$geth_tar"
    fi

    # 解压
    print_info "解压文件..."
    tar -xzf "$geth_tar"

    # 创建 bin 目录并移动二进制文件
    mkdir -p "$INSTALL_DIR/bin"

    # 移动所有二进制文件到 bin 目录
    for binary in geth bootnode abigen clef evm rlpdump; do
        if [ -f "$binary" ]; then
            mv "$binary" "$INSTALL_DIR/bin/"
            chmod +x "$INSTALL_DIR/bin/$binary"
            print_info "已安装: $binary"
        fi
    done

    # 清理压缩包
    rm -f "$geth_tar"

    # 添加到 PATH
    print_info "配置环境变量..."
    export PATH="$INSTALL_DIR/bin:$PATH"

    # 添加到 shell 配置文件
    local shell_rc=""
    if [ -f "$HOME/.zshrc" ]; then
        shell_rc="$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        shell_rc="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
        shell_rc="$HOME/.bash_profile"
    fi

    if [ -n "$shell_rc" ]; then
        # 检查是否已经添加过
        if ! grep -q "pijs-node/bin" "$shell_rc" 2>/dev/null; then
            echo "" >> "$shell_rc"
            echo "# PIJS Node" >> "$shell_rc"
            echo "export PATH=\"$INSTALL_DIR/bin:\$PATH\"" >> "$shell_rc"
            print_info "已添加到 $shell_rc"
        fi
    fi

    # 复制到系统路径
    echo -e "是否将 geth 和 bootnode 复制到 /usr/local/bin? (y/n) [默认: y]: \c"
    read -r copy_to_system
    if [[ ! "$copy_to_system" =~ ^[Nn]$ ]]; then
        if [ -w "/usr/local/bin" ] || command -v sudo &> /dev/null; then
            print_info "复制二进制文件到 /usr/local/bin/..."
            if [ -w "/usr/local/bin" ]; then
                cp "$INSTALL_DIR/bin/geth" /usr/local/bin/
                cp "$INSTALL_DIR/bin/bootnode" /usr/local/bin/
            else
                sudo cp "$INSTALL_DIR/bin/geth" /usr/local/bin/
                sudo cp "$INSTALL_DIR/bin/bootnode" /usr/local/bin/
            fi
            print_success "已复制到 /usr/local/bin/"
        else
            print_warn "无法写入 /usr/local/bin/，请手动复制或使用 sudo 权限"
        fi
    fi

    # 验证安装
    if [ -f "$INSTALL_DIR/bin/geth" ]; then
        "$INSTALL_DIR/bin/geth" version
        print_success "节点程序安装完成"
        print_info "二进制文件位置: $INSTALL_DIR/bin/"
    else
        print_error "geth 安装失败"
        exit 1
    fi
}

# 下载 genesis.json
download_genesis() {
    print_step "4" "下载创世配置"

    if [ -f "genesis.json" ]; then
        print_info "检测到已存在的 genesis.json"
        echo -e "是否重新下载? (y/n) [默认: n]: \c"
        read -r redownload
        if [[ ! "$redownload" =~ ^[Yy]$ ]]; then
            print_info "跳过下载，使用现有配置"
            return
        fi
    fi

    print_info "正在下载 genesis.json..."
    print_info "下载地址: $GENESIS_URL"

    # 尝试自动下载
    if download_file "$GENESIS_URL" "genesis.json"; then
        print_success "genesis.json 下载完成"
    else
        # 下载失败，提示手动下载
        echo ""
        print_warn "自动下载失败，请手动下载 genesis.json"
        print_info "下载地址: $GENESIS_URL"
        print_info "保存到: $INSTALL_DIR/genesis.json"
        echo ""
        echo -e "genesis.json 是否已准备好? (y/n): \c"
        read -r genesis_ready
        if [[ ! "$genesis_ready" =~ ^[Yy]$ ]]; then
            print_error "请先下载 genesis.json 后再运行此脚本"
            exit 1
        fi

        if [ ! -f "genesis.json" ]; then
            print_error "genesis.json 文件不存在"
            exit 1
        fi
    fi

    print_success "创世配置就绪"
}

# 生成 nodekey（固定节点身份）
generate_nodekey() {
    print_step "5" "生成节点身份 (nodekey)"

    local nodekey_file="$INSTALL_DIR/data/PIJSChain/nodekey"

    # 确保目录存在
    mkdir -p "$INSTALL_DIR/data/PIJSChain"

    if [ -f "$nodekey_file" ]; then
        print_info "检测到已存在的 nodekey"
        echo -e "是否保留现有 nodekey? (y/n) [默认: y]: \c"
        read -r keep_nodekey
        if [[ "$keep_nodekey" =~ ^[Nn]$ ]]; then
            rm -f "$nodekey_file"
        else
            print_info "保留现有 nodekey"
            # 显示现有 enode 地址
            if [ -f "$INSTALL_DIR/bin/bootnode" ]; then
                local enode_addr=$("$INSTALL_DIR/bin/bootnode" -nodekey "$nodekey_file" -writeaddress 2>/dev/null)
                if [ -n "$enode_addr" ]; then
                    print_info "节点 ID: $enode_addr"
                fi
            fi
            return
        fi
    fi

    print_info "生成新的 nodekey..."

    # 优先使用 bootnode 工具生成
    if [ -f "$INSTALL_DIR/bin/bootnode" ]; then
        "$INSTALL_DIR/bin/bootnode" -genkey "$nodekey_file"
        print_success "nodekey 已生成 (使用 bootnode)"
        # 显示 enode 地址
        local enode_addr=$("$INSTALL_DIR/bin/bootnode" -nodekey "$nodekey_file" -writeaddress 2>/dev/null)
        if [ -n "$enode_addr" ]; then
            print_info "节点 ID: $enode_addr"
        fi
    elif check_command bootnode; then
        bootnode -genkey "$nodekey_file"
        print_success "nodekey 已生成 (使用 bootnode)"
    elif check_command openssl; then
        # 备用方案：使用 openssl 生成 32 字节随机数
        openssl rand -hex 32 > "$nodekey_file"
        print_success "nodekey 已生成 (使用 openssl)"
    else
        # 最后方案：使用 /dev/urandom
        head -c 32 /dev/urandom | xxd -p -c 64 > "$nodekey_file"
        print_success "nodekey 已生成 (使用 urandom)"
    fi

    chmod 600 "$nodekey_file"

    print_info "nodekey 位置: $nodekey_file"
    print_warn "请妥善备份此文件，它决定了您的节点身份"
}

# 生成 BLS 密钥
generate_bls_key() {
    print_step "6" "生成 BLS 密钥"

    local bls_keyfile="$INSTALL_DIR/keys/bls-keystore.json"
    local bls_password="$INSTALL_DIR/keys/password.txt"

    if [ -f "$bls_keyfile" ]; then
        print_info "检测到已存在的 BLS 密钥"
        echo -e "是否保留现有 BLS 密钥? (y/n) [默认: y]: \c"
        read -r keep_bls
        if [[ "$keep_bls" =~ ^[Nn]$ ]]; then
            rm -f "$bls_keyfile" "$bls_password"
        else
            print_info "保留现有 BLS 密钥"
            return
        fi
    fi

    echo ""
    print_info "即将生成 BLS 密钥，请设置一个强密码"
    print_warn "此密码用于加密您的 BLS 私钥，请务必牢记！"
    echo ""

    # 获取密码
    while true; do
        echo -e "请输入 BLS 密钥密码: \c"
        read -rs bls_pwd
        echo ""
        echo -e "请再次输入密码确认: \c"
        read -rs bls_pwd_confirm
        echo ""

        if [ "$bls_pwd" != "$bls_pwd_confirm" ]; then
            print_error "两次输入的密码不一致，请重试"
            continue
        fi

        if [ ${#bls_pwd} -lt 8 ]; then
            print_error "密码长度至少需要 8 个字符"
            continue
        fi

        break
    done

    # 保存密码到文件
    echo "$bls_pwd" > "$bls_password"
    chmod 600 "$bls_password"

    # 生成 BLS 密钥
    print_info "正在生成 BLS 密钥..."

    # 使用 expect 或直接调用（根据 geth 实现）
    echo "$bls_pwd" | geth hybrid bls generate --save "$bls_keyfile" --password "$bls_password" 2>/dev/null || \
    geth hybrid bls generate --save "$bls_keyfile" --password "$bls_password"

    if [ ! -f "$bls_keyfile" ]; then
        print_error "BLS 密钥生成失败"
        exit 1
    fi

    chmod 600 "$bls_keyfile"

    # 显示公钥
    echo ""
    print_success "BLS 密钥生成成功"
    print_info "密钥文件: $bls_keyfile"
    print_info "密码文件: $bls_password"
    echo ""
    print_info "您的 BLS 公钥:"
    geth hybrid bls show --keyfile "$bls_keyfile" --password "$bls_password" 2>/dev/null | grep "Public Key" || \
    geth hybrid bls show --keyfile "$bls_keyfile" --password "$bls_password"
    echo ""
    print_warn "请妥善备份 BLS 密钥文件和密码，丢失后无法恢复！"
}

# 初始化区块链数据
init_blockchain() {
    print_step "7" "初始化区块链数据"

    local chaindata="$INSTALL_DIR/data/PIJSChain/chaindata"

    if [ -d "$chaindata" ] && [ "$(ls -A $chaindata 2>/dev/null)" ]; then
        print_info "检测到已初始化的区块链数据"
        echo -e "是否跳过初始化? (y/n) [默认: y]: \c"
        read -r skip_init
        if [[ ! "$skip_init" =~ ^[Nn]$ ]]; then
            print_info "跳过初始化"
            return
        fi
        print_warn "重新初始化将删除现有数据！"
        echo -e "确认删除并重新初始化? (yes/no): \c"
        read -r confirm_delete
        if [ "$confirm_delete" != "yes" ]; then
            print_info "取消重新初始化"
            return
        fi
        rm -rf "$INSTALL_DIR/data/PIJSChain/chaindata" "$INSTALL_DIR/data/PIJSChain/lightchaindata"
    fi

    print_info "正在初始化区块链数据..."
    geth init --datadir "$INSTALL_DIR/data" "$INSTALL_DIR/genesis.json"

    print_success "区块链数据初始化完成"
}

# 配置提款地址
configure_withdrawal() {
    print_step "8" "配置提款地址"

    echo ""
    print_info "提款地址用于接收您的质押奖励"
    print_warn "请确保您完全控制此地址的私钥"
    echo ""

    while true; do
        echo -e "请输入您的提款地址 (0x 开头): \c"
        read -r WITHDRAWAL_ADDRESS

        # 验证地址格式
        if [[ ! "$WITHDRAWAL_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            print_error "地址格式不正确，请输入有效的以太坊地址"
            continue
        fi

        echo -e "确认提款地址: $WITHDRAWAL_ADDRESS (y/n): \c"
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            break
        fi
    done

    print_success "提款地址已配置: $WITHDRAWAL_ADDRESS"
}

# 获取引导节点
get_bootnodes() {
    print_step "9" "配置引导节点"

    # 默认引导节点
    DEFAULT_BOOTNODES="enode://6f05512feacca0b15cd94ed2165e8f96b16cf346cb16ba7810a37bea05851b3887ee8ef3ee790090cb3352f37a710bcd035d6b0bfd8961287751532c2b0717fb@54.169.152.20:30303,enode://2d2370d19648032a525287645a38b6f1a87199e282cf9a99ebc25f3387e79780695b6c517bd8180be4e9b6b93c39502185960203c35d1ea067924f40e0fd50f1@104.16.132.181:30303,enode://3fb2f819279b92f256718081af1c26bb94c4056f9938f8f1897666f1612ad478e2d84fc56428d20f99201d958951bde4c3f732d27c52d0c5138d9174e744e115@52.76.128.119:30303"

    echo ""
    print_info "引导节点用于连接到 PIJS 网络"
    echo ""

    # 尝试下载 bootnodes.txt
    print_info "正在获取引导节点列表..."
    if download_file "$BOOTNODE_URL" "bootnodes.txt" 2>/dev/null; then
        # 读取 bootnodes.txt 并合并为逗号分隔的字符串
        BOOTNODES=$(cat bootnodes.txt | grep -v "^#" | grep -v "^$" | tr '\n' ',' | sed 's/,$//')
        if [ -n "$BOOTNODES" ]; then
            print_success "已从 bootnodes.txt 获取引导节点"
        else
            BOOTNODES="$DEFAULT_BOOTNODES"
            print_info "使用默认引导节点"
        fi
    else
        BOOTNODES="$DEFAULT_BOOTNODES"
        print_info "使用默认引导节点"
    fi

    print_success "引导节点已配置"
}

# 生成启动脚本
generate_start_script() {
    print_step "10" "生成启动脚本"

    local start_script="$INSTALL_DIR/start-node.sh"

    cat > "$start_script" << EOF
#!/bin/bash
# PIJS 节点启动脚本
# 生成时间: $(date)

# ==================== 配置 ====================
INSTALL_DIR="$INSTALL_DIR"
export PATH="\$INSTALL_DIR/bin:\$PATH"

DATADIR="\$INSTALL_DIR/data"
BLS_KEYFILE="\$INSTALL_DIR/keys/bls-keystore.json"
BLS_PASSWORD="\$INSTALL_DIR/keys/password.txt"
WITHDRAWAL_ADDRESS="$WITHDRAWAL_ADDRESS"
BOOTNODES="$BOOTNODES"

# 网络配置
NETWORK_ID="$CHAIN_ID"
HTTP_ADDR="0.0.0.0"
HTTP_PORT="8545"
# 安全警告：仅暴露安全的 API 模块！
# 安全：eth,net,web3,hybrid
# 危险（绝不可添加）：personal,admin,debug,miner
HTTP_API="eth,net,web3,hybrid"
WS_ADDR="0.0.0.0"
WS_PORT="8546"
# 安全警告：同 HTTP_API，不要添加 personal/admin/debug/miner
WS_API="eth,net,web3,hybrid"

# 性能配置
CACHE_SIZE="4096"

# 日志配置
LOG_DIR="\$INSTALL_DIR/logs"
LOG_FILE="\$LOG_DIR/geth.log"
LOG_MAXSIZE="100"
LOG_MAXBACKUPS="10"

# ==================== 启动检查 ====================
echo "========================================"
echo "  PIJS 共识节点启动"
echo "========================================"

# 检查必需文件
if [ ! -f "\$BLS_KEYFILE" ]; then
    echo "错误: BLS 密钥文件不存在: \$BLS_KEYFILE"
    exit 1
fi

if [ ! -f "\$BLS_PASSWORD" ]; then
    echo "错误: BLS 密码文件不存在: \$BLS_PASSWORD"
    exit 1
fi

# 创建日志目录
mkdir -p "\$LOG_DIR"

# 显示配置信息
echo ""
echo "配置信息:"
echo "  数据目录: \$DATADIR"
echo "  网络 ID: \$NETWORK_ID"
echo "  HTTP RPC: http://\$HTTP_ADDR:\$HTTP_PORT"
echo "  WebSocket: ws://\$WS_ADDR:\$WS_PORT"
echo "  提款地址: \$WITHDRAWAL_ADDRESS"
echo "  日志文件: \$LOG_FILE"
echo ""

# 安全警告
if [ "\$HTTP_ADDR" == "0.0.0.0" ] || [ "\$WS_ADDR" == "0.0.0.0" ]; then
    echo "========================================"
    echo "安全警告: RPC 接口对外暴露"
    echo "========================================"
    echo "建议配置防火墙限制访问 IP"
    echo ""
fi

# ==================== 检测公网IP ====================
detect_public_ip() {
    local ip=""
    # 尝试多个服务获取公网IP
    for service in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com" "https://ipecho.net/plain"; do
        ip=\$(curl -s --connect-timeout 3 --max-time 5 "\$service" 2>/dev/null | tr -d '[:space:]')
        # 验证IPv4格式
        if [[ "\$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\$ ]]; then
            echo "\$ip"
            return 0
        fi
    done
    return 1
}

# ==================== 启动节点 ====================
echo "正在启动节点..."

# 检测公网IP用于NAT配置
echo "正在检测公网IP..."
PUBLIC_IP=\$(detect_public_ip)
if [ -n "\$PUBLIC_IP" ]; then
    NAT_CONFIG="extip:\$PUBLIC_IP"
    echo "  检测到公网IP: \$PUBLIC_IP"
    echo "  NAT配置: \$NAT_CONFIG"
else
    NAT_CONFIG="any"
    echo "  未检测到公网IP，使用 NAT: any"
fi
echo ""

# 构建启动参数
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
    --nat "\$NAT_CONFIG"
)

# 启动 geth
exec geth "\${START_ARGS[@]}"
EOF

    chmod +x "$start_script"

    # 生成后台启动脚本
    local start_bg_script="$INSTALL_DIR/start-node-bg.sh"
    cat > "$start_bg_script" << EOF
#!/bin/bash
# PIJS 节点后台启动脚本

INSTALL_DIR="$INSTALL_DIR"
LOG_FILE="\$INSTALL_DIR/logs/geth.log"

echo "正在后台启动节点..."
nohup "\$INSTALL_DIR/start-node.sh" > /dev/null 2>&1 &

echo "节点已在后台启动"
echo "查看日志: tail -f \$LOG_FILE"
echo "停止节点: pkill -f 'geth.*--datadir.*pijs-node'"
EOF

    chmod +x "$start_bg_script"

    # 生成停止脚本
    local stop_script="$INSTALL_DIR/stop-node.sh"
    cat > "$stop_script" << EOF
#!/bin/bash
# PIJS 节点停止脚本

echo "正在停止节点..."
pkill -f "geth.*--datadir.*$INSTALL_DIR"

if [ \$? -eq 0 ]; then
    echo "节点已停止"
else
    echo "未找到运行中的节点"
fi
EOF

    chmod +x "$stop_script"

    print_success "启动脚本已生成:"
    echo "  - 前台启动: $start_script"
    echo "  - 后台启动: $start_bg_script"
    echo "  - 停止节点: $stop_script"
}

# 显示完成信息
show_completion() {
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}        部署完成！${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "${BLUE}节点信息:${NC}"
    echo "  安装目录: $INSTALL_DIR"
    echo "  数据目录: $INSTALL_DIR/data"
    echo "  BLS 密钥: $INSTALL_DIR/keys/bls-keystore.json"
    echo "  提款地址: $WITHDRAWAL_ADDRESS"
    echo ""
    echo -e "${BLUE}启动命令:${NC}"
    echo "  前台启动: $INSTALL_DIR/start-node.sh"
    echo "  后台启动: $INSTALL_DIR/start-node-bg.sh"
    echo "  停止节点: $INSTALL_DIR/stop-node.sh"
    echo ""
    echo -e "${BLUE}下一步操作:${NC}"
    echo "  1. 启动节点: cd $INSTALL_DIR && ./start-node.sh"
    echo "  2. 等待节点同步完成"
    echo "  3. 生成质押签名: geth hybrid bls deposit --keyfile ./keys/bls-keystore.json \\"
    echo "       --chainid $CHAIN_ID --address $WITHDRAWAL_ADDRESS --amount 10000 \\"
    echo "       --output deposit_data.json"
    echo "  4. 访问质押平台，上传 deposit_data.json 完成质押"
    echo ""
    echo -e "${YELLOW}重要提示:${NC}"
    echo "  - 请妥善备份 $INSTALL_DIR/keys/ 目录下的密钥文件"
    echo "  - 请妥善备份 $INSTALL_DIR/data/PIJSChain/nodekey 文件"
    echo "  - 首次同步可能需要数小时到数天（归档模式）"
    echo ""
    echo "============================================================"
}

# ==================== 主流程 ====================

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

# 运行主流程
main "$@"
