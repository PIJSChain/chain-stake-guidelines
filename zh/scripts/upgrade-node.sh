#!/bin/bash
# ============================================================
# PIJS 共识节点升级脚本
# 用于硬分叉升级 - 仅更新客户端和链配置
# 不会删除现有链数据
# ============================================================

set -e

# ==================== 配置区域 ====================
GITHUB_RELEASE="https://github.com/PIJSChain/pijs/releases/download/v1.25.6k"
GETH_VERSION="v1.25.6k"
GENESIS_URL="https://github.com/PIJSChain/pijs/releases/download/v1.25.6k/genesis.json"

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

    local geth_filename="geth-${PLATFORM}"
    local download_url="${GITHUB_RELEASE}/${geth_filename}"

    print_info "下载地址: $download_url"

    cd "$INSTALL_DIR/bin"

    # 删除旧文件
    rm -f geth geth-*

    if command -v curl &> /dev/null; then
        curl -L -o geth "$download_url" --progress-bar
    elif command -v wget &> /dev/null; then
        wget -O geth "$download_url" --show-progress
    else
        print_error "未找到 curl 或 wget"
        exit 1
    fi

    chmod +x geth

    # 验证下载
    if [ ! -f "geth" ] || [ ! -s "geth" ]; then
        print_error "下载失败或文件为空"
        exit 1
    fi

    # 显示版本
    local version=$(./geth version 2>/dev/null | grep "Version:" | head -1 || echo "未知")
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
        curl -L -o genesis.json "$GENESIS_URL" --progress-bar
    elif command -v wget &> /dev/null; then
        wget -O genesis.json "$GENESIS_URL" --show-progress
    fi

    if [ ! -f "genesis.json" ] || [ ! -s "genesis.json" ]; then
        print_error "下载 genesis.json 失败"
        exit 1
    fi

    print_success "创世配置已下载"
}

# 重新初始化链配置（用于硬分叉）
reinit_chain() {
    print_step "5" "重新初始化链配置（硬分叉）"

    print_warn "此操作仅更新链配置，现有链数据将被保留"
    echo ""

    # 使用新的创世文件运行 init（与部署脚本保持一致的绝对路径）
    print_info "执行: geth init --datadir \"$INSTALL_DIR/data\" \"$INSTALL_DIR/genesis.json\""

    "$INSTALL_DIR/bin/geth" init --datadir "$INSTALL_DIR/data" "$INSTALL_DIR/genesis.json"

    if [ $? -eq 0 ]; then
        print_success "链配置更新成功"
    else
        print_error "链配置更新失败"
        exit 1
    fi
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

    show_completion
}

# 运行主流程
main "$@"
