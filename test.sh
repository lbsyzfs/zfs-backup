#!/bin/bash

test_configuration() {
    show_info "开始测试配置..."

    local total_tests=5
    local current_test=0

    # 测试本地数据集是否存在
    current_test=$((current_test + 1))
    show_progress "测试进度" "测试本地数据集..." $((current_test * 100 / total_tests))
    if zfs list "$(get_config_value source_dataset)" > /dev/null 2>&1; then
        show_info "✅ 本地数据集 $(get_config_value source_dataset) 存在"
    else
        show_error "❌ 错误: 本地数据集 $(get_config_value source_dataset) 不存在"
        return 1
    fi

    # 解析 SSH 命令和远程主机信息
    local ssh_cmd="$(get_config_value ssh_cmd)"
    local remote_host="$(get_config_value remote_host)"
    local remote_port="$(get_config_value remote_port)"
    local remote_user=$(echo $remote_host | cut -d@ -f1)
    local remote_hostname=$(echo $remote_host | cut -d@ -f2)

    # 测试 SSH 连接
    current_test=$((current_test + 1))
    show_progress "测试进度" "测试 SSH 连接..." $((current_test * 100 / total_tests))
    if $ssh_cmd -p $remote_port -o ConnectTimeout=5 $remote_user@$remote_hostname echo "SSH connection successful" > /dev/null 2>&1; then
        show_info "✅ SSH 连接成功"
    else
        show_error "❌ 错误: 无法连接到远程主机 $remote_host"
        return 1
    fi

    # 测试远程 sudo 权限
    current_test=$((current_test + 1))
    show_progress "测试进度" "测试远程 sudo 权限..." $((current_test * 100 / total_tests))
    if $ssh_cmd -p $remote_port $remote_user@$remote_hostname "sudo -n true" > /dev/null 2>&1; then
        show_info "✅ 远程 sudo 权限正常"
    else
        show_error "❌ 错误: 远程主机上无法使用 sudo，或需要密码"
        return 1
    fi

    # 测试远程存储池是否存在
    current_test=$((current_test + 1))
    show_progress "测试进度" "测试远程存储池..." $((current_test * 100 / total_tests))
    local remote_pool=$(echo $(get_config_value remote_dataset) | cut -d/ -f1)
    if $ssh_cmd -p $remote_port $remote_user@$remote_hostname "sudo zfs list $remote_pool" > /dev/null 2>&1; then
        show_info "✅ 远程存储池 $remote_pool 存在"
    else
        show_error "❌ 错误: 远程存储池 $remote_pool 不存在"
        return 1
    fi

    # 测试 Telegram 消息发送
    current_test=$((current_test + 1))
    show_progress "测试进度" "测试 Telegram 消息发送..." $((current_test * 100 / total_tests))
    if [ "$(get_config_value enable_telegram_notify)" = "true" ]; then
        local test_message="ZFS 备份系统测试消息"
        local telegram_response=$(curl -s -X POST "https://api.telegram.org/bot$(get_config_value telegram_bot_token)/sendMessage" \
             -d chat_id="$(get_config_value telegram_chat_id)" \
             -d text="$test_message")
        
        if echo "$telegram_response" | grep -q '"ok":true'; then
            show_info "✅ Telegram 测试消息发送成功"
        else
            show_error "❌ 错误: 无法发送 Telegram 测试消息"
            return 1
        fi
    else
        show_info "Telegram 通知未启用，跳过测试"
    fi

    show_info "✅ 所有测试通过"
    return 0
}
