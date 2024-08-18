#!/bin/bash

# 全局变量，用于跟踪已创建的资源
created_resources=()

# 记录创建的资源
record_resource() {
    created_resources+=("$1")
}

# 清理函数
cleanup() {
    for resource in "${created_resources[@]}"; do
        case $resource in
            "service")
                systemctl stop zfs-backup.timer
                systemctl disable zfs-backup.timer
                rm -f /etc/systemd/system/zfs-backup.service
                rm -f /etc/systemd/system/zfs-backup.timer
                systemctl daemon-reload
                ;;
            "script")
                rm -f "$INSTALL_PATH/zfs_backup.sh"
                ;;
            "config")
                rm -f /etc/zfs_backup/config.yaml
                ;;
        esac
    done
}

# 错误处理函数
handle_error() {
    local error_message="$1"
    show_error "安装失败: $error_message"
    show_info "正在回滚更改..."
    cleanup
    show_info "回滚完成。"
    exit 1
}

install_script() {
    # 获取安装路径
    INSTALL_PATH=$(dialog --inputbox "请输入主备份脚本的安装路径" 8 60 "/usr/local/bin" 2>&1 >/dev/tty)
    
    # 获取备份时间
    BACKUP_TIME=$(dialog --inputbox "请输入每天的备份时间（24小时制，例如 04:00）" 8 60 "04:00" 2>&1 >/dev/tty)

    # 复制主备份脚本到安装路径
    cp "$(dirname "$0")/zfs_backup.sh" "$INSTALL_PATH/zfs_backup.sh" || handle_error "复制备份脚本失败"
    chmod +x "$INSTALL_PATH/zfs_backup.sh" || handle_error "设置脚本执行权限失败"
    record_resource "script"

    # 获取配置
    get_config

    # 确认配置
    if confirm_config; then
        if test_configuration; then
            create_systemd_service
            show_info "ZFS 备份系统安装完成"
        else
            handle_error "配置测试失败"
        fi
    else
        handle_error "安装已取消"
    fi
}

confirm_config() {
    local config_text=""
    for key in "${!config[@]}"; do
        config_text+="$key: ${config[$key]}\n"
    done
    config_text+="备份时间: $BACKUP_TIME"

    dialog --title "确认配置" --yesno "$config_text" 20 60
    return $?
}

create_systemd_service() {
    # 创建 systemd 服务文件
    cat << EOF > /etc/systemd/system/zfs-backup.service
[Unit]
Description=ZFS Backup Service
After=network.target

[Service]
Type=oneshot
ExecStart=$INSTALL_PATH/zfs_backup.sh
User=root

[Install]
WantedBy=multi-user.target
EOF
    record_resource "service"

    # 创建 systemd timer 文件
    cat << EOF > /etc/systemd/system/zfs-backup.timer
[Unit]
Description=Run ZFS Backup daily

[Timer]
OnCalendar=*-*-* $BACKUP_TIME:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
    record_resource "service"

    # 重新加载 systemd，启用并启动 timer
    systemctl daemon-reload
    systemctl enable zfs-backup.timer
    systemctl start zfs-backup.timer

    # 保存配置到文件
    mkdir -p /etc/zfs_backup
    echo "install_path: $INSTALL_PATH" > /etc/zfs_backup/config.yaml
    for key in "${!config[@]}"; do
        echo "$key: ${config[$key]}" >> /etc/zfs_backup/config.yaml
    done
    chmod 600 /etc/zfs_backup/config.yaml
    record_resource "config"
}
