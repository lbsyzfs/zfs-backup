#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 打印彩色消息
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查 root 权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
       print_message $RED "此脚本需要 root 权限运行"
       exit 1
    fi
}

# 检查系统兼容性
check_compatibility() {
    # 检查操作系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            debian|ubuntu)
                OS_TYPE="debian"
                ;;
            arch)
                OS_TYPE="arch"
                ;;
            gentoo)
                OS_TYPE="gentoo"
                ;;
            *)
                handle_error "不支持的操作系统: $ID"
                ;;
        esac
    elif [ -f /etc/gentoo-release ]; then
        OS_TYPE="gentoo"
    else
        handle_error "无法确定操作系统类型"
    fi

    # 检查必要的命令
    local missing_deps=()
    for cmd in zfs rsync curl yq dialog; do
        if ! command_exists $cmd; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        show_error "以下依赖未安装: ${missing_deps[*]}"
        if dialog --yesno "是否尝试安装缺失的依赖？" 8 40; then
            install_dependencies "${missing_deps[@]}"
        else
            handle_error "请手动安装缺失的依赖后重试。"
        fi
    fi

    # 检查 systemd
    if ! systemctl --version &> /dev/null; then
        handle_error "系统不支持 systemd"
    fi

    show_info "系统兼容性检查通过"
}

# 安装依赖
install_dependencies() {
    local deps=("$@")
    case "$OS_TYPE" in
        debian)
            sudo apt-get update
            sudo apt-get install -y "${deps[@]}"
            ;;
        arch)
            sudo pacman -Sy --noconfirm "${deps[@]}"
            ;;
        gentoo)
            sudo emerge --ask n "${deps[@]}"
            ;;
    esac

    # 特别处理 yq 的安装（如果需要）
    if [[ " ${deps[*]} " =~ " yq " ]] && ! command_exists yq; then
        install_yq
    fi
}

# 安装 yq
install_yq() {
    local YQ_VERSION="v4.30.6"
    local BINARY_URL="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
    
    show_info "正在安装 yq..."
    if sudo wget "$BINARY_URL" -O /usr/local/bin/yq && sudo chmod +x /usr/local/bin/yq; then
        show_info "yq 安装成功"
    else
        handle_error "yq 安装失败"
    fi
}

# 生成随机字符串
generate_random_string() {
    local length=$1
    tr -dc A-Za-z0-9 </dev/urandom | head -c $length ; echo ''
}

# 验证 IP 地址
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# 验证端口号
validate_port() {
    local port=$1
    if [[ $port =~ ^[0-9]+$ ]] && [ $port -ge 1 ] && [ $port -le 65535 ]; then
        return 0
    else
        return 1
    fi
}
