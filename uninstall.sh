#!/bin/bash

uninstall_script() {
    if dialog --title "确认卸载" --yesno "确定要卸载 ZFS 备份系统吗？" 8 40; then
        # 停止并禁用 systemd 服务
        systemctl stop zfs-backup.timer
        systemctl disable zfs-backup.timer
        systemctl stop zfs-backup.service
        systemctl disable zfs-backup.service

        # 删除 systemd 文件
        rm -f /etc/systemd/system/zfs-backup.service
        rm -f /etc/systemd/system/zfs-backup.timer

        # 删除主脚本
        local install_path=$(yq e '.install_path' /etc/zfs_backup/config.yaml)
        rm -f "${install_path}/zfs_backup.sh"

        # 删除配置文件
        rm -rf /etc/zfs_backup

        # 重新加载 systemd
        systemctl daemon-reload

        show_info "ZFS 备份系统已卸载"
    else
        show_info "卸载已取消"
    fi
}

# 如果直接运行此脚本，执行卸载函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    uninstall_script
fi
