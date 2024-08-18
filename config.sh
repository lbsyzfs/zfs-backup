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
