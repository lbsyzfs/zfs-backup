#!/bin/bash

# 显示主菜单
main_menu() {
    while true; do
        local choice=$(dialog --clear --title "ZFS 备份系统管理" \
                    --menu "请选择一个操作：" 15 50 4 \
                    1 "安装脚本" \
                    2 "修改配置" \
                    3 "卸载脚本" \
                    4 "退出" \
                    2>&1 >/dev/tty)

        case $choice in
            1) install_script ;;
            2) modify_config ;;
            3) uninstall_script ;;
            4) 
                clear
                print_message $GREEN "感谢使用 ZFS 备份系统管理工具"
                exit 0
                ;;
            *) 
                show_error "无效选项，请重新选择"
                ;;
        esac
    done
}

# 显示帮助信息
show_help() {
    local title="$1"
    local text="$2"
    dialog --title "$title" --msgbox "$text" 20 70
}

# 显示错误信息
show_error() {
    dialog --title "错误" --msgbox "$1" 8 40
}

# 显示信息
show_info() {
    dialog --title "信息" --msgbox "$1" 8 40
}

# 显示进度条
show_progress() {
    local title="$1"
    local text="$2"
    local percent="$3"
    echo $percent | dialog --gauge "$text" 8 50 0
}

# 获取用户输入
get_user_input() {
    local title="$1"
    local text="$2"
    local default="$3"
    dialog --title "$title" --inputbox "$text" 8 60 "$default" 2>&1 >/dev/tty
}

# 获取用户确认
get_user_confirmation() {
    local title="$1"
    local text="$2"
    dialog --title "$title" --yesno "$text" 8 60
    return $?
}

# 显示多行文本
show_text() {
    local title="$1"
    local text="$2"
    dialog --title "$title" --msgbox "$text" 20 70
}

# 显示文件内容
show_file() {
    local title="$1"
    local file="$2"
    dialog --title "$title" --textbox "$file" 20 70
}
