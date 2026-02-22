#!/bin/bash

# ==========================================
# Fail2ban 交互式管理脚本
# ==========================================

# 颜色输出格式
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}错误: 请使用 root 权限运行此脚本 (例如: sudo ./fail2ban_manager.sh)${NC}"
  exit 1
fi

# 安装 Fail2ban
install_fail2ban() {
    echo -e "${YELLOW}正在检测系统并安装 Fail2ban...${NC}"
    if [ -f /etc/debian_version ]; then
        apt-get update
        apt-get install -y fail2ban
    elif [ -f /etc/redhat-release ]; then
        yum install -y epel-release
        yum install -y fail2ban
    else
        echo -e "${RED}不支持的操作系统，请手动安装。${NC}"
        return
    fi
    
    systemctl enable fail2ban
    systemctl start fail2ban
    echo -e "${GREEN}Fail2ban 安装并启动完成！${NC}"
}

# 服务管理 (启动/停止/重启)
manage_service() {
    read -p "请选择操作 (1: 启动 2: 停止 3: 重启): " action
    case $action in
        1) systemctl start fail2ban && echo -e "${GREEN}已启动${NC}" ;;
        2) systemctl stop fail2ban && echo -e "${GREEN}已停止${NC}" ;;
        3) systemctl restart fail2ban && echo -e "${GREEN}已重启${NC}" ;;
        *) echo -e "${RED}无效选择${NC}" ;;
    esac
}

# 查看运行状态
check_status() {
    echo -e "${YELLOW}Fail2ban 整体运行状态:${NC}"
    fail2ban-client status
}

# 查看特定 Jail 的状态
check_jail_status() {
    read -p "请输入要查看的 Jail 名称 (如 sshd): " jail_name
    if [ -z "$jail_name" ]; then
        echo -e "${RED}名称不能为空！${NC}"
    else
        echo -e "${YELLOW}状态信息 - $jail_name :${NC}"
        fail2ban-client status "$jail_name"
    fi
}

# 解封 IP
unban_ip() {
    read -p "请输入要解封的 IP 地址: " ip_addr
    read -p "请输入该 IP 所在的 Jail 名称 (如 sshd): " jail_name
    
    if [ -z "$ip_addr" ] || [ -z "$jail_name" ]; then
        echo -e "${RED}IP 和 Jail 名称不能为空！${NC}"
    else
        fail2ban-client set "$jail_name" unbanip "$ip_addr"
        echo -e "${GREEN}已尝试从 $jail_name 中解封 IP: $ip_addr${NC}"
    fi
}

# 封禁 IP (手动)
ban_ip() {
    read -p "请输入要封禁的 IP 地址: " ip_addr
    read -p "请输入要加入的 Jail 名称 (如 sshd): " jail_name
    
    if [ -z "$ip_addr" ] || [ -z "$jail_name" ]; then
        echo -e "${RED}IP 和 Jail 名称不能为空！${NC}"
    else
        fail2ban-client set "$jail_name" banip "$ip_addr"
        echo -e "${GREEN}已尝试将 IP: $ip_addr 加入到 $jail_name 进行封禁${NC}"
    fi
}

# 主菜单
show_menu() {
    echo "=================================="
    echo -e "${GREEN}   Fail2ban 管理脚本   ${NC}"
    echo "=================================="
    echo "1. 安装 Fail2ban"
    echo "2. 管理 Fail2ban 服务 (启动/停止/重启)"
    echo "3. 查看 Fail2ban 整体状态 (列出活动 Jails)"
    echo "4. 查看指定 Jail 的详细状态 (查看被封 IP)"
    echo "5. 解封 (Unban) 指定 IP"
    echo "6. 封禁 (Ban) 指定 IP"
    echo "0. 退出脚本"
    echo "=================================="
}

# 运行主逻辑
while true; do
    show_menu
    read -p "请输入选项 [0-6]: " choice
    case $choice in
        1) install_fail2ban ;;
        2) manage_service ;;
        3) check_status ;;
        4) check_jail_status ;;
        5) unban_ip ;;
        6) ban_ip ;;
        0) echo -e "${GREEN}退出脚本，祝你使用愉快！${NC}"; exit 0 ;;
        *) echo -e "${RED}无效选项，请重新输入。${NC}" ;;
    esac
    echo ""
    read -p "按回车键继续..." 
    clear
done
