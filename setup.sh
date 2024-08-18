#!/bin/bash

# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
   echo "此脚本需要 root 权限运行"
   exit 1
fi

# 安装依赖
apt-get update
apt-get install -y rsync curl yq dialog

# 创建安装目录
mkdir -p /usr/local/share/zfs_backup

# 复制文件
cp zfs_backup_manager.sh /usr/local/bin/
cp zfs_backup.sh /usr/local/bin/
cp *.sh /usr/local/share/zfs_backup/

# 设置权限
chmod +x /usr/local/bin/zfs_backup_manager.sh
chmod +x /usr/local/bin/zfs_backup.sh

echo "安装完成。请运行 'sudo zfs_backup_manager.sh' 来配置和管理备份系统。"
