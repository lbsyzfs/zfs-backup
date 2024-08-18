#!/bin/bash

# ZFS 备份系统管理脚本
# 版本: 1.0
# 作者: [您的名字]
# 日期: [当前日期]
#
# 介绍:
# 这个脚本用于管理 ZFS 备份系统的安装、配置和卸载。它提供了一个交互式界面，
# 允许用户轻松地设置和管理 ZFS 数据集的自动备份。主要功能包括：
#
# 1. 安装 ZFS 备份系统
# 2. 修改现有配置
# 3. 卸载 ZFS 备份系统
# 4. 依赖检查和安装
# 5. 配置测试
#
# 使用方法:
# 1. 以 root 用户或使用 sudo 运行此脚本
# 2. 按照菜单提示选择所需的操作
# 3. 根据提示输入必要的信息
#
# 注意事项:
# - 此脚本需要 root 权限运行
# - 确保远程主机已正确配置 SSH 密钥认证和 sudo 权限
# - 建议在使用前备份重要数据
#
# 依赖:
# - rsync, curl, yq, dialog (脚本会自动尝试安装这些依赖)
# - ZFS 文件系统
# - systemd

# 加载其他模块
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/install.sh"
source "$(dirname "$0")/uninstall.sh"
source "$(dirname "$0")/utils.sh"
source "$(dirname "$0")/ui.sh"
source "$(dirname "$0")/test.sh"

# 主函数
main() {
    check_root
    check_compatibility
    main_menu
}

# 运行主函数
main
