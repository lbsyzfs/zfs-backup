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

# 安装依赖
install_dependencies() {
    print_message $YELLOW "正在检查并安装必要的依赖..."
    
    local need_install=false
    local to_install=""

    for cmd in rsync curl yq dialog; do
        if ! command_exists $cmd; then
            need_install=true
            to_install="$to_install $cmd"
        fi
    done

    if [ "$need_install" = true ]; then
        print_message $YELLOW "需要安装以下软件包:$to_install"
        
        # 检测系统类型并安装
        if [ -f /etc/debian_version ]; then
            sudo apt-get update
            sudo apt-get install -y $to_install
        elif [ -f /etc/arch-release ]; then
            sudo pacman -Sy --noconfirm $to_install
        elif [ -f /etc/gentoo-release ]; then
            sudo emerge --ask n $to_install
        else
            print_message $RED "无法确定系统类型，请手动安装 rsync, curl, yq 和 dialog"
            exit 1
        fi

        # 再次检查安装是否成功
        for cmd in rsync curl yq dialog; do
            if ! command_exists $cmd; then
                print_message $RED "$cmd 安装失败，请手动安装"
                exit 1
            fi
        done
        print_message $GREEN "所有依赖已成功安装"
    else
        print_message $GREEN "所有必要的依赖已经安装"
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
