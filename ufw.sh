#!/bin/bash

# 检查是否以 root 权限运行
if [[ $EUID -ne 0 ]]; then
   echo "错误: 请使用 sudo 或 root 权限运行此脚本。"
   exit 1
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查并安装 UFW
check_install() {
    if ! command -v ufw &> /dev/null; then
        echo -e "${YELLOW}检测到系统未安装 UFW，正在尝试安装...${NC}"
        apt-get update && apt-get install ufw -y
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}UFW 安装成功！${NC}"
        else
            echo -e "${RED}安装失败，请检查网络或软件源。${NC}"
            exit 1
        fi
    fi
}

# 卸载 UFW
uninstall_ufw() {
    echo -e "${RED}警告: 这将禁用并彻底从系统中移除 UFW 及其配置！${NC}"
    echo -n "确定要继续吗? (y/n): "
    read confirm
    if [[ $confirm == [yY] ]]; then
        ufw disable
        apt-get purge ufw -y && apt-get autoremove -y
        echo -e "${GREEN}UFW 已成功卸载。${NC}"
        exit 0
    else
        echo "操作已取消。"
    fi
}

# 初始化安装检查
check_install

# 菜单函数
show_menu() {
    echo -e "\n${YELLOW}--- UFW 全能助手 (含安装/卸载) ---${NC}"
    echo "1) 查看状态"      "2) 启用防火墙"      "3) 禁用防火墙"
    echo "4) 开放端口"      "5) 删除规则(编号)"  "6) 允许 IP (白名单)"
    echo "7) 拦截 IP (黑名单)" "8) 重置所有规则"    "9) 卸载 UFW"
    echo "0) 退出"
    echo -ne "${GREEN}请选择 [0-9]: ${NC}"
}

while true; do
    show_menu
    read choice
    case $choice in
        1) ufw status numbered ;;
        2) ufw enable ;;
        3) ufw disable ;;
        4) echo -n "端口/服务 (如 22 或 80/tcp): "; read port; ufw allow $port ;;
        5) ufw status numbered; echo -n "规则编号: "; read num; ufw delete $num ;;
        6) echo -n "允许的 IP: "; read ip; ufw allow from $ip ;;
        7) echo -n "拦截的 IP: "; read ip; ufw deny from $ip ;;
        8) ufw reset ;;
        9) uninstall_ufw ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入错误${NC}" ;;
    esac
done
