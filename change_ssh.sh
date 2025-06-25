#!/bin/bash

# =================================================================
#  交互式 SSH 管理脚本
#
#  功能:
#  1. [修改端口]  - 安全地修改 SSH 端口号，并提示进行外部端口验证。
#  2. [修改密码]  - 修改当前 sudo 用户的登录密码。
# =================================================================

# 颜色代码
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- 函数定义区域 ---

# 函数：修改 SSH 端口
change_ssh_port() {
    echo -e "\n${YELLOW}--- 开始修改 SSH 端口 ---${NC}"
    # ... (此处省略了之前版本中完整的端口修改代码，以保持清晰) ...
    # ... (实际脚本中会包含所有步骤：验证、备份、修改、提示等) ...
    
    # 为了简洁，我们仅保留核心逻辑框架
    # 1. 获取并验证新端口号
    while true; do
        read -p "请输入新的 SSH 端口号 (推荐使用 1024-65535 之间的端口): " NEW_PORT
        if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}无效输入。请输入一个数字。${NC}"; continue
        fi
        if [ "$NEW_PORT" -lt 1024 ] || [ "$NEW_PORT" -gt 65535 ]; then
            echo -e "${RED}无效端口。请输入 1024 到 65535 之间的端口号。${NC}"; continue
        fi
        CURRENT_PORT=$(ss -tlpn | grep sshd | awk '{print $4}' | awk -F ':' '{print $NF}' | head -n 1)
        if [ "$NEW_PORT" -eq "$CURRENT_PORT" ]; then
            echo -e "${RED}新端口号 (${NEW_PORT}) 与当前端口号相同，无需修改。${NC}"
            return # 从函数返回
        fi
        break
    done

    # 2. 备份
    SSHD_CONFIG="/etc/ssh/sshd_config"
    BACKUP_FILE="/etc/ssh/sshd_config.bak.$(date +%F_%T)"
    echo "正在备份 SSH 配置文件到 ${BACKUP_FILE} ..."
    cp "$SSHD_CONFIG" "$BACKUP_FILE"
    if [ $? -ne 0 ]; then echo -e "${RED}错误：备份失败！${NC}"; return; fi
    echo -e "${GREEN}备份成功！${NC}"

    # 3. 修改配置
    echo "正在修改 SSH 配置文件..."
    sed -i -E "s/^[#\s]*Port\s+[0-9]+/Port ${NEW_PORT}/" "$SSHD_CONFIG"
    sed -i -E "/^#?Port\s/ s/^#?Port\s/#&/" "$SSHD_CONFIG"
    sed -i -E "s/^##?Port\s+${NEW_PORT}/Port ${NEW_PORT}/" "$SSHD_CONFIG"
    if ! grep -q "^Port ${NEW_PORT}" "$SSHD_CONFIG"; then
        echo -e "${RED}错误：修改配置文件失败。${NC}"; cp "$BACKUP_FILE" "$SSHD_CONFIG"; return;
    fi
    echo -e "${GREEN}SSH 配置文件修改成功。${NC}"
    
    # 4. 提示用户手动检查端口
    PUBLIC_IP=$(curl -s --ipv4 ifconfig.me)
    echo -e "\n${YELLOW}==================== 请手动操作并确认 ====================${NC}"
    echo "下一步将重启SSH服务。在此之前，您必须在您的云服务商防火墙中放行新端口 ${NEW_PORT}。"
    echo -e "请在新浏览器标签页中打开以下链接，检查端口状态："
    echo -e "  ${GREEN}https://tcp.ping.pe/${PUBLIC_IP}:${NEW_PORT}${NC}"
    read -p "网站是否显示端口可以正常访问？ (y/n): " port_is_open

    if [[ "${port_is_open,,}" != "y" ]]; then
        echo -e "\n${RED}操作已由用户中止。正在恢复原始配置...${NC}"
        cp "$BACKUP_FILE" "$SSHD_CONFIG"
        echo "恢复完成。"
        return
    fi

    # 5. 重启服务并给出最终指导
    echo -e "\n${GREEN}好的，将重启 SSH 服务...${NC}"
    systemctl restart sshd
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误：重启 SSH 服务失败！${NC}"; cp "$BACKUP_FILE" "$SSHD_CONFIG"; systemctl restart sshd; return;
    fi
    echo -e "${GREEN}SSH 服务已重启。请立即打开新终端使用新端口验证登录！${NC}"
    echo -e "${YELLOW}ssh ${USER}@${PUBLIC_IP} -p ${NEW_PORT}${NC}"
}

# 函数：修改密码
change_password() {
    echo -e "\n${YELLOW}--- 开始修改 SSH 用户密码 ---${NC}"
    
    # SUDO_USER 环境变量通常会保留原始用户名
    if [ -n "$SUDO_USER" ]; then
        TARGET_USER="$SUDO_USER"
    else
        # 如果直接以 root 登录，SUDO_USER 可能为空
        echo -e "${YELLOW}无法自动检测到普通用户。${NC}"
        read -p "请输入您要修改密码的用户名: " TARGET_USER
        if ! id "$TARGET_USER" &>/dev/null; then
            echo -e "${RED}错误：用户 '${TARGET_USER}' 不存在。${NC}"
            return
        fi
    fi

    echo "将要修改用户 ${GREEN}${TARGET_USER}${NC} 的密码。"
    # 调用系统的 passwd 命令，它会安全地处理密码输入
    passwd "$TARGET_USER"

    # 检查 passwd 命令的退出状态
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}用户 '${TARGET_USER}' 的密码已成功修改！${NC}"
    else
        echo -e "\n${RED}密码修改失败。可能是两次输入的密码不匹配。${NC}"
    fi
}

# --- 主逻辑区域 ---

# 检查必备工具和 root 权限
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}此脚本需要以 root 权限运行，请使用 sudo。${NC}"
  exit 1
fi
if ! command -v curl >/dev/null; then
    echo -e "${RED}错误：需要 'curl' 命令。请先安装 (例如: sudo apt install curl)。${NC}"
    exit 1
fi

# 显示菜单
echo "==================================="
echo "     交互式 SSH 管理脚本"
echo "==================================="
echo "请选择要执行的操作:"
echo "  1. 修改 SSH 端口号"
echo "  2. 修改 SSH 用户密码"
echo "  3. 退出脚本"
echo "==================================="

# 读取用户输入
read -p "请输入您的选择 [1-3]: " choice

# 根据用户输入执行相应操作
case "$choice" in
    1)
        change_ssh_port
        ;;
    2)
        change_password
        ;;
    3)
        echo "正在退出脚本。"
        exit 0
        ;;
    *)
        echo -e "\n${RED}无效的选择，请输入 1, 2, 或 3。${NC}"
        exit 1
        ;;
esac

echo -e "\n${GREEN}操作完成。${NC}"
exit 0
