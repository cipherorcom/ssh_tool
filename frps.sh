#!/bin/bash

#================================================================================
# frps 多功能管理脚本 (精简版)
#
# @author   Gemini
# @date     2025-09-15
# @version  2.1 (Lite)
#
# 功能:
#   - [安装] 交互式引导完成 frps 的安装与配置 (已移除vhost配置)
#   - [卸载] 干净地移除 frps 服务和所有相关文件
#   - [管理] 查看当前配置、启动/停止/重启服务、查看日志
#================================================================================

# --- 全局变量和颜色定义 ---
FRPS_INSTALL_PATH="/usr/local/bin/frps"
FRPS_CONFIG_PATH="/etc/frp/frps.toml"
FRPS_SERVICE_PATH="/etc/systemd/system/frps.service"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- 检查和准备工作 ---

# 检查是否以 root 权限运行
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误: 此脚本必须以 root 权限运行。${NC}"
        exit 1
    fi
}

# 检查 frps 是否已安装
check_if_installed() {
    if [ -f "$FRPS_INSTALL_PATH" ]; then
        return 0 # 已安装
    else
        return 1 # 未安装
    fi
}

# --- 功能函数 ---

# 任务：安装 frps
do_install() {
    if check_if_installed; then
        echo -e "${YELLOW}检测到 frps 已安装。如果您想重新安装，请先卸载。${NC}"
        return
    fi

    # --- 交互式获取配置 ---
    echo -e "${BLUE}--- 开始安装 frps (精简版) ---${NC}"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    read -p "请输入要安装的 frp 版本 (直接回车使用最新版: $LATEST_VERSION): " USER_VERSION
    FRP_VERSION=${USER_VERSION:-$LATEST_VERSION}
    read -p "请输入 frps 服务端口 [默认: 7000]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-7000}
    SUGGESTED_TOKEN=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    read -p "请输入认证令牌 (token) [建议: ${SUGGESTED_TOKEN}]: " TOKEN
    TOKEN=${TOKEN:-$SUGGESTED_TOKEN}
    read -p "请输入 Dashboard 端口 [默认: 7500]: " DASHBOARD_PORT
    DASHBOARD_PORT=${DASHBOARD_PORT:-7500}
    read -p "请输入 Dashboard 用户名 [默认: admin]: " DASHBOARD_USER
    DASHBOARD_USER=${DASHBOARD_USER:-admin}
    SUGGESTED_PWD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)
    read -p "请输入 Dashboard 密码 [建议: ${SUGGESTED_PWD}]: " DASHBOARD_PWD
    DASHBOARD_PWD=${DASHBOARD_PWD:-$SUGGESTED_PWD}

    # --- 开始执行安装 ---
    echo -e "${YELLOW}正在准备安装环境...${NC}"
    ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')
    DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"
    TMP_FILE="/tmp/frp.tar.gz"

    echo "正在下载 frp v$FRP_VERSION..."
    curl -L -o "$TMP_FILE" "$DOWNLOAD_URL" || { echo -e "${RED}下载失败!${NC}"; exit 1; }

    echo "正在解压和安装..."
    tar -zxvf "$TMP_FILE" -C /tmp
    install -m 755 "/tmp/frp_${FRP_VERSION}_linux_${ARCH}/frps" "$FRPS_INSTALL_PATH"
    
    echo "正在创建配置文件..."
    mkdir -p /etc/frp
    cat > "$FRPS_CONFIG_PATH" <<EOF
# frps.toml (由精简版脚本生成)
bindPort = $SERVER_PORT
auth.token = "$TOKEN"

# Dashboard 配置
webServer.addr = "0.0.0.0"
webServer.port = $DASHBOARD_PORT
webServer.user = "$DASHBOARD_USER"
webServer.password = "$DASHBOARD_PWD"

# 日志配置
log.to = "/var/log/frps.log"
log.level = "info"
log.maxDays = 7

# 性能优化
transport.tcpMux = true
EOF

    echo "正在创建 systemd 服务..."
    cat > "$FRPS_SERVICE_PATH" <<EOF
[Unit]
Description=frp server
After=network.target
[Service]
Type=simple
User=nobody
Restart=on-failure
RestartSec=5s
ExecStart=$FRPS_INSTALL_PATH -c $FRPS_CONFIG_PATH
[Install]
WantedBy=multi-user.target
EOF
    
    echo "正在配置防火墙..."
    # 只开放服务端口和Dashboard端口
    PORTS_TO_OPEN=($SERVER_PORT $DASHBOARD_PORT)
    if command -v firewall-cmd &>/dev/null; then
        echo "检测到 firewalld, 正在开放端口: ${PORTS_TO_OPEN[*]}"
        for port in "${PORTS_TO_OPEN[@]}"; do firewall-cmd --permanent --add-port=${port}/tcp; done
        firewall-cmd --reload
    elif command -v ufw &>/dev/null; then
        echo "检测到 ufw, 正在开放端口: ${PORTS_TO_OPEN[*]}"
        for port in "${PORTS_TO_OPEN[@]}"; do ufw allow ${port}/tcp; done
        ufw reload
    else
        echo -e "${YELLOW}警告: 未检测到防火墙工具, 请手动开放TCP端口: ${PORTS_TO_OPEN[*]}${NC}"
    fi

    echo "清理临时文件..."
    rm -f "$TMP_FILE"
    rm -rf "/tmp/frp_${FRP_VERSION}_linux_${ARCH}"

    echo "启动并启用 frps 服务..."
    systemctl daemon-reload
    systemctl enable frps >/dev/null 2>&1
    systemctl start frps

    echo -e "${GREEN}frps 安装成功!${NC}"
    show_config
}

# 任务：卸载 frps
do_uninstall() {
    if ! check_if_installed; then
        echo -e "${RED}错误: frps 未安装。${NC}"
        return
    fi

    read -p "您确定要卸载 frps 吗？这将移除所有相关文件和配置。[y/N]: " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
        echo -e "${YELLOW}卸载已取消。${NC}"
        return
    fi

    echo -e "${YELLOW}正在停止并禁用 frps 服务...${NC}"
    systemctl stop frps
    systemctl disable frps >/dev/null 2>&1

    echo "正在移除文件..."
    rm -f "$FRPS_INSTALL_PATH"
    rm -f "$FRPS_SERVICE_PATH"
    rm -rf "/etc/frp" # 移除整个配置目录
    rm -f "/var/log/frps.log" # 移除日志文件

    echo "正在重载 systemd..."
    systemctl daemon-reload

    echo -e "${GREEN}frps 已成功卸载。${NC}"
}

# 任务：显示配置
show_config() {
    if ! check_if_installed; then
        echo -e "${RED}错误: frps 未安装，无法查看配置。${NC}"
        return
    fi
    
    # 从配置文件中提取信息
    SERVER_PORT=$(grep "bindPort" "$FRPS_CONFIG_PATH" | sed 's/.*= //')
    TOKEN=$(grep "token" "$FRPS_CONFIG_PATH" | sed 's/.*= "//' | sed 's/"//')
    DASHBOARD_PORT=$(grep "webServer.port" "$FRPS_CONFIG_PATH" | sed 's/.*= //')
    DASHBOARD_USER=$(grep "webServer.user" "$FRPS_CONFIG_PATH" | sed 's/.*= "//' | sed 's/"//')
    
    echo -e "${BLUE}---------- frps 当前配置信息 ----------${NC}"
    echo -e "配置文件路径:   ${YELLOW}$FRPS_CONFIG_PATH${NC}"
    echo -e "服务端口:       ${GREEN}$SERVER_PORT${NC}"
    echo -e "认证令牌:       ${GREEN}$TOKEN${NC}"
    echo -e "Dashboard 端口:   ${GREEN}$DASHBOARD_PORT${NC}"
    echo -e "Dashboard 用户:   ${GREEN}$DASHBOARD_USER${NC}"
    echo -e "-------------------------------------------"
    echo -e "要查看完整配置，请运行: ${YELLOW}cat $FRPS_CONFIG_PATH${NC}"
}

# --- 管理菜单 ---
show_manage_menu() {
    while true; do
        clear
        echo -e "${BLUE}--- frps 管理菜单 (精简版) ---${NC}"
        systemctl is-active --quiet frps && echo -e "服务状态: ${GREEN}运行中${NC}" || echo -e "服务状态: ${RED}已停止${NC}"
        echo "-----------------------"
        echo " 1. 启动 frps"
        echo " 2. 停止 frps"
        echo " 3. 重启 frps"
        echo " 4. 查看 frps 状态"
        echo " 5. 查看实时日志"
        echo " 6. 查看当前配置"
        echo " 0. 返回主菜单"
        echo "-----------------------"
        read -p "请输入选项 [0-6]: " choice

        case $choice in
            1) systemctl start frps && echo -e "${GREEN}服务已启动。${NC}" ;;
            2) systemctl stop frps && echo -e "${YELLOW}服务已停止。${NC}" ;;
            3) systemctl restart frps && echo -e "${GREEN}服务已重启。${NC}" ;;
            4) systemctl status frps ;;
            5) journalctl -u frps -f ;;
            6) show_config ;;
            0) return ;;
            *) echo -e "${RED}无效选项，请重试。${NC}" ;;
        esac
        read -p "按任意键继续..."
    done
}


# --- 主菜单 ---
show_main_menu() {
    clear
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}      frps 多功能管理脚本 v2.1 (精简版)   ${NC}"
    echo -e "${GREEN}==========================================${NC}"
    
    if check_if_installed; then
        echo " frps 已安装。"
        echo "------------------------------------------"
        echo " 1. ${BLUE}管理 frps 服务${NC} (启动/停止/查看配置等)"
        echo " 2. ${RED}卸载 frps${NC}"
        echo " 0. ${YELLOW}退出脚本${NC}"
        echo "------------------------------------------"
        read -p "请输入选项 [0-2]: " choice
        case $choice in
            1) show_manage_menu ;;
            2) do_uninstall ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选项!${NC}"; sleep 1 ;;
        esac
    else
        echo " frps 未安装。"
        echo "------------------------------------------"
        echo " 1. ${GREEN}安装 frps${NC}"
        echo " 0. ${YELLOW}退出脚本${NC}"
        echo "------------------------------------------"
        read -p "请输入选项 [0-1]: " choice
        case $choice in
            1) do_install ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选项!${NC}"; sleep 1 ;;
        esac
    fi
}

# --- 脚本入口 ---
main() {
    check_root
    while true; do
        show_main_menu
    done
}

# 运行主程序
main
