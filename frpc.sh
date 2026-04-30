#!/bin/bash

#================================================================================
# frpc 多功能管理脚本 (精简版)
#
# 功能:
#   - [安装] 交互式引导完成 frpc 的安装与配置
#   - [卸载] 干净地移除 frpc 服务和相关文件
#   - [管理] 启动/停止/重启服务、查看状态和日志、查看/修改配置
#================================================================================

# --- 全局变量和颜色定义 ---
FRPC_INSTALL_PATH="/usr/local/bin/frpc"
FRPC_CONFIG_PATH="/etc/frp/frpc.toml"
FRPC_SERVICE_PATH="/etc/systemd/system/frpc.service"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- 检查和准备工作 ---
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误: 此脚本必须以 root 权限运行。${NC}"
        exit 1
    fi
}

check_if_installed() {
    if [ -f "$FRPC_INSTALL_PATH" ]; then
        return 0
    else
        return 1
    fi
}

build_proxies_block() {
    local default_count="$1"
    local count i p_name p_type p_local_ip p_local_port p_remote_port
    local block=""

    read -p "请输入代理数量 [默认: ${default_count}]: " count
    count=${count:-$default_count}
    [[ "$count" =~ ^[0-9]+$ ]] || count=$default_count
    [ "$count" -lt 1 ] && count=1

    for ((i=1; i<=count; i++)); do
        echo ""
        echo -e "${BLUE}--- 配置第 ${i}/${count} 个代理 ---${NC}"
        read -p "代理名称 [默认: proxy${i}]: " p_name
        p_name=${p_name:-proxy${i}}
        read -p "代理类型 [默认: tcp]: " p_type
        p_type=${p_type:-tcp}
        read -p "本地服务地址 [默认: 127.0.0.1]: " p_local_ip
        p_local_ip=${p_local_ip:-127.0.0.1}
        read -p "本地服务端口 [默认: 22]: " p_local_port
        p_local_port=${p_local_port:-22}
        read -p "远程映射端口 [默认: $((6000 + i - 1))]: " p_remote_port
        p_remote_port=${p_remote_port:-$((6000 + i - 1))}

        block+="[[proxies]]\n"
        block+="name = \"${p_name}\"\n"
        block+="type = \"${p_type}\"\n"
        block+="localIP = \"${p_local_ip}\"\n"
        block+="localPort = ${p_local_port}\n"
        block+="remotePort = ${p_remote_port}\n\n"
    done

    PROXIES_BLOCK="$block"
}

# --- 功能函数 ---
do_install() {
    if check_if_installed; then
        echo -e "${YELLOW}检测到 frpc 已安装。如果您想重新安装，请先卸载。${NC}"
        return
    fi

    echo -e "${BLUE}--- 开始安装 frpc (精简版) ---${NC}"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    read -p "请输入要安装的 frp 版本 (直接回车使用最新版: $LATEST_VERSION): " USER_VERSION
    FRP_VERSION=${USER_VERSION:-$LATEST_VERSION}

    read -p "请输入 frps 服务端地址 [默认: 127.0.0.1]: " SERVER_ADDR
    SERVER_ADDR=${SERVER_ADDR:-127.0.0.1}
    read -p "请输入 frps 服务端口 [默认: 7000]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-7000}
    read -p "请输入认证令牌 (token): " TOKEN

    build_proxies_block 1

    echo -e "${YELLOW}正在准备安装环境...${NC}"
    ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')
    DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"
    TMP_FILE="/tmp/frp.tar.gz"

    echo "正在下载 frp v$FRP_VERSION..."
    curl -L -o "$TMP_FILE" "$DOWNLOAD_URL" || { echo -e "${RED}下载失败!${NC}"; exit 1; }

    echo "正在解压和安装..."
    tar -zxvf "$TMP_FILE" -C /tmp
    install -m 755 "/tmp/frp_${FRP_VERSION}_linux_${ARCH}/frpc" "$FRPC_INSTALL_PATH"

    echo "正在创建配置文件..."
    mkdir -p /etc/frp
    cat > "$FRPC_CONFIG_PATH" <<EOF
# frpc.toml (由精简版脚本生成)
serverAddr = "$SERVER_ADDR"
serverPort = $SERVER_PORT
auth.token = "$TOKEN"


$PROXIES_BLOCK

log.to = "/var/log/frpc.log"
log.level = "info"
log.maxDays = 7
EOF

    echo "正在创建 systemd 服务..."
    cat > "$FRPC_SERVICE_PATH" <<EOF
[Unit]
Description=frp client
After=network.target
[Service]
Type=simple
User=nobody
Restart=on-failure
RestartSec=5s
ExecStart=$FRPC_INSTALL_PATH -c $FRPC_CONFIG_PATH
[Install]
WantedBy=multi-user.target
EOF

    echo "清理临时文件..."
    rm -f "$TMP_FILE"
    rm -rf "/tmp/frp_${FRP_VERSION}_linux_${ARCH}"

    echo "启动并启用 frpc 服务..."
    systemctl daemon-reload
    systemctl enable frpc >/dev/null 2>&1
    systemctl start frpc

    echo -e "${GREEN}frpc 安装成功!${NC}"
    show_config
}

do_uninstall() {
    if ! check_if_installed; then
        echo -e "${RED}错误: frpc 未安装。${NC}"
        return
    fi

    read -p "您确定要卸载 frpc 吗？这将移除所有相关文件和配置。[y/N]: " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
        echo -e "${YELLOW}卸载已取消。${NC}"
        return
    fi

    echo -e "${YELLOW}正在停止并禁用 frpc 服务...${NC}"
    systemctl stop frpc
    systemctl disable frpc >/dev/null 2>&1

    echo "正在移除文件..."
    rm -f "$FRPC_INSTALL_PATH"
    rm -f "$FRPC_SERVICE_PATH"
    rm -f "$FRPC_CONFIG_PATH"
    rm -f "/var/log/frpc.log"

    echo "正在重载 systemd..."
    systemctl daemon-reload

    echo -e "${GREEN}frpc 已成功卸载。${NC}"
}

show_config() {
    if ! check_if_installed || [ ! -f "$FRPC_CONFIG_PATH" ]; then
        echo -e "${RED}错误: frpc 未安装或配置文件不存在。${NC}"
        return
    fi

    SERVER_ADDR=$(grep "^serverAddr" "$FRPC_CONFIG_PATH" | sed 's/.*= "//' | sed 's/"//')
    SERVER_PORT=$(grep "^serverPort" "$FRPC_CONFIG_PATH" | sed 's/.*= //' | tr -d ' ')
    TOKEN=$(grep "^auth.token" "$FRPC_CONFIG_PATH" | sed 's/.*= "//' | sed 's/"//')
    PROXY_COUNT=$(grep -c "^\[\[proxies\]\]" "$FRPC_CONFIG_PATH")

    echo -e "${BLUE}---------- frpc 当前配置信息 ----------${NC}"
    echo -e "配置文件路径:   ${YELLOW}$FRPC_CONFIG_PATH${NC}"
    echo -e "服务端地址:     ${GREEN}$SERVER_ADDR${NC}"
    echo -e "服务端端口:     ${GREEN}$SERVER_PORT${NC}"
    echo -e "认证令牌:       ${GREEN}$TOKEN${NC}"
    echo -e "代理数量:       ${GREEN}$PROXY_COUNT${NC}"
    echo -e "代理列表:"
    awk '
        /^\[\[proxies\]\]/{idx++;next}
        /^name = /{gsub(/"/,"",$3);name[idx]=$3}
        /^type = /{gsub(/"/,"",$3);type[idx]=$3}
        /^localIP = /{gsub(/"/,"",$3);lip[idx]=$3}
        /^localPort = /{lport[idx]=$3}
        /^remotePort = /{rport[idx]=$3}
        END {
            for(i=1;i<=idx;i++){
                printf("  - %s (%s) %s:%s -> remote:%s\n", name[i], type[i], lip[i], lport[i], rport[i])
            }
        }
    ' "$FRPC_CONFIG_PATH"
    echo -e "-------------------------------------------"
    echo -e "要查看完整配置，请运行: ${YELLOW}cat $FRPC_CONFIG_PATH${NC}"
}

do_edit_config() {
    if ! check_if_installed || [ ! -f "$FRPC_CONFIG_PATH" ]; then
        echo -e "${RED}错误: frpc 未安装或配置文件不存在。${NC}"
        return
    fi

    local current_server_addr current_server_port current_token current_proxy_count
    current_server_addr=$(grep "^serverAddr" "$FRPC_CONFIG_PATH" | sed 's/.*= "//' | sed 's/"//')
    current_server_port=$(grep "^serverPort" "$FRPC_CONFIG_PATH" | sed 's/.*= //' | tr -d ' ')
    current_token=$(grep "^auth.token" "$FRPC_CONFIG_PATH" | sed 's/.*= "//' | sed 's/"//')
    current_proxy_count=$(grep -c "^\[\[proxies\]\]" "$FRPC_CONFIG_PATH")

    read -p "请输入 frps 服务端地址 [当前: ${current_server_addr}]: " SERVER_ADDR
    SERVER_ADDR=${SERVER_ADDR:-$current_server_addr}
    read -p "请输入 frps 服务端口 [当前: ${current_server_port}]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-$current_server_port}
    read -p "请输入认证令牌 (token) [当前: ${current_token}]: " TOKEN
    TOKEN=${TOKEN:-$current_token}

    build_proxies_block "$current_proxy_count"

    cp -a "$FRPC_CONFIG_PATH" "${FRPC_CONFIG_PATH}.bak.$(date +%Y%m%d%H%M%S)"

    cat > "$FRPC_CONFIG_PATH" <<EOF
# frpc.toml (由精简版脚本更新)
serverAddr = "$SERVER_ADDR"
serverPort = $SERVER_PORT
auth.token = "$TOKEN"


$PROXIES_BLOCK

log.to = "/var/log/frpc.log"
log.level = "info"
log.maxDays = 7
EOF

    systemctl restart frpc
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}配置已更新并重启 frpc 成功。${NC}"
    else
        echo -e "${RED}配置已写入，但重启 frpc 失败，请检查配置和日志。${NC}"
    fi
}

# --- 管理菜单 ---
show_manage_menu() {
    while true; do
        clear
        echo -e "${BLUE}--- frpc 管理菜单 (精简版) ---${NC}"
        systemctl is-active --quiet frpc && echo -e "服务状态: ${GREEN}运行中${NC}" || echo -e "服务状态: ${RED}已停止${NC}"
        echo "-----------------------"
        echo " 1. 启动 frpc"
        echo " 2. 停止 frpc"
        echo " 3. 重启 frpc"
        echo " 4. 查看 frpc 状态"
        echo " 5. 查看实时日志"
        echo " 6. 查看当前配置"
        echo " 7. 修改当前配置"
        echo " 0. 返回主菜单"
        echo "-----------------------"
        read -p "请输入选项 [0-7]: " choice

        case $choice in
            1) systemctl start frpc && echo -e "${GREEN}服务已启动。${NC}" ;;
            2) systemctl stop frpc && echo -e "${YELLOW}服务已停止。${NC}" ;;
            3) systemctl restart frpc && echo -e "${GREEN}服务已重启。${NC}" ;;
            4) systemctl status frpc ;;
            5) journalctl -u frpc -f ;;
            6) show_config ;;
            7) do_edit_config ;;
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
    echo -e "${GREEN}      frpc 多功能管理脚本 v1.0 (精简版)   ${NC}"
    echo -e "${GREEN}==========================================${NC}"

    if check_if_installed; then
        echo " frpc 已安装。"
        echo "------------------------------------------"
        echo " 1. 管理 frpc 服务 (启动/停止/查看配置等)"
        echo " 2. 卸载 frpc"
        echo " 0. 退出脚本"
        echo "------------------------------------------"
        read -p "请输入选项 [0-2]: " choice
        case $choice in
            1) show_manage_menu ;;
            2) do_uninstall ;;
            0) exit 0 ;;
            *) echo -e "无效选项!"; sleep 1 ;;
        esac
    else
        echo " frpc 未安装。"
        echo "------------------------------------------"
        echo " 1. 安装 frpc"
        echo " 0. 退出脚本"
        echo "------------------------------------------"
        read -p "请输入选项 [0-1]: " choice
        case $choice in
            1) do_install ;;
            0) exit 0 ;;
            *) echo -e "无效选项!"; sleep 1 ;;
        esac
    fi
}

main() {
    check_root
    while true; do
        show_main_menu
    done
}

main
