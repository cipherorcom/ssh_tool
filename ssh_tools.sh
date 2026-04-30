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

# 本地安装路径（用于快捷命令）
INSTALL_DIR="/usr/local/share/ssh-tools"
INSTALL_SCRIPT_PATH="${INSTALL_DIR}/ssh_tools.sh"
SHORTCUT_PATH="/usr/local/bin/ssh-tools"

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

install_bt_panel() {
    clear
    echo "=================================="
    echo "        安装宝塔面板"
    echo "=================================="

    # 1) 先判断是否已安装（通过 bt 命令）
    if command -v bt >/dev/null 2>&1; then
        echo "检测到宝塔已安装（bt 命令存在）：$(command -v bt)"
        echo "如需管理可直接执行：bt"
        read -n 1 -s -r -p "按任意键返回主菜单..."
        return 0
    fi

    # 有些环境 bt 在固定路径，额外兜底
    if [ -x /usr/bin/bt ] || [ -x /usr/local/bin/bt ]; then
        echo "检测到宝塔已安装（bt 脚本存在）"
        echo "如需管理可直接执行：bt"
        read -n 1 -s -r -p "按任意键返回主菜单..."
        return 0
    fi

    # 2) 未安装则询问后安装
    read -rp "未检测到宝塔，是否现在安装？(y/n): " confirm
    case "$confirm" in
        y|Y )
            wget -O install.sh https://bt.cxinyun.com/install/install_panel.sh && bash install.sh
            ;;
        * )
            echo "已取消安装"
            ;;
    esac

    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# 自动保存脚本并创建快捷命令 ssh-tools
ensure_shortcut_command() {
    # 仅 root 可写系统目录；非 root 时静默跳过
    if [[ $EUID -ne 0 ]]; then
        return 0
    fi

    mkdir -p "$INSTALL_DIR"

    # 优先从仓库拉取最新版；失败则用当前脚本兜底
    if ! curl -fsSL "${BASE_URL}/ssh_tools.sh" -o "$INSTALL_SCRIPT_PATH"; then
        if [[ -n "$0" && -f "$0" ]]; then
            cp -f "$0" "$INSTALL_SCRIPT_PATH" 2>/dev/null || return 0
        else
            return 0
        fi
    fi

    chmod +x "$INSTALL_SCRIPT_PATH"

    cat > "$SHORTCUT_PATH" <<EOF
#!/bin/bash
bash "$INSTALL_SCRIPT_PATH" "\$@"
EOF
    chmod +x "$SHORTCUT_PATH"
}

run_ecs_benchmark() {
    clear
    echo -e "${BLUE}================================================${PLAIN}"
    echo -e "${BLUE}         融合怪测评脚本 (ecs.sh)               ${PLAIN}"
    echo -e "${BLUE}================================================${PLAIN}"
    echo -e "${GREEN}正在下载并执行 ecs.sh ...${PLAIN}"

    curl -L "https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh" -o ecs.sh

    if [ $? -eq 0 ]; then
        chmod +x ecs.sh
        bash ecs.sh
        rm -f ecs.sh
    else
        echo -e "${RED}下载失败，请检查网络或链接可用性。${PLAIN}"
    fi

    echo ""
    read -n 1 -s -r -p "按任意键继续..."
}

run_nodequality_benchmark() {
    clear
    echo -e "${BLUE}================================================${PLAIN}"
    echo -e "${BLUE}       NodeQuality 测评脚本                     ${PLAIN}"
    echo -e "${BLUE}================================================${PLAIN}"
    echo -e "${GREEN}正在执行 NodeQuality 测评脚本...${PLAIN}"

    bash <(curl -sL https://run.NodeQuality.com)

    echo ""
    read -n 1 -s -r -p "按任意键继续..."
}

# ==================================================
# 分组子菜单
# ==================================================

system_menu() {
    while true; do
        clear
        echo -e "${BLUE}================================================${PLAIN}"
        echo -e "${BLUE}              系统基础菜单                      ${PLAIN}"
        echo -e "${BLUE}================================================${PLAIN}"
        echo -e "${GREEN}1.${PLAIN} swap管理 (swap.sh)"
        echo -e "${GREEN}2.${PLAIN} zram管理 (zram.sh)"
        echo -e "${GREEN}3.${PLAIN} Zsh一键安装 (zsh.sh)"
        echo -e "${BLUE}================================================${PLAIN}"
        echo -e "${YELLOW}0.${PLAIN} 返回主菜单"
        echo ""
        read -p "请输入选项 [0-3]: " sub_choice

        case $sub_choice in
            1) run_script "swap.sh" ;;
            2) run_script "zram.sh" ;;
            3) run_script "zsh.sh" ;;
            0) return ;;
            *) echo -e "${RED}无效输入${PLAIN}"; sleep 1 ;;
        esac
    done
}

security_menu() {
    while true; do
        clear
        echo -e "${BLUE}================================================${PLAIN}"
        echo -e "${BLUE}           SSH/网络与安全菜单                   ${PLAIN}"
        echo -e "${BLUE}================================================${PLAIN}"
        echo -e "${GREEN}1.${PLAIN} 修改SSH端口及密码 (change_ssh.sh)"
        echo -e "${GREEN}2.${PLAIN} 出站优先级管理脚本 (network.sh)"
        echo -e "${GREEN}3.${PLAIN} UFW管理 (ufw.sh)"
        echo -e "${GREEN}4.${PLAIN} Fail2ban管理 (fail2ban.sh)"
        echo -e "${BLUE}================================================${PLAIN}"
        echo -e "${YELLOW}0.${PLAIN} 返回主菜单"
        echo ""
        read -p "请输入选项 [0-4]: " sub_choice

        case $sub_choice in
            1) run_script "change_ssh.sh" ;;
            2) run_script "network.sh" ;;
            3) run_script "ufw.sh" ;;
            4) run_script "fail2ban.sh" ;;
            0) return ;;
            *) echo -e "${RED}无效输入${PLAIN}"; sleep 1 ;;
        esac
    done
}

service_menu() {
    while true; do
        clear
        echo -e "${BLUE}================================================${PLAIN}"
        echo -e "${BLUE}              服务与面板菜单                    ${PLAIN}"
        echo -e "${BLUE}================================================${PLAIN}"
        echo -e "${GREEN}1.${PLAIN} Nginx管理 (nginx.sh)"
        echo -e "${GREEN}2.${PLAIN} frps管理 (frps.sh)"
        echo -e "${GREEN}3.${PLAIN} frpc管理 (frpc.sh)"
        echo -e "${GREEN}4.${PLAIN} Sing-box四合一 (sb.sh)"
        echo -e "${GREEN}5.${PLAIN} Docker 管理 (安装/配置加速)"
        echo -e "${GREEN}6.${PLAIN} 安装宝塔 (Ubuntu/Debian)"
        echo -e "${BLUE}================================================${PLAIN}"
        echo -e "${YELLOW}0.${PLAIN} 返回主菜单"
        echo ""
        read -p "请输入选项 [0-6]: " sub_choice

        case $sub_choice in
            1) run_script "nginx.sh" ;;
            2) run_script "frps.sh" ;;
            3) run_script "frpc.sh" ;;
            4) run_script "sb.sh" ;;
            5) docker_menu ;;
            6) install_bt_panel ;;
            0) return ;;
            *) echo -e "${RED}无效输入${PLAIN}"; sleep 1 ;;
        esac
    done
}

benchmark_menu() {
    while true; do
        clear
        echo -e "${BLUE}================================================${PLAIN}"
        echo -e "${BLUE}               性能测评菜单                     ${PLAIN}"
        echo -e "${BLUE}================================================${PLAIN}"
        echo -e "${GREEN}1.${PLAIN} 融合怪测评脚本 (ecs.sh)"
        echo -e "${GREEN}2.${PLAIN} NodeQuality 测评脚本"
        echo -e "${BLUE}================================================${PLAIN}"
        echo -e "${YELLOW}0.${PLAIN} 返回主菜单"
        echo ""
        read -p "请输入选项 [0-2]: " sub_choice

        case $sub_choice in
            1) run_ecs_benchmark ;;
            2) run_nodequality_benchmark ;;
            0) return ;;
            *) echo -e "${RED}无效输入${PLAIN}"; sleep 1 ;;
        esac
    done
}

search_menu() {
    while true; do
        clear
        echo -e "${BLUE}================================================${PLAIN}"
        echo -e "${BLUE}                 一键搜索脚本                   ${PLAIN}"
        echo -e "${BLUE}================================================${PLAIN}"
        echo "支持关键词示例: ssh / nginx / docker / 测评 / bbr"
        echo ""
        read -rp "请输入关键词（直接回车返回）: " keyword

        [[ -z "$keyword" ]] && return

        local items=(
            "swap管理|swap.sh|run_script:swap.sh"
            "修改SSH端口及密码|change_ssh.sh|run_script:change_ssh.sh"
            "Nginx管理|nginx.sh|run_script:nginx.sh"
            "frps管理|frps.sh|run_script:frps.sh"
            "frpc管理|frpc.sh|run_script:frpc.sh"
            "zram管理|zram.sh|run_script:zram.sh"
            "Sing-box四合一|sb.sh|run_script:sb.sh"
            "Zsh一键安装|zsh.sh|run_script:zsh.sh"
            "Docker管理|docker_menu|func:docker_menu"
            "出站优先级管理|network.sh|run_script:network.sh"
            "UFW管理|ufw.sh|run_script:ufw.sh"
            "Fail2ban管理|fail2ban.sh|run_script:fail2ban.sh"
            "安装宝塔|bt_panel|func:install_bt_panel"
            "融合怪测评|ecs.sh|func:run_ecs_benchmark"
            "NodeQuality测评|NodeQuality|func:run_nodequality_benchmark"
            "BBR调优|bbr.sh|run_script:bbr.sh"
        )

        local match_indexes=()
        local i=0
        local item name target action lower_item lower_keyword
        lower_keyword=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')

        for item in "${items[@]}"; do
            name=${item%%|*}
            target=${item#*|}; target=${target%%|*}
            action=${item##*|}

            lower_item=$(echo "${name} ${target}" | tr '[:upper:]' '[:lower:]')
            if [[ "$lower_item" == *"$lower_keyword"* ]] || [[ "${name}${target}" == *"$keyword"* ]]; then
                match_indexes+=("$i")
            fi
            ((i++))
        done

        if [[ ${#match_indexes[@]} -eq 0 ]]; then
            echo ""
            echo -e "${YELLOW}未找到匹配项，请换个关键词重试。${PLAIN}"
            read -n 1 -s -r -p "按任意键继续..."
            continue
        fi

        echo ""
        echo -e "${GREEN}匹配结果：${PLAIN}"
        local n=1 idx
        for idx in "${match_indexes[@]}"; do
            item=${items[$idx]}
            name=${item%%|*}
            target=${item#*|}; target=${target%%|*}
            echo -e "${GREEN}${n}.${PLAIN} ${name} (${target})"
            ((n++))
        done
        echo -e "${YELLOW}0.${PLAIN} 重新搜索"
        echo ""

        read -rp "请选择要执行的脚本: " pick
        if [[ "$pick" == "0" ]]; then
            continue
        fi

        if ! [[ "$pick" =~ ^[0-9]+$ ]] || (( pick < 1 || pick > ${#match_indexes[@]} )); then
            echo -e "${RED}无效输入${PLAIN}"
            sleep 1
            continue
        fi

        idx=${match_indexes[$((pick-1))]}
        item=${items[$idx]}
        action=${item##*|}

        if [[ "$action" == run_script:* ]]; then
            run_script "${action#run_script:}"
        elif [[ "$action" == func:* ]]; then
            "${action#func:}"
        else
            echo -e "${RED}内部错误：未知动作${PLAIN}"
            sleep 1
        fi
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
        echo -e "${GREEN}1.${PLAIN} 系统基础"
        echo -e "${GREEN}2.${PLAIN} SSH/网络与安全"
        echo -e "${GREEN}3.${PLAIN} 服务与面板"
        echo -e "${GREEN}4.${PLAIN} 性能测评"
        echo -e "${GREEN}5.${PLAIN} 一键搜索脚本"
        echo -e "${BLUE}================================================${PLAIN}"
        echo -e "${YELLOW}0.${PLAIN} 退出脚本"
        echo ""
        read -p "请输入选项 [0-5]: " choice

        case $choice in
            1) system_menu ;;
            2) security_menu ;;
            3) service_menu ;;
            4) benchmark_menu ;;
            5) search_menu ;;
            0) echo "退出。"; exit 0 ;;
            *) echo -e "${RED}无效输入，请重新选择。${PLAIN}"; sleep 1 ;;
        esac
    done
}

# ==================================================
# 脚本入口
# ==================================================
check_dependencies
ensure_shortcut_command
main_menu
