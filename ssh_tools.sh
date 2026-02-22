#!/bin/bash

# ==================================================
# 脚本配置
# ==================================================
# GitHub 用户名和仓库名
GITHUB_USER="cipherorcom"
REPO_NAME="ssh_tool"
# 分支名称
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
    local missing_tools=0
    # 检查 wget
    if ! command -v wget &> /dev/null; then
        echo -e "${YELLOW}未找到 wget，将尝试安装...${PLAIN}"
        missing_tools=1
    fi
    # 检查 curl
    if ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}未找到 curl，将尝试安装...${PLAIN}"
        missing_tools=1
    fi

    if [ $missing_tools -eq 1 ]; then
        if [ -x "$(command -v apt-get)" ]; then
            apt-get update && apt-get install -y wget curl
        elif [ -x "$(command -v yum)" ]; then
            yum install -y wget curl
        elif [ -x "$(command -v apk)" ]; then
            apk add wget curl
        else
            echo -e "${RED}错误: 无法自动安装 wget 或 curl，请手动安装。${PLAIN}"
            exit 1
        fi
        echo -e "${GREEN}必要的工具 (wget/curl) 安装完成。${PLAIN}"
    fi
}

# 下载并执行脚本的函数
run_script() {
    local script_name=$1
    echo -e "${GREEN}正在从仓库获取 ${script_name} ...${PLAIN}"
    
    wget -O "$script_name" "${BASE_URL}/${script_name}"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}下载成功，正在执行...${PLAIN}"
        chmod +x "$script_name"
        ./"$script_name"
        
        # 执行完后清理
        rm -f "$script_name"
    else
        echo -e "${RED}下载失败！请检查以下几点：${PLAIN}"
        echo "1. 仓库地址: https://github.com/${GITHUB_USER}/${REPO_NAME}"
        echo "2. 文件名 ${script_name} 是否存在"
    fi
    
    # 执行完暂停
    echo ""
    read -n 1 -s -r -p "按任意键继续..."
}

# ==================================================
# Docker 管理模块
# ==================================================

# Docker 安装函数 (保持本地执行，因为只需要拉取官方脚本)
install_docker_local() {
    # 检查 Docker 是否已安装
    if command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker 似乎已安装，版本: $(docker version --format '{{.Server.Version}}')${PLAIN}"
        read -p "是否强制重新安装? (y/N): " continue_install
        if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}取消安装。${PLAIN}"
            return
        fi
    fi

    echo -e "${GREEN}正在获取官方安装脚本 (get.docker.com)...${PLAIN}"
    curl -fsSL get.docker.com -o get-docker.sh

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}脚本下载成功，开始安装...${PLAIN}"
        sh get-docker.sh
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Docker 安装完成！${PLAIN}"
            echo -e "${YELLOW}提示: 非 root 用户请执行: ${BLUE}sudo usermod -aG docker \$USER${PLAIN}"
        else
            echo -e "${RED}安装脚本执行失败！${PLAIN}"
        fi
        rm -f get-docker.sh
    else
        echo -e "${RED}无法连接到 get.docker.com，请检查网络。${PLAIN}"
    fi
    
    echo ""
    read -n 1 -s -r -p "按任意键继续..."
}

# Docker 管理子菜单
docker_menu() {
    while true; do
        clear
        echo -e "${BLUE}================================================${PLAIN}"
        echo -e "${BLUE}            Docker 管理菜单                     ${PLAIN}"
        echo -e "${BLUE}================================================${PLAIN}"
        echo -e "${GREEN}1.${PLAIN} 安装 Docker (get.docker.com)"
        echo -e "${GREEN}2.${PLAIN} 配置 镜像加速/代理 (运行 docker_mirror.sh)"
        echo -e "${BLUE}================================================${PLAIN}"
        echo -e "${YELLOW}0.${PLAIN} 返回主菜单"
        echo ""
        read -p "请输入选项: " sub_choice

        case $sub_choice in
            1)
                install_docker_local
                ;;
            2)
                # 这里调用 run_script，你需要确保仓库里有 docker_mirror.sh
                run_script "set_docker_mirror.sh"
                ;;
            0)
                # 退出子循环，返回主菜单
                return 
                ;;
            *)
                echo -e "${RED}无效输入${PLAIN}"
                sleep 1
                ;;
        esac
    done
}

# ==================================================
# 主菜单
# ==================================================
main_menu() {
    while true; do
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
        echo -e "${GREEN}8.${PLAIN} Docker 管理 (安装/配置加速)" 
        echo -e "${GREEN}9.${PLAIN} 出站优先级管理脚本 (network.sh)"
        echo -e "${GREEN}10.${PLAIN} UFW管理 (ufw.sh)"
        echo -e "${GREEN}11.${PLAIN} Fail2ban管理 (fail2ban.sh)"
        echo -e "${BLUE}================================================${PLAIN}"
        echo -e "${YELLOW}0.${PLAIN} 退出脚本"
        echo ""
        read -p "请输入选项数字 [0-11]: " choice

        case $choice in
            1) run_script "swap.sh" ;;
            2) run_script "change_ssh.sh" ;;
            3) run_script "nginx.sh" ;;
            4) run_script "frps.sh" ;;
            5) run_script "zram.sh" ;;
            6) run_script "sb.sh" ;;
            7) run_script "zsh.sh" ;;
            8) docker_menu ;; 
            9) run_script "network.sh" ;;
            10) run_script "ufw.sh" ;;
            11) run_script "fail2ban.sh" ;;
            0) echo "退出。"; exit 0 ;;
            *) echo -e "${RED}无效输入，请重新选择。${PLAIN}"; sleep 1 ;;
        esac
    done
}

# ==================================================
# 脚本入口
# ==================================================
check_dependencies
main_menu
