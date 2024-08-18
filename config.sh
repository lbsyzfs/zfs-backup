#!/bin/bash

# 加载配置
load_config() {
    if [ -f "/etc/zfs_backup/config.yaml" ]; then
        config=$(yq e -o=json /etc/zfs_backup/config.yaml)
    else
        config="{}"
    fi
}

# 保存配置
save_config() {
    mkdir -p /etc/zfs_backup
    yq e -P . <<< "$config" > /etc/zfs_backup/config.yaml
    chmod 600 /etc/zfs_backup/config.yaml
}

# 修改配置
modify_config() {
    load_config
    while true; do
        local choice=$(dialog --clear --title "修改配置" \
                    --menu "请选择要修改的配置项：" 15 60 8 \
                    1 "源数据集" \
                    2 "远程主机" \
                    3 "远程数据集" \
                    4 "快照保留天数" \
                    5 "Telegram Bot Token" \
                    6 "Telegram Chat ID" \
                    7 "自定义报告标题" \
                    8 "返回主菜单" \
                    2>&1 >/dev/tty)

        case $choice in
            1) modify_config_item "source_dataset" "源数据集" ;;
            2) modify_config_item "remote_host" "远程主机" ;;
            3) modify_config_item "remote_dataset" "远程数据集" ;;
            4) modify_config_item "snapshot_retention_days" "快照保留天数" ;;
            5) modify_config_item "telegram_bot_token" "Telegram Bot Token" ;;
            6) modify_config_item "telegram_chat_id" "Telegram Chat ID" ;;
            7) modify_config_item "custom_report_header" "自定义报告标题" ;;
            8) break ;;
            *) show_error "无效选项，请重新选择" ;;
        esac
    done
    save_config
    show_info "配置已更新"
}

# 修改单个配置项
modify_config_item() {
    local key=$1
    local title=$2
    local current_value=$(echo "$config" | yq e ".$key" -)
    local new_value=$(dialog --inputbox "请输入新的$title值" 8 60 "$current_value" 2>&1 >/dev/tty)
    
    if [ -n "$new_value" ]; then
        config=$(echo "$config" | yq e ".$key = \"$new_value\"" -)
        show_help "$title" "已更新$title:\n旧值: $current_value\n新值: $new_value"
    fi
}

# 获取配置值
get_config_value() {
    local key=$1
    echo "$config" | yq e ".$key" -
}

# 获取配置
get_config() {
    config[source_dataset]=$(dialog --inputbox "请输入源数据集名称" 8 60 "poolname/dataset" 2>&1 >/dev/tty)
    config[remote_host]=$(dialog --inputbox "请输入远程主机信息（格式：user@host）" 8 60 "user@remote_host" 2>&1 >/dev/tty)
    config[remote_port]=$(dialog --inputbox "请输入SSH端口" 8 60 "22" 2>&1 >/dev/tty)
    config[remote_dataset]=$(dialog --inputbox "请输入远程数据集名称" 8 60 "remotepoolname/dataset" 2>&1 >/dev/tty)
    config[snapshot_retention_days]=$(dialog --inputbox "请输入本地快照保留天数" 8 60 "7" 2>&1 >/dev/tty)
    config[telegram_bot_token]=$(dialog --inputbox "请输入 Telegram Bot Token" 8 60 "YOUR_BOT_TOKEN" 2>&1 >/dev/tty)
    config[telegram_chat_id]=$(dialog --inputbox "请输入 Telegram Chat ID" 8 60 "YOUR_CHAT_ID" 2>&1 >/dev/tty)
    config[custom_report_header]=$(dialog --inputbox "请输入自定义报告标题（可选）" 8 60 "" 2>&1 >/dev/tty)
    config[enable_telegram_notify]=$(dialog --yesno "是否启用 Telegram 通知？" 8 40 && echo "true" || echo "false")
    config[log_file]=$(dialog --inputbox "请输入日志文件路径" 8 60 "/var/log/zfs_backup.log" 2>&1 >/dev/tty)

    # SSH 密钥选项
    ssh_option=$(dialog --menu "选择 SSH 密钥选项:" 15 60 3 \
        1 "使用现有密钥文件" \
        2 "输入私钥内容" \
        3 "生成新密钥对" \
        2>&1 >/dev/tty)

    case $ssh_option in
        1)
            config[ssh_key_path]=$(dialog --inputbox "请输入 SSH 私钥路径" 8 60 "~/.ssh/id_rsa" 2>&1 >/dev/tty)
            if [ -f "${config[ssh_key_path]}" ]; then
                if [ -f "${config[ssh_key_path]}.pub" ]; then
                    local pub_key=$(cat "${config[ssh_key_path]}.pub")
                    if dialog --yesno "是否需要对公钥进行命令限制？\n\n注意：如果这个密钥用于其他用途，添加限制可能会影响其他功能。" 10 60; then
                        show_key_restriction_info "$pub_key"
                        config[ssh_key_restricted]=true
                    else
                        dialog --msgbox "您选择不对公钥进行限制。请确保远程主机上的配置安全。" 8 60
                        config[ssh_key_restricted]=false
                    fi
                else
                    show_error "找不到对应的公钥文件：${config[ssh_key_path]}.pub"
                    show_info "请确保远程主机上已正确配置了对应的公钥。"
                fi
            else
                show_error "找不到指定的私钥文件：${config[ssh_key_path]}"
                return 1
            fi
            ;;
        2)
            config[ssh_key]=$(dialog --inputbox "请输入 SSH 私钥内容" 15 60 "" 2>&1 >/dev/tty)
            dialog --msgbox "请确保远程主机上已正确配置了对应的公钥，并考虑对公钥进行命令限制以提高安全性。" 10 60
            config[ssh_key_restricted]=false
            ;;
        3)
            generate_ssh_key
            config[ssh_key_restricted]=true
            ;;
    esac
}

show_key_restriction_info() {
    local pub_key="$1"
    local zfs_commands="sudo zfs list -H -t snapshot -o name,
                        sudo zfs destroy,
                        sudo zfs receive,
                        sudo zfs rename"
    local restricted_pub_key="command=\"${zfs_commands// /}\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ${pub_key}"
    
    dialog --msgbox "请在远程主机的 ~/.ssh/authorized_keys 文件中，将该公钥行替换为以下内容：\n\n$restricted_pub_key\n\n这将限制该密钥只能执行以下 ZFS 操作：\n- 列出快照\n- 删除快照\n- 接收快照\n- 重命名快照\n\n这些权限足够进行备份操作，同时最大限度地保护远程系统的安全。" 20 70
}

generate_ssh_key() {
    local key_path="/root/.ssh/zfs_backup_ed25519"
    ssh-keygen -t ed25519 -f "$key_path" -N "" -C "ZFS Backup Key"
    chmod 600 "$key_path"
    chmod 644 "${key_path}.pub"
    config[ssh_key_path]="$key_path"
    
    local pub_key=$(cat "${key_path}.pub")
    show_key_restriction_info "$pub_key"
}
