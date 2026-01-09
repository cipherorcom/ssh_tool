#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 检查是否为root用户
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 必须使用 root 用户运行此脚本！${PLAIN}" 
   exit 1
fi

GAI_CONF="/etc/gai.conf"

# --- 功能函数区 ---

# 暂停并等待用户操作
pause_and_return() {
    echo ""
    echo -e "${YELLOW}按回车键返回主菜单...${PLAIN}"
    read -r
}

# 功能：检查当前出站IP
check_status() {
    echo -e "${YELLOW}正在测试当前出站优先级...${PLAIN}"
    
    # 使用 curl 访问双栈域名
    # 设置超时时间，防止网络不通卡住
    local ip_info=$(curl -s --connect-timeout 5 https://ip.gs)
    
    if [[ -z "$ip_info" ]]; then
        ip_info=$(curl -s --connect-timeout 5 https://api.ip.sb/ip)
    fi

    echo -e "当前出站 IP: ${GREEN}${ip_info}${PLAIN}"
    
    if [[ "$ip_info" == *":"* ]]; then
        echo -e "当前偏好: ${GREEN}IPv6 优先${PLAIN}"
    elif [[ "$ip_info" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "当前偏好: ${GREEN}IPv4 优先${PLAIN}"
    else
        echo -e "${RED}无法检测网络或IP格式未知 (可能网络不通)${PLAIN}"
    fi
    
    # 检查配置文件状态
    if grep -q "^precedence ::ffff:0:0/96  100" "$GAI_CONF" 2>/dev/null; then
        echo -e "配置状态: ${GREEN}已强制 IPv4 优先 (/etc/gai.conf)${PLAIN}"
    else
        echo -e "配置状态: ${GREEN}系统默认 (通常为 IPv6 优先)${PLAIN}"
    fi
}

# 功能：设置IPv4优先
set_ipv4_first() {
    echo -e "${YELLOW}正在配置 IPv4 优先...${PLAIN}"
    
    if [ -f "$GAI_CONF" ]; then
        cp "$GAI_CONF" "${GAI_CONF}.bak"
    fi

    if [ ! -f "$GAI_CONF" ]; then
        echo "label  ::1/128       0" > "$GAI_CONF"
        echo "label  ::/0          1" >> "$GAI_CONF"
        echo "label  2002::/16     2" >> "$GAI_CONF"
        echo "label  ::/96         3" >> "$GAI_CONF"
        echo "label  ::ffff:0:0/96 4" >> "$GAI_CONF"
    fi

    sed -i '/^precedence ::ffff:0:0\/96  100/d' "$GAI_CONF"
    echo "precedence ::ffff:0:0/96  100" >> "$GAI_CONF"
    
    echo -e "${GREEN}设置完成！${PLAIN}"
    echo "------------------------"
    check_status
}

# 功能：设置IPv6优先 (还原默认)
set_ipv6_first() {
    echo -e "${YELLOW}正在配置 IPv6 优先 (恢复默认)...${PLAIN}"
    
    if [ -f "$GAI_CONF" ]; then
        sed -i '/^precedence ::ffff:0:0\/96  100/d' "$GAI_CONF"
        echo -e "${GREEN}设置完成！已恢复系统默认行为。${PLAIN}"
    else
        echo -e "${YELLOW}配置文件不存在，系统默认为 IPv6 优先。${PLAIN}"
    fi
    echo "------------------------"
    check_status
}

# --- 菜单逻辑 ---

show_menu() {
    while true; do
        clear
        echo -e "-----------------------------------"
        echo -e "${GREEN}    Linux VPS 出站优先级管理脚本    ${PLAIN}"
        echo -e "-----------------------------------"
        echo -e "1. 设置 ${YELLOW}IPv4${PLAIN} 优先 (修改 gai.conf)"
        echo -e "2. 设置 ${YELLOW}IPv6${PLAIN} 优先 (恢复默认)"
        echo -e "3. 检测当前出站优先级"
        echo -e "0. 退出脚本"
        echo -e "-----------------------------------"
        read -p "请输入选项 [0-3]: " choice

        case $choice in
            1)
                set_ipv4_first
                pause_and_return
                ;;
            2)
                set_ipv6_first
                pause_and_return
                ;;
            3)
                check_status
                pause_and_return
                ;;
            0)
                echo -e "${GREEN}退出脚本。${PLAIN}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请重新输入${PLAIN}"
                sleep 1
                ;;
        esac
    done
}

# 启动菜单
show_menu
