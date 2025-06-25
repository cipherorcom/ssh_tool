#!/bin/bash

# =================================================================
#  交互式 SSH 管理脚本 (V3 - 安全流程优化版)
#
#  功能:
#  1. [修改端口]  - 重启SSH后，引导用户进行外部验证和故障恢复。
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
            return
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
    echo "正在修改 SSH 配置文件以使用新端口 ${NEW_PORT}..."
    sed -i -E "s/^[#\s]*Port\s+[0-9]+/Port ${NEW_PORT}/" "$SSHD_CONFIG"
    sed -i -E "/^#?Port\s/ s/^#?Port\s/#&/" "$SSHD_CONFIG"
    sed -i -E "s/^##?Port\s+${NEW_PORT}/Port ${NEW_PORT}/" "$SSHD_CONFIG"
    if ! grep -q "^Port ${NEW_PORT}" "$SSHD_CONFIG"; then
        echo -e "${RED}错误：修改配置文件失败。${NC}"; cp "$BACKUP_FILE" "$SSHD_CONFIG"; return;
    fi
    echo -e "${GREEN}SSH 配置文件修改成功。${NC}"

    # 4. 【关键步骤】强制用户确认防火墙已配置
    echo -e "\n${YELLOW}==================== 请手动操作并确认 ====================${NC}"
    echo "下一步将重启SSH服务，这是不可逆的操作（在当前会话中）。"
    echo -e "在此之前，请务必在您的 ${RED}云服务商控制台（AWS、阿里云等）的防火墙或安全组${NC}中，"
    echo -e "添加入站规则，允许 TCP 端口 ${YELLOW}${NEW_PORT}${NC} 的访问。"
    echo "------------------------------------------------------------------"
    read -p "我已完成云防火墙的配置，并允许了新端口。 (y/n): " firewall_configured

    if [[ "${firewall_configured,,}" != "y" ]]; then
        echo -e "\n${RED}操作已由用户中止。正在恢复原始配置...${NC}"
        cp "$BACKUP_FILE" "$SSHD_CONFIG"
        echo "恢复完成。SSH 端口未做任何更改。"
        return
    fi
    
    # 5. 重启服务
    echo -e "\n${GREEN}好的，正在重启 SSH 服务以应用新端口...${NC}"
    systemctl restart sshd
    # 检查重启命令本身是否成功
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误：SSH 服务启动失败！可能是 sshd_config 文件存在语法错误。${NC}"
        echo "请在此窗口中运行 'journalctl -xeu sshd' 查看详细错误。"
        echo "正在自动从备份恢复并再次重启..."
        cp "$BACKUP_FILE" "$SSHD_CONFIG"
        systemctl restart sshd
        echo "已恢复到原始配置。"
        return
    fi
    
    # 6. 【关键步骤】给出重启后的验证与恢复指南
    PUBLIC_IP=$(curl -s --ipv4 ifconfig.me)
    echo -e "${GREEN}SSH 服务已重启。现在是验证新端口是否正常工作的关键时刻。${NC}"
    echo -e "${RED}==================== 重要！请立即验证！ ====================${NC}"
    echo -e "  1. ${YELLOW}请不要关闭当前的 SSH 连接！${NC} 它是您唯一的救生索。"
    echo
    echo -e "  2. ${GREEN}第一步：使用外部工具检查端口连通性。${NC}"
    echo -e "     请在新浏览器标签页中打开以下链接："
    echo -e "     ${YELLOW}https://tcp.ping.pe/${PUBLIC_IP}:${NEW_PORT}${NC}"
    echo -e "     如果网站显示多个地区测试 'succeeded'，说明您的云防火墙配置正确，"
    echo -e "     并且 SSH 服务已成功在新端口上运行。"
    echo
    echo -e "  3. ${GREEN}第二步：尝试使用新端口建立新的 SSH 连接。${NC}"
    echo -e "     请打开一个 ${RED}新的本地终端窗口${NC}，运行以下命令："
    echo -e "     ${YELLOW}ssh ${USER}@${PUBLIC_IP} -p ${NEW_PORT}${NC}"
    echo
    echo -e "  4. ${GREEN}如果新连接成功，恭喜您！所有操作已完成，您可以安全地关闭此窗口。${NC}"
    echo
    echo -e "  5. ${RED}如果新连接失败，请不要惊慌，按以下步骤处理：${NC}"
    echo -e "     - 失败原因通常是：a) 云防火墙未放行 b) 系统内部防火墙(ufw/firewalld)拦截 c) SELinux策略。"
    echo -e "     - 您可以**在此旧的终端窗口中**，运行下面的**恢复命令**来撤销所有更改："
    echo -e "       ${YELLOW}sudo cp ${BACKUP_FILE} ${SSHD_CONFIG} && sudo systemctl restart sshd${NC}"
    echo -e "     - 运行恢复命令后，您的 SSH 将回到原始端口，可以重新连接。"
    echo -e "${RED}================================================================${NC}"
}

# 函数：修改密码
change_password() {
    echo -e "\n${YELLOW}--- 开始修改 SSH 用户密码 ---${NC}"
    if [ -n "$SUDO_USER" ]; then
        TARGET_USER="$SUDO_USER"
    else
        echo -e "${YELLOW}无法自动检测到普通用户。${NC}"
        read -p "请输入您要修改密码的用户名: " TARGET_USER
        if ! id "$TARGET_USER" &>/dev/null; then
            echo -e "${RED}错误：用户 '${TARGET_USER}' 不存在。${NC}"; return
        fi
    fi
    echo "将要修改用户 ${GREEN}${TARGET_USER}${NC} 的密码。"
    passwd "$TARGET_USER"
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}用户 '${TARGET_USER}' 的密码已成功修改！${NC}"
    else
        echo -e "\n${RED}密码修改失败。${NC}"
    fi
}

# --- 主逻辑区域 ---

# 检查必备工具和 root 权限
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}此脚本需要以 root 权限运行，请使用 sudo。${NC}"; exit 1;
fi
if ! command -v curl >/dev/null; then
    echo -e "${RED}错误：需要 'curl' 命令。请先安装 (例如: sudo apt install curl)。${NC}"; exit 1;
fi

# 显示菜单
echo "==================================="
echo "     交互式 SSH 管理脚本 (V3)"
echo "==================================="
echo "请选择要执行的操作:"
echo "  1. 修改 SSH 端口号"
echo "  2. 修改 SSH 用户密码"
echo "  3. 退出脚本"
echo "==================================="
read -p "请输入您的选择 [1-3]: " choice

case "$choice" in
    1) change_ssh_port ;;
    2) change_password ;;
    3) echo "正在退出脚本。"; exit 0 ;;
    *) echo -e "\n${RED}无效的选择。${NC}"; exit 1 ;;
esac

echo -e "\n${GREEN}操作完成。${NC}"
exit 0
