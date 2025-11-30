#!/bin/bash

# ==================================================
# 脚本配置
# ==================================================
# GitHub 用户名和仓库名
GITHUB_USER="cipherorcom"
REPO_NAME="ssh_tool"
# 分支名称 (如果脚本无法下载，请尝试改为 master)
BRANCH="main" 

# 基础下载链接构造
BASE_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/${BRANCH}"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# ==================================================
# 辅助函数
# ==================================================

# 检查并安装必要的下载工具
check_dependencies() {
    if ! command -v wget &> /dev/null; then
        echo -e "${YELLOW}正在安装 wget...${PLAIN}"
        if [ -x "$(command -v apt-get)" ]; then
            apt-get update && apt-get install -y wget
        elif [ -x "$(command -v yum)" ]; then
            yum install -y wget
        elif [ -x "$(command -v apk)" ]; then
            apk add wget
        else
            echo -e "${RED}错误: 无法自动安装 wget，请手动安装。${PLAIN}"
            exit 1
        fi
    fi
}

# 下载并执行脚本的函数
# 参数 $1: 脚本文件名 (例如 check_cpu.sh)
run_script() {
    local script_name=$1
    echo -e "${GREEN}正在从仓库获取 ${script_name} ...${PLAIN}"
    
    # 下载脚本
    wget -O "$script_name" "${BASE_URL}/${script_name}"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}下载成功，正在执行...${PLAIN}"
        chmod +x "$script_name"
        ./"$script_name"
        
        # 执行完后清理（可选，如果想保留脚本请注释掉下面这行）
        rm -f "$script_name"
    else
        echo -e "${RED}下载失败！请检查以下几点：${PLAIN}"
        echo "1. 仓库地址是否正确: https://github.com/${GITHUB_USER}/${REPO_NAME}"
        echo "2. 分支名称是否正确 (当前尝试: ${BRANCH})"
        echo "3. 文件名 ${script_name} 是否存在于仓库中"
    fi
    
    # 执行完暂停，按任意键回菜单
    echo ""
    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
}

# ==================================================
# 主菜单
# ==================================================
main_menu() {
    clear
    echo -e "${BLUE}================================================${PLAIN}"
    echo -e "${BLUE}    SSH Tool 综合管理脚本 (仓库: ${GITHUB_USER}) ${PLAIN}"
    echo -e "${BLUE}================================================${PLAIN}"
    echo -e "${GREEN}1.${PLAIN} swap管理 (swap.sh)"
    echo -e "${GREEN}2.${PLAIN} 修改SSH端口及密码 (change_ssh.sh)"
    echo -e "${GREEN}3.${PLAIN} Nginx管理 (nginx.sh)"
    echo -e "${GREEN}4.${PLAIN} frps管理 (frps.sh)"
    echo -e "${GREEN}5.${PLAIN} zram管理 (zram.sh)"
    echo -e "${GREEN}6.${PLAIN} Sing-box四合一 (sb.sh)"
    echo -e "${GREEN}7.${PLAIN} Zsh一键安装 (zsh.sh)"
    echo -e "${BLUE}================================================${PLAIN}"
    echo -e "${YELLOW}0.${PLAIN} 退出脚本"
    echo ""
    read -p "请输入选项数字 [0-7]: " choice

    case $choice in
        1) run_script "swap.sh" ;;
        2) run_script "change_ssh.sh" ;;
        3) run_script "nginx.sh" ;;
        4) run_script "frps.sh" ;;
        5) run_script "zram.sh" ;;
        6) run_script "sb.sh" ;;
        7) run_script "zsh.sh" ;;
        0) echo "退出。"; exit 0 ;;
        *) echo -e "${RED}无效输入，请重新选择。${PLAIN}"; sleep 1; main_menu ;;
    esac
}

# ==================================================
# 脚本入口
# ==================================================
check_dependencies
main_menu
