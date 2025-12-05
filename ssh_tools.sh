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
    local missing_tools=0
    # 检查 wget
    if ! command -v wget &> /dev/null; then
        echo -e "${YELLOW}未找到 wget，将尝试安装...${PLAIN}"
        missing_tools=1
    fi
    # 检查 curl (新增)
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

# Docker 一键安装函数
install_docker() {
    clear
    echo -e "${BLUE}================================================${PLAIN}"
    echo -e "${BLUE}            Docker 一键安装               ${PLAIN}"
    echo -e "${BLUE}================================================${PLAIN}"
    
    # 检查 Docker 是否已安装
    if command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker 似乎已安装，版本信息: ${PLAIN}"
        docker version --format '{{.Server.Version}}'
        echo -e "${YELLOW}如果您需要重新安装，请先手动卸载。${PLAIN}"
        # 仍然提供继续安装的选项，以防万一
        read -p "是否仍然继续安装 Docker? (y/N): " continue_install
        if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}取消安装。${PLAIN}"
            echo ""
            read -n 1 -s -r -p "按任意键返回主菜单..."
            main_menu
            return
        fi
    fi

    echo -e "${GREEN}正在从 get.docker.com 获取并执行安装脚本...${PLAIN}"
    
    # 执行 Docker 官方安装脚本
    # 官方推荐方式: curl -fsSL https://get.docker.com | sh
    # 你指定的脚本获取方式: curl -fsSL get.docker.com -o get-docker.sh && sh get-docker.sh
    # 为了清晰和标准，我们使用下载后执行的方式。
    curl -fsSL get.docker.com -o get-docker.sh

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Docker 安装脚本下载成功，正在执行...${PLAIN}"
        sh get-docker.sh
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Docker 安装完成！${PLAIN}"
            echo -e "${YELLOW}提示: 为了让非 root 用户也能使用 Docker，请运行: ${PLAIN}"
            echo -e "    ${BLUE}sudo usermod -aG docker \$USER${PLAIN}"
            echo -e "${YELLOW}然后重新登录 SSH 会话。${PLAIN}"
        else
            echo -e "${RED}Docker 安装脚本执行失败！${PLAIN}"
        fi
        
        # 清理安装脚本
        rm -f get-docker.sh
    else
        echo -e "${RED}Docker 安装脚本下载失败！请检查网络连接。${PLAIN}"
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
    echo -e "${BLUE}    SSH Tool 综合管理脚本 (仓库: ${GITHUB_USER}) ${PLAIN}"
    echo -e "${BLUE}================================================${PLAIN}"
    echo -e "${GREEN}1.${PLAIN} swap管理 (swap.sh)"
    echo -e "${GREEN}2.${PLAIN} 修改SSH端口及密码 (change_ssh.sh)"
    echo -e "${GREEN}3.${PLAIN} Nginx管理 (nginx.sh)"
    echo -e "${GREEN}4.${PLAIN} frps管理 (frps.sh)"
    echo -e "${GREEN}5.${PLAIN} zram管理 (zram.sh)"
    echo -e "${GREEN}6.${PLAIN} Sing-box四合一 (sb.sh)"
    echo -e "${GREEN}7.${PLAIN} Zsh一键安装 (zsh.sh)"
    echo -e "${GREEN}8.${PLAIN} Docker 一键安装 (get.docker.com)"
    echo -e "${BLUE}================================================${PLAIN}"
    echo -e "${YELLOW}0.${PLAIN} 退出脚本"
    echo ""
    read -p "请输入选项数字 [0-8]: " choice

    case $choice in
        1) run_script "swap.sh" ;;
        2) run_script "change_ssh.sh" ;;
        3) run_script "nginx.sh" ;;
        4) run_script "frps.sh" ;;
        5) run_script "zram.sh" ;;
        6) run_script "sb.sh" ;;
        7) run_script "zsh.sh" ;;
        8) install_docker ;; # 调用新增的 Docker 安装函数
        0) echo "退出。"; exit 0 ;;
        *) echo -e "${RED}无效输入，请重新选择。${PLAIN}"; sleep 1; main_menu ;;
    esac
}

# ==================================================
# 脚本入口
# ==================================================
check_dependencies
main_menu
