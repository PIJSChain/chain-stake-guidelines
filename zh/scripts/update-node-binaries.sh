#!/bin/bash
# ============================================================
# PIJS 二进制更新脚本
# 自动下载最新版本的二进制文件，并配置 PATH
# 不修改链数据，不更新创世配置
# ============================================================

set -euo pipefail

# ==================== 配置区域 ====================
GITHUB_REPO="PIJSChain/pijs"
LATEST_RELEASE_API="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
DEFAULT_INSTALL_DIR="$HOME/pijs-node"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==================== 工具函数 ====================

print_banner() {
    echo -e "${BLUE}"
    echo "============================================================"
    echo "    PIJS 二进制更新脚本"
    echo "    自动更新最新 geth / bootnode 等工具"
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
        print_error "未找到 curl 或 wget"
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
        print_error "未找到 curl 或 wget"
        exit 1
    fi
}

# ==================== 核心流程 ====================

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
            print_error "不支持的操作系统: $os"
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
            print_error "不支持的架构: $arch"
            exit 1
            ;;
    esac

    PLATFORM="${os}-${arch}"
    print_info "检测到平台: $PLATFORM"
}

fetch_latest_version() {
    print_step "1" "查询最新版本"

    local response
    response=$(download_text "$LATEST_RELEASE_API")
    LATEST_VERSION=$(printf '%s' "$response" | tr -d '\n' | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    if [ -z "$LATEST_VERSION" ]; then
        print_error "无法解析最新版本号"
        exit 1
    fi

    GITHUB_RELEASE="https://github.com/${GITHUB_REPO}/releases/download/${LATEST_VERSION}"
    print_success "最新版本: $LATEST_VERSION"
}

backup_binaries() {
    print_step "2" "备份现有二进制文件"

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
        print_success "已备份到: $backup_dir"
    else
        print_info "未发现需要备份的旧二进制文件"
    fi
}

install_latest_binaries() {
    print_step "3" "下载并安装最新二进制文件"

    local archive_name="geth-${LATEST_VERSION}-${PLATFORM}.tar.gz"
    local download_url="${GITHUB_RELEASE}/${archive_name}"
    local tmp_dir
    local installed=0

    tmp_dir=$(mktemp -d)
    trap "rm -rf '$tmp_dir'" EXIT

    print_info "下载地址: $download_url"
    download_file "$download_url" "$tmp_dir/$archive_name"

    if [ ! -s "$tmp_dir/$archive_name" ]; then
        print_error "下载失败或文件为空"
        exit 1
    fi

    tar -xzf "$tmp_dir/$archive_name" -C "$tmp_dir"
    mkdir -p "$INSTALL_DIR/bin"

    for binary in geth bootnode abigen clef evm rlpdump devp2p ethkey p2psim; do
        if [ -f "$tmp_dir/$binary" ]; then
            mv "$tmp_dir/$binary" "$INSTALL_DIR/bin/$binary"
            chmod +x "$INSTALL_DIR/bin/$binary"
            installed=1
            print_info "已更新: $binary"
        fi
    done

    if [ $installed -eq 0 ]; then
        print_error "压缩包中未找到可安装的二进制文件"
        exit 1
    fi

    CURRENT_VERSION=$($INSTALL_DIR/bin/geth version 2>/dev/null | awk '/Version:/ {print $2; exit}')
    CURRENT_VERSION=${CURRENT_VERSION:-}

    if [ -n "$CURRENT_VERSION" ] && [ "$CURRENT_VERSION" != "${LATEST_VERSION#v}" ] && [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
        print_success "二进制更新完成，Release 标签: ${LATEST_VERSION}，geth version: $CURRENT_VERSION"
    elif [ -n "$CURRENT_VERSION" ]; then
        print_success "二进制更新完成，当前版本: $CURRENT_VERSION"
    else
        print_success "二进制更新完成，Release 标签: $LATEST_VERSION"
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
    print_step "4" "配置环境变量"

    local bin_dir="$INSTALL_DIR/bin"
    local shell_rc
    local path_line="export PATH=\"$bin_dir:\$PATH\""

    export PATH="$bin_dir:$PATH"
    shell_rc=$(detect_shell_rc)
    mkdir -p "$(dirname "$shell_rc")"
    touch "$shell_rc"

    if grep -Fqs "$bin_dir" "$shell_rc"; then
        print_info "PATH 已存在于 $shell_rc"
    else
        {
            echo ""
            echo "# PIJS Node"
            echo "$path_line"
        } >> "$shell_rc"
        print_success "已写入 PATH 到: $shell_rc"
    fi
}

show_completion() {
    local shell_rc="$1"

    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}        二进制更新完成!${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "${BLUE}更新摘要:${NC}"
    echo "  最新版本: $LATEST_VERSION"
    echo "  安装目录: $INSTALL_DIR"
    echo "  二进制目录: $INSTALL_DIR/bin"
    echo "  链数据: 未修改"
    echo ""
    echo -e "${BLUE}后续建议:${NC}"
    echo "  1. 重新加载环境变量: source $shell_rc"
    echo "  2. 验证版本: geth version"
    echo "  3. 如果本次发布涉及硬分叉，请改用 upgrade-node.sh 完整升级"
    echo ""
}

main() {
    print_banner

    print_warn "本脚本只更新二进制文件和 PATH，不会更新 genesis.json 或重新 init。"
    echo ""
    read -r -p "请输入二进制安装目录 [$DEFAULT_INSTALL_DIR]: " INSTALL_DIR
    INSTALL_DIR=$(expand_path "${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}")

    mkdir -p "$INSTALL_DIR"
    print_info "目标目录: $INSTALL_DIR"

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
