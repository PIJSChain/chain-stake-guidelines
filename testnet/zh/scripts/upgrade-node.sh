#!/bin/bash
# ============================================================
# PIJS 共识节点升级脚本
# 用于硬分叉升级 - 仅更新客户端和链配置
# 不会删除现有链数据
# ============================================================

set -e

# ==================== 配置区域 ====================
GITHUB_RELEASE="https://github.com/PIJSChain/pijs/releases/download/v1.26.0"
GETH_VERSION="v1.26.0"
GENESIS_URL="https://github.com/PIJSChain/pijs/releases/download/v1.26.0/genesis.json"

# 默认目录
DEFAULT_INSTALL_DIR="$HOME/pijs-node"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ==================== 工具函数 ====================

print_banner() {
    echo -e "${BLUE}"
    echo "============================================================"
    echo "    PIJS 共识节点升级脚本"
    echo "    目标版本: $GETH_VERSION"
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
    echo -e "${GREEN}[完成]${NC} $1"
}

# 校验文件是否为完整的 gzip 压缩包(防止下载被截断或重定向到 HTML)
# 用法: verify_gzip_archive <文件路径> [最小字节数]
verify_gzip_archive() {
    local path="$1"
    local min_size="${2:-1048576}"

    if [ ! -f "$path" ]; then
        print_error "下载的文件不存在: $path"
        return 1
    fi

    local size
    size=$(wc -c < "$path" 2>/dev/null | tr -d ' ')
    if [ -z "$size" ] || [ "$size" -lt "$min_size" ]; then
        print_error "下载文件过小(${size:-0} 字节, 期望 >= ${min_size} 字节)，可能被截断"
        return 1
    fi

    # 校验 gzip 魔数 (1f 8b)
    local magic
    magic=$(head -c 2 "$path" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
    if [ "$magic" != "1f8b" ]; then
        print_error "下载文件不是有效的 gzip 压缩包(魔数=${magic:-unknown})，可能下载被截断或被重定向到 HTML"
        return 1
    fi

    return 0
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

# 检查节点是否运行
check_node_running() {
    # 使用 ps + grep 组合，避免 pgrep -f 匹配到脚本自身
    # 先检查是否有 geth 进程，再检查是否包含目标目录
    local geth_pids=$(pgrep -x geth 2>/dev/null)
    if [ -z "$geth_pids" ]; then
        return 1
    fi

    # 检查是否有 geth 进程使用了目标目录
    for pid in $geth_pids; do
        if [ -f "/proc/$pid/cmdline" ]; then
            if tr '\0' ' ' < "/proc/$pid/cmdline" | grep -q "$INSTALL_DIR"; then
                return 0
            fi
        else
            # macOS 兼容：使用 ps
            if ps -p "$pid" -o args= 2>/dev/null | grep -q "$INSTALL_DIR"; then
                return 0
            fi
        fi
    done
    return 1
}

# 停止运行中的节点
stop_node() {
    print_step "1" "检查节点状态"

    if check_node_running; then
        print_warn "节点正在运行，正在停止..."

        # 只停止进程名为 geth 且使用目标目录的进程
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
            print_error "无法停止节点，请先手动停止"
            exit 1
        fi
        print_success "节点已停止"
    else
        print_info "节点未运行"
    fi
}

# 备份当前客户端
backup_client() {
    print_step "2" "备份当前客户端"

    local backup_dir="$INSTALL_DIR/backup"
    mkdir -p "$backup_dir"

    if [ -f "$INSTALL_DIR/bin/geth" ]; then
        local backup_name="geth.backup.$(date +%Y%m%d%H%M%S)"
        cp "$INSTALL_DIR/bin/geth" "$backup_dir/$backup_name"
        print_success "当前客户端已备份至: $backup_dir/$backup_name"
    else
        print_info "没有现有客户端需要备份"
    fi
}

# 下载新客户端
download_client() {
    print_step "3" "下载新客户端 ($GETH_VERSION)"

    local geth_tar="geth-${GETH_VERSION}-${PLATFORM}.tar.gz"
    local download_url="${GITHUB_RELEASE}/${geth_tar}"
    local bin_dir="$INSTALL_DIR/bin"

    print_info "下载地址: $download_url"

    # 进入安装目录
    cd "$INSTALL_DIR"

    # 下载压缩包
    rm -f "$geth_tar"

    if command -v curl &> /dev/null; then
        curl -L -o "$geth_tar" "$download_url" --progress-bar
    elif command -v wget &> /dev/null; then
        wget -O "$geth_tar" "$download_url" --show-progress
    else
        print_error "未找到 curl 或 wget"
        exit 1
    fi

    # 校验下载完整性(大小 + gzip 魔数)
    if ! verify_gzip_archive "$geth_tar"; then
        rm -f "$geth_tar"
        print_error "请检查网络后重试，或手动下载: $download_url"
        exit 1
    fi

    # 解压(显式检查 tar 退出码，失败立即终止)
    print_info "解压文件..."
    if ! tar -xzf "$geth_tar"; then
        print_error "解压失败，压缩包可能损坏"
        rm -f "$geth_tar"
        exit 1
    fi

    # 确保 bin 目录存在
    mkdir -p "$bin_dir"

    # 移动所有二进制文件到 bin 目录
    for binary in geth bootnode abigen clef evm rlpdump devp2p ethkey p2psim; do
        if [ -f "$binary" ]; then
            mv "$binary" "$bin_dir/"
            chmod +x "$bin_dir/$binary"
        fi
    done

    # 清理压缩包
    rm -f "$geth_tar"

    # 校验 geth 已成功生成
    if [ ! -x "$bin_dir/geth" ]; then
        print_error "解压完成但 $bin_dir/geth 未找到，压缩包内容异常"
        exit 1
    fi

    # 校验 geth 可执行
    if ! "$bin_dir/geth" version >/dev/null 2>&1; then
        print_error "geth 无法运行 — 二进制文件可能损坏"
        "$bin_dir/geth" version || true
        exit 1
    fi

    # 更新 /usr/local/bin 中的二进制文件
    if [ -f "/usr/local/bin/geth" ]; then
        print_info "检测到 /usr/local/bin/geth，正在更新..."
        if [ -w "/usr/local/bin" ]; then
            cp "$bin_dir/geth" /usr/local/bin/geth
            [ -f "$bin_dir/bootnode" ] && cp "$bin_dir/bootnode" /usr/local/bin/bootnode
            [ -f "$bin_dir/devp2p" ] && cp "$bin_dir/devp2p" /usr/local/bin/devp2p
            print_success "已更新 /usr/local/bin 中的二进制文件"
        elif command -v sudo &> /dev/null; then
            sudo cp "$bin_dir/geth" /usr/local/bin/geth
            [ -f "$bin_dir/bootnode" ] && sudo cp "$bin_dir/bootnode" /usr/local/bin/bootnode
            [ -f "$bin_dir/devp2p" ] && sudo cp "$bin_dir/devp2p" /usr/local/bin/devp2p
            print_success "已更新 /usr/local/bin 中的二进制文件"
        else
            print_warn "无法更新 /usr/local/bin，请手动复制"
        fi
    fi

    # 显示版本
    local version=$("$bin_dir/geth" version 2>/dev/null | grep "Version:" | head -1 || echo "未知")
    print_success "新客户端已下载: $version"
}

# 下载创世文件
download_genesis() {
    print_step "4" "下载创世配置"

    cd "$INSTALL_DIR"

    # 备份旧的创世文件
    if [ -f "genesis.json" ]; then
        mv genesis.json "genesis.json.backup.$(date +%Y%m%d%H%M%S)"
    fi

    print_info "下载地址: $GENESIS_URL"

    if command -v curl &> /dev/null; then
        curl -fL -o genesis.json "$GENESIS_URL" --progress-bar || true
    elif command -v wget &> /dev/null; then
        wget -O genesis.json "$GENESIS_URL" --show-progress || true
    fi

    local genesis_size
    genesis_size=$(wc -c < genesis.json 2>/dev/null | tr -d ' ' || echo 0)
    if [ ! -f "genesis.json" ] || [ "${genesis_size:-0}" -lt 100 ]; then
        print_error "下载 genesis.json 失败或文件过小(${genesis_size:-0} 字节)"
        rm -f genesis.json
        exit 1
    fi

    # 校验是否为合法 JSON
    if command -v python3 &> /dev/null; then
        if ! python3 -c "import json,sys; json.load(open('genesis.json'))" 2>/dev/null; then
            print_error "genesis.json 不是合法的 JSON，可能下载被截断"
            rm -f genesis.json
            exit 1
        fi
    elif command -v python &> /dev/null; then
        if ! python -c "import json,sys; json.load(open('genesis.json'))" 2>/dev/null; then
            print_error "genesis.json 不是合法的 JSON，可能下载被截断"
            rm -f genesis.json
            exit 1
        fi
    fi

    print_success "创世配置已下载"
}

# 重新初始化链配置（用于硬分叉）
reinit_chain() {
    print_step "5" "重新初始化链配置（硬分叉）"

    print_warn "此操作仅更新链配置，现有链数据将被保留"
    echo ""

    # 使用新的创世文件运行 init（与部署脚本保持一致）
    print_info "执行: geth init --datadir \"$INSTALL_DIR/data\" \"$INSTALL_DIR/genesis.json\""

    geth init --datadir "$INSTALL_DIR/data" "$INSTALL_DIR/genesis.json"

    if [ $? -eq 0 ]; then
        print_success "链配置更新成功"
    else
        print_error "链配置更新失败"
        exit 1
    fi
}

# 交互式选择 NAT 模式（与 setup 一致）
choose_nat_mode() {
    echo ""
    echo "请选择您的网络环境:"
    echo ""
    echo "  1) 固定公网IP - 服务器有固定的公网IP地址"
    echo "  2) NAT环境   - 位于路由器/NAT网关后面（家庭网络、部分云服务器）"
    echo "  3) 自动检测  - 每次启动时自动检测公网IP（推荐）"
    echo ""

    while true; do
        read -p "请选择 [1-3] (默认: 3): " network_choice
        network_choice=${network_choice:-3}

        case $network_choice in
            1)
                echo ""
                echo "正在检测您的公网IP..."
                local detected_ip=""
                for service in "https://ip.sb" "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com" "https://ipinfo.io/ip"; do
                    detected_ip=$(curl -sA "curl/7" --connect-timeout 3 --max-time 5 "$service" 2>/dev/null | tr -d '[:space:]')
                    if [[ "$detected_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                        break
                    fi
                done

                if [ -n "$detected_ip" ]; then
                    echo "检测到IP: $detected_ip"
                    read -p "使用此IP? (y/n, 或输入其他IP): " ip_confirm
                    if [ "$ip_confirm" = "y" ] || [ "$ip_confirm" = "Y" ] || [ -z "$ip_confirm" ]; then
                        NAT_MODE="extip"
                        PUBLIC_IP="$detected_ip"
                    elif [[ "$ip_confirm" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                        NAT_MODE="extip"
                        PUBLIC_IP="$ip_confirm"
                    else
                        echo "输入无效，请重试"
                        continue
                    fi
                else
                    read -p "无法检测公网IP，请手动输入您的公网IP: " PUBLIC_IP
                    if [[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                        NAT_MODE="extip"
                    else
                        print_error "IP地址格式无效"
                        continue
                    fi
                fi
                break
                ;;
            2)
                NAT_MODE="any"
                PUBLIC_IP=""
                print_info "已选择NAT模式，将使用UPnP/NAT-PMP自动端口映射"
                break
                ;;
            3)
                NAT_MODE="auto"
                PUBLIC_IP=""
                print_info "自动检测模式，每次启动时检测公网IP"
                break
                ;;
            *)
                echo "选择无效，请输入 1、2 或 3"
                ;;
        esac
    done
}

# 根据 NAT_MODE 输出 NAT 配置块，供嵌入到 start-node.sh
emit_nat_section() {
    if [ "$NAT_MODE" = "extip" ]; then
        cat << EOF
# 固定公网IP模式
NAT_CONFIG="extip:$PUBLIC_IP"
echo "NAT配置: \$NAT_CONFIG (固定公网IP)"
EOF
    elif [ "$NAT_MODE" = "any" ]; then
        cat << EOF
# NAT环境模式 (UPnP/NAT-PMP)
NAT_CONFIG="any"
echo "NAT配置: \$NAT_CONFIG (自动端口映射)"
EOF
    else
        cat << 'AUTODETECT'
# 自动检测公网IP
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

echo "正在检测公网IP..."
DETECTED_IP=$(detect_public_ip)
if [ -n "$DETECTED_IP" ]; then
    NAT_CONFIG="extip:$DETECTED_IP"
    echo "  检测到公网IP: $DETECTED_IP"
    echo "  NAT配置: $NAT_CONFIG"
else
    NAT_CONFIG="any"
    echo "  未检测到公网IP，使用 NAT: any"
fi
AUTODETECT
    fi
}

# 可选：重新配置网络
reconfigure_network() {
    print_step "6" "网络配置（可选）"

    echo ""
    echo "此步骤可以重新配置节点的 NAT 网络模式"
    echo "仅在以下情况需要执行："
    echo "  - 服务器 IP 变更"
    echo "  - 从家用网络迁移到云主机（反之亦然）"
    echo "  - 升级前 NAT 配置不正确（如 peer 数长期为 0）"
    echo ""

    read -p "是否重新配置网络？(y/N): " reset_network
    if [ "$reset_network" != "y" ] && [ "$reset_network" != "Y" ]; then
        print_info "跳过网络配置（保持现有设置）"
        return
    fi

    local start_script="$INSTALL_DIR/start-node.sh"
    if [ ! -f "$start_script" ]; then
        print_error "未找到 $start_script"
        print_error "建议重新运行 setup-node-testnet.sh 重新部署"
        return
    fi

    # 检查是否为新版 start-node.sh（有明确的 NAT 配置标记）
    if ! grep -q "^# ==================== NAT 配置 ====================$" "$start_script" || \
       ! grep -q "^# ==================== 启动节点 ====================$" "$start_script"; then
        print_error "start-node.sh 格式不兼容（可能是旧版本脚本生成的）"
        print_error "建议重新运行 setup-node-testnet.sh 重新部署"
        return
    fi

    # 询问 NAT 模式
    choose_nat_mode

    # 生成新的 NAT 配置块到临时文件
    local nat_block_file
    nat_block_file=$(mktemp)
    emit_nat_section > "$nat_block_file"

    # 备份现有 start-node.sh
    local backup_dir="$INSTALL_DIR/backup"
    mkdir -p "$backup_dir"
    local backup_file="$backup_dir/start-node.sh.$(date +%Y%m%d%H%M%S)"
    cp "$start_script" "$backup_file"
    print_info "已备份原 start-node.sh 至: $backup_file"

    # 使用 awk 替换两个标记之间的内容
    local temp_script
    temp_script=$(mktemp)
    awk -v nat_file="$nat_block_file" '
        /^# ==================== NAT 配置 ====================$/ {
            in_nat = 1
            print
            while ((getline line < nat_file) > 0) print line
            close(nat_file)
            next
        }
        /^# ==================== 启动节点 ====================$/ {
            in_nat = 0
        }
        !in_nat { print }
    ' "$start_script" > "$temp_script"

    mv "$temp_script" "$start_script"
    rm -f "$nat_block_file"
    chmod +x "$start_script"

    print_success "网络配置已更新为: $NAT_MODE"
}

# 显示完成信息
show_completion() {
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}        升级完成!${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "${BLUE}升级摘要:${NC}"
    echo "  新版本: $GETH_VERSION"
    echo "  安装目录: $INSTALL_DIR"
    echo "  链数据: 已保留"
    echo ""
    echo -e "${BLUE}后续步骤:${NC}"
    echo "  1. 启动节点: $INSTALL_DIR/start-node.sh"
    echo "  2. 或后台启动: $INSTALL_DIR/start-node-bg.sh"
    echo "  3. 查看日志: tail -f $INSTALL_DIR/logs/geth.log"
    echo ""
    echo -e "${YELLOW}重要提示:${NC}"
    echo "  - 如升级失败，可从 $INSTALL_DIR/backup/ 恢复备份"
    echo "  - 重启后请监控日志，确保节点正常同步"
    echo ""
    echo -e "${BLUE}网络连接诊断:${NC}"
    echo "  如果启动后 peerCount 为 0，可使用 devp2p 工具检测引导节点连通性:"
    echo -e "  ${CYAN}devp2p discv4 ping <enode-url>${NC}"
    echo "  示例: devp2p discv4 ping enode://6f05...fb@54.169.152.20:30303"
    echo ""
}

# ==================== 主流程 ====================

main() {
    print_banner

    # 获取安装目录
    read -p "请输入节点安装目录 [$DEFAULT_INSTALL_DIR]: " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}

    # 验证目录存在
    if [ ! -d "$INSTALL_DIR" ]; then
        print_error "目录不存在: $INSTALL_DIR"
        exit 1
    fi

    if [ ! -d "$INSTALL_DIR/data" ]; then
        print_error "未找到数据目录，这是有效的 PIJS 节点安装吗？"
        exit 1
    fi

    print_info "升级节点: $INSTALL_DIR"
    echo ""

    # 确认升级
    echo -e "${YELLOW}警告: 这将把您的节点升级到版本 $GETH_VERSION${NC}"
    echo "链数据将被保留，仅更新客户端和配置。"
    echo ""
    read -p "确认继续升级? (y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "升级已取消"
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

# 运行主流程
main "$@"
