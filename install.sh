#!/bin/bash

install_script() {
    # 获取安装路径
    INSTALL_PATH=$(dialog --inputbox "请输入主备份脚本的安装路径" 8 60 "/usr/local/bin" 2>&1 >/dev/tty)
    
    # 获取备份时间
    BACKUP_TIME=$(dialog --inputbox "请输入每天的备份时间（24小时制，例如 04:00）" 8 60 "04:00" 2>&1 >/dev/tty)

    # 复制主备份脚本到安装路径
    cp "$(dirname "$0")/zfs_backup.sh" "$INSTALL_PATH/zfs_backup.sh"
    chmod +x "$INSTALL_PATH/zfs_backup.sh"

    # 获取配置
    get_config

    # 确认配置
    if confirm_config; then
        if test_configuration; then
            create_systemd_service
            show_info "ZFS 备份系统安装完成"
        else
            show_error "配置测试失败，安装中止"
        fi
    else
        show_info "安装已取消"
    fi
}

get_config() {
    config[source_dataset]=$(dialog --inputbox "请输入源数据集名称" 8 60 "poolname/dataset" 2>&1 >/dev/tty)
    config[remote_host]=$(dialog --inputbox "请输入远程主机信息（格式：user@host -p port）" 8 60 "user@remote_host -p 2233" 2>&1 >/dev/tty)
    config[remote_dataset]=$(dialog --inputbox "请输入远程数据集名称" 8 60 "remotepoolname/dataset" 2>&1 >/dev/tty)
    config[snapshot_retention_days]=$(dialog --inputbox "请输入本地快照保留天数" 8 60 "7" 2>&1 >/dev/tty)
    config[telegram_bot_token]=$(dialog --inputbox "请输入 Telegram Bot Token" 8 60 "YOUR_BOT_TOKEN" 2>&1 >/dev/tty)
    config[telegram_chat_id]=$(dialog --inputbox "请输入 Telegram Chat ID" 8 60 "YOUR_CHAT_ID" 2>&1 >/dev/tty)
    config[custom_report_header]=$(dialog --inputbox "请输入自定义报告标题（可选）" 8 60 "" 2>&1 >/dev/tty)
    config[enable_telegram_notify]=$(dialog --yesno "是否启用 Telegram 通知？" 8 40 && echo "true" || echo "false")
}

confirm_config() {
    local config_text=""
    for key in "${!config[@]}"; do
        config_text+="$key: ${config[$key]}\n"
    done
    config_text+="备份时间: $BACKUP_TIME"

    dialog --title "确认配置" --yesno "$config_text" 20 60
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
}
