#!/bin/bash

# 此脚本用于自动化ZFS数据集的备份过程。主要功能包括：
# 1. 备份 /boot 目录到 /root/boot-backup
# 2. 创建精确到秒的本地ZFS快照
# 3. 将本地快照同步到远程系统，支持增量传输
# 4. 在远程系统上保持一个名为"latest"的最新快照
# 5. 删除同一天的旧快照以节省空间
# 6. 通过Telegram发送备份过程的详细报告
# 使用方法：直接运行脚本，无需额外参数


# 加载配置文件
CONFIG_FILE="/etc/zfs_backup/config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误：找不到配置文件 $CONFIG_FILE"
    exit 1
fi

# 读取配置
config=$(yq e -o=json /etc/zfs_backup/config.yaml)

# 构建 SSH 命令
ssh_command="ssh -p $(yq e '.remote_port // "22"' /etc/zfs_backup/config.yaml)"
if [ "$(yq e '.ssh_key_path' /etc/zfs_backup/config.yaml)" != "null" ]; then
    ssh_command+=" -i $(yq e '.ssh_key_path' /etc/zfs_backup/config.yaml)"
elif [ "$(yq e '.ssh_key' /etc/zfs_backup/config.yaml)" != "null" ]; then
    ssh_command+=" -o IdentityFile=<(echo '$(yq e '.ssh_key' /etc/zfs_backup/config.yaml)')"
fi

ssh_command+=" -o StrictHostKeyChecking=no"

# 如果密钥没有被限制，我们需要在这里添加命令限制
if [ "$(yq e '.ssh_key_restricted // "true"' /etc/zfs_backup/config.yaml)" = "false" ]; then
    zfs_commands="sudo zfs list -H -t snapshot -o name,sudo zfs destroy,sudo zfs receive,sudo zfs rename"
    ssh_command="$ssh_command \"${zfs_commands// /}\""
fi

# 在后续的脚本中使用 $ssh_command 来执行远程命令

# 生成易读的日期时间字符串
get_readable_date() {
    date '+%Y年%m月%d日 %H:%M:%S' | sed 's/[()]/\\&/g'
}

# 日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# 转义 Markdown 特殊字符
escape_markdown() {
    echo "$1" | sed -e 's/[_*\[\]()~`>#+=|{}.!-]/\\&/g'
}

# Telegram 通知函数
send_telegram_message() {
    if [ "$ENABLE_TELEGRAM_NOTIFY" = true ]; then
        local escaped_message=$(escape_markdown "$MESSAGE")
        
        # 检查转义后的消息是否为空
        if [ -z "$escaped_message" ]; then
            log "警告：转义后的消息为空，使用原始消息"
            escaped_message="$MESSAGE"
        fi
        
        local response=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
             -d chat_id="$TELEGRAM_CHAT_ID" \
             -d text="$escaped_message" \
             -d parse_mode="MarkdownV2")
        
        if echo "$response" | grep -q '"ok":true'; then
            log "Telegram 消息发送成功"
        else
            log "发送 Telegram 消息时出错: $response"
            log "尝试发送不带 Markdown 解析的消息"
            response=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
                 -d chat_id="$TELEGRAM_CHAT_ID" \
                 -d text="$MESSAGE")
            if echo "$response" | grep -q '"ok":true'; then
                log "不带 Markdown 解析的 Telegram 消息发送成功"
            else
                log "发送不带 Markdown 解析的 Telegram 消息时出错: $response"
            fi
        fi
        echo "Debug: 原始消息为: $MESSAGE" >> "$LOG_FILE"
        echo "Debug: 转义后的消息为: $escaped_message" >> "$LOG_FILE"
    fi
}

# 添加消息到报告
append_to_message() {
    MESSAGE+="$1"$'\n'
}

# 获取快照大小
get_snapshot_size() {
    local snapshot=$1
    local size=$(zfs get -Hp -o value used $snapshot)
    if [[ $size =~ ^[0-9]+$ ]]; then
        echo $size
    else
        echo "0"
    fi
}

# 获取快照的引用大小（实际占用的独立空间）
get_snapshot_referenced_size() {
    local snapshot=$1
    local size=$(zfs get -Hp -o value referenced $snapshot)
    if [[ $size =~ ^[0-9]+$ ]]; then
        echo $size
    else
        echo "0"
    fi
}

# 格式化大小为人类可读形式
format_size() {
    numfmt --to=iec-i --suffix=B $1
}

# 复制 /boot 到 /root/boot-backup
backup_boot() {
    local backup_dir="/root/boot-backup"
    log "开始备份 /boot 到 $backup_dir"
    append_to_message "📁 备份 /boot 目录"

    # 确保备份目录存在
    mkdir -p "$backup_dir"

    # 使用 rsync 复制 /boot 内容
    if rsync -av --delete /boot/ "$backup_dir/"; then
        log "/boot 备份成功"
        append_to_message "✅ /boot 备份成功"
    else
        log "备份 /boot 时出错"
        append_to_message "❌ 备份 /boot 失败"
        send_telegram_message "$MESSAGE"
        exit 1
    fi
}

# 删除同一天的旧快照
delete_same_day_snapshots() {
    local current_date=$(date +%Y%m%d)
    local snapshots_to_delete=$(zfs list -H -t snapshot -o name | grep "^$SOURCE_DATASET@$current_date" | grep -v "$LOCAL_SNAPSHOT_NAME")
    
    if [ -n "$snapshots_to_delete" ]; then
        log "删除同一天的旧快照"
        append_to_message "🗑️ 删除同一天的旧快照:"
        echo "$snapshots_to_delete" | while read snapshot; do
            if zfs destroy "$snapshot"; then
                log "已删除快照: $snapshot"
                append_to_message "   - $snapshot"
            else
                log "删除快照失败: $snapshot"
                append_to_message "   ⚠️ 删除失败: $snapshot"
            fi
        done
    else
        log "没有同一天的旧快照需要删除"
        append_to_message "ℹ️ 没有同一天的旧快照需要删除"
    fi
}

# 删除远程系统上的 "latest" 快照并重命名新快照
delete_old_remote_snapshot_and_rename() {
    log "检查并删除远程系统上的 'latest' 快照"
    append_to_message "🔍 检查远程系统上的 'latest' 快照"

    # 删除名为 "latest" 的远程快照
    if eval "$SSH_COMMAND zfs list -H -t snapshot -o name | grep -q '^$REMOTE_DATASET@latest$'"; then
        if eval "$SSH_COMMAND zfs destroy $REMOTE_DATASET@latest"; then
            log "已删除远程 'latest' 快照"
            append_to_message "🗑️ 已删除远程 'latest' 快照"
        else
            log "删除远程 'latest' 快照失败"
            append_to_message "⚠️ 删除远程 'latest' 快照失败"
        fi
    else
        log "远程系统上没有 'latest' 快照需要删除"
        append_to_message "ℹ️ 远程系统上没有 'latest' 快照需要删除"
    fi

    # 重命名新快照为 "latest"
    if eval "$SSH_COMMAND zfs rename $REMOTE_DATASET@${SNAPSHOT_DATE} $REMOTE_DATASET@latest"; then
        log "远程快照已重命名为 'latest'"
        append_to_message "✅ 远程快照已重命名为 'latest'"
    else
        log "重命名远程快照时出错"
        append_to_message "⚠️ 重命名远程快照失败"
    fi
}

# 初始化消息和计时器
START_TIME=$(date +%s)
REPORT_DATE=$(get_readable_date)
MESSAGE=""

# 添加自定义消息（如果有）
if [ -n "$CUSTOM_REPORT_HEADER" ]; then
    MESSAGE+="$CUSTOM_REPORT_HEADER"$'\n\n'
fi

# 开始代码块
MESSAGE+='```'$'\n'
MESSAGE+="ZFS 备份报告 ($REPORT_DATE)"$'\n'

# 在日志文件中添加会话分隔符
echo "========================================" >> "$LOG_FILE"
echo "备份会话开始: $REPORT_DATE" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

# 备份 /boot
backup_boot

# 创建新的本地快照
SNAPSHOT_DATE=$(date +%Y%m%d%H%M%S)
LOCAL_SNAPSHOT_NAME="${SOURCE_DATASET}@${SNAPSHOT_DATE}"
REMOTE_SNAPSHOT_NAME="${REMOTE_DATASET}@latest"

log "创建新的本地快照: $LOCAL_SNAPSHOT_NAME"
if zfs snapshot -r "$LOCAL_SNAPSHOT_NAME"; then
    log "新快照创建成功"
    append_to_message "✅ 新快照已创建: $LOCAL_SNAPSHOT_NAME"
    SNAPSHOT_SIZE=$(get_snapshot_size "$LOCAL_SNAPSHOT_NAME")
    SNAPSHOT_REFERENCED_SIZE=$(get_snapshot_referenced_size "$LOCAL_SNAPSHOT_NAME")
    append_to_message "   快照大小: $(format_size $SNAPSHOT_SIZE)"
    append_to_message "   引用大小: $(format_size $SNAPSHOT_REFERENCED_SIZE)"
else
    log "创建新快照时出错"
    append_to_message "❌ 创建新快照失败"
    send_telegram_message "$MESSAGE"
    exit 1
fi

log "Debug: SSH_COMMAND = $SSH_COMMAND"
if ! eval "$SSH_COMMAND zfs list -H >/dev/null 2>&1"; then
    log "错误: SSH 连接或远程 ZFS 命令执行测试失败"
    append_to_message "❌ SSH 连接或远程 ZFS 命令执行测试失败"
    send_telegram_message "$MESSAGE"
    exit 1
fi

# 检查远程快照是否存在
REMOTE_SNAPSHOT_EXISTS=$(eval "$SSH_COMMAND zfs list -H -t snapshot -o name | grep '^$REMOTE_SNAPSHOT_NAME$'")

if [ -n "$REMOTE_SNAPSHOT_EXISTS" ]; then
    # 远程快照存在，执行增量传输
    log "远程快照存在。执行增量传输。"
    append_to_message "ℹ️ 正在增量更新远程快照"
    
    # 获取最新的本地快照（不包括刚刚创建的）
    LATEST_LOCAL_SNAPSHOT=$(zfs list -H -t snapshot -o name -s creation | grep "^$SOURCE_DATASET@" | tail -n 2 | head -n 1)
    
    if [ -n "$LATEST_LOCAL_SNAPSHOT" ]; then
        log "使用最新的本地快照进行增量传输: $LATEST_LOCAL_SNAPSHOT"
        if zfs send -i "$LATEST_LOCAL_SNAPSHOT" "$LOCAL_SNAPSHOT_NAME" | eval "$SSH_COMMAND zfs receive -o mountpoint=none -F $REMOTE_DATASET"; then
            log "增量快照发送成功"
            append_to_message "✅ 远程快照已增量更新"
            delete_same_day_snapshots  # 删除同一天的旧快照
            delete_old_remote_snapshot_and_rename  # 删除远程 "latest" 快照并重命名新快照
        else
            log "发送增量快照时出错"
            append_to_message "❌ 更新远程快照失败"
            send_telegram_message "$MESSAGE"
            exit 1
        fi
    else
        log "未找到之前的本地快照，执行完整传输"
        if zfs send "$LOCAL_SNAPSHOT_NAME" | eval "$SSH_COMMAND zfs receive -o mountpoint=none -F $REMOTE_DATASET"; then
            log "完整快照发送成功"
            append_to_message "✅ 完整快照已发送到远程系统"
            delete_same_day_snapshots  # 删除同一天的旧快照
            delete_old_remote_snapshot_and_rename  # 删除远程 "latest" 快照并重命名新快照
        else
            log "发送完整快照时出错"
            append_to_message "❌ 发送完整快照失败"
            send_telegram_message "$MESSAGE"
            exit 1
        fi
    fi
else
    # 远程快照不存在，执行完整传输
    log "远程快照不存在。执行完整传输。"
    append_to_message "ℹ️ 正在向远程系统发送完整快照"
    
    if zfs send "$LOCAL_SNAPSHOT_NAME" | eval "$SSH_COMMAND zfs receive -o mountpoint=none -F $REMOTE_DATASET"; then
        log "完整快照发送成功"
        append_to_message "✅ 完整快照已发送到远程系统"
        delete_same_day_snapshots  # 删除同一天的旧快照
        delete_old_remote_snapshot_and_rename  # 删除远程 "latest" 快照并重命名新快照
    else
        log "发送完整快照时出错"
        append_to_message "❌ 发送完整快照失败"
        send_telegram_message "$MESSAGE"
        exit 1
    fi
fi

# 清理本地旧快照
log "清理旧快照"
LOCAL_SNAPSHOTS_TO_DELETE=$(zfs list -H -t snapshot -o name | grep "$SOURCE_DATASET@" | sort -r | tail -n +$((SNAPSHOT_RETENTION_DAYS + 1)))

DELETED_COUNT=0
TOTAL_SPACE_FREED=0
for snapshot in $LOCAL_SNAPSHOTS_TO_DELETE; do
    SNAPSHOT_SIZE=$(get_snapshot_size "$snapshot")
    
    if zfs destroy "$snapshot"; then
        log "已删除本地快照: $snapshot"
        DELETED_COUNT=$((DELETED_COUNT + 1))
        TOTAL_SPACE_FREED=$((TOTAL_SPACE_FREED + SNAPSHOT_SIZE))
    else
        log "删除本地快照时出错: $snapshot"
        append_to_message "⚠️ 删除本地快照失败: $snapshot"
    fi
done

append_to_message "🗑️ 已删除 $DELETED_COUNT 个旧快照"
append_to_message "   释放空间: $(format_size $TOTAL_SPACE_FREED)"

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

log "备份和清理成功完成"
append_to_message "✅ *备份和清理成功完成*"
append_to_message "⏱️ 总耗时: $TOTAL_DURATION 秒"

# 结束代码块
MESSAGE+='```'

# 发送最终报告
send_telegram_message "$MESSAGE"
log "脚本执行完成"
