#!/bin/bash

# =================================================================
#  交互式 Nginx 管理脚本
#
#  功能:
#  1. [安装]  - 安装、启动 Nginx 并设置为开机自启。
#  2. [卸载]  - 停止、禁用并卸载 Nginx。
#  3. [查询]  - 查询 Nginx 配置文件所在位置。
#
#  兼容性: Debian, Ubuntu, CentOS, RHEL, Fedora
# =================================================================

# 设置颜色代码以便输出更美观
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- 函数定义区域 ---

# 函数：安装 Nginx
install_nginx() {
    echo -e "\n${YELLOW}--- 开始安装 Nginx ---${NC}"
    if command -v apt >/dev/null; then
        echo "检测到 'apt' 包管理器 (Debian/Ubuntu)..."
        echo "正在更新包列表..."
        apt update -y
        echo "正在安装 Nginx..."
        apt install -y nginx
    elif command -v dnf >/dev/null; then
        echo "检测到 'dnf' 包管理器 (Fedora/RHEL/CentOS)..."
        echo "正在安装 Nginx..."
        dnf install -y nginx
    elif command -v yum >/dev/null; then
        echo "检测到 'yum' 包管理器 (CentOS/RHEL)..."
        echo "正在安装 EPEL release..."
        yum install -y epel-release
        echo "正在安装 Nginx..."
        yum install -y nginx
    else
        echo -e "${RED}错误：未检测到支持的包管理器 (apt, dnf, yum)。${NC}"
        exit 1
    fi

    if ! command -v nginx >/dev/null; then
        echo -e "${RED}错误：Nginx 安装失败。${NC}"
        exit 1
    fi

    echo -e "${GREEN}Nginx 安装成功！${NC}"
    echo "正在启动 Nginx 服务并设置为开机自启..."
    systemctl start nginx
    systemctl enable nginx

    if systemctl is-active --quiet nginx; then
        echo -e "${GREEN}Nginx 服务已成功启动并运行。${NC}"
    else
        echo -e "${YELLOW}警告：Nginx 服务未能启动，请运行 'systemctl status nginx' 查看详情。${NC}"
    fi
    # 安装后自动显示路径
    find_config
}

# 函数：卸载 Nginx
uninstall_nginx() {
    echo -e "\n${YELLOW}--- 开始卸载 Nginx ---${NC}"
    if ! command -v nginx >/dev/null; then
        echo -e "${YELLOW}Nginx 未安装，无需卸载。${NC}"
        return
    fi
    
    echo "正在停止并禁用 Nginx 服务..."
    systemctl stop nginx
    systemctl disable nginx

    if command -v apt >/dev/null; then
        echo "正在使用 'apt' 卸载 Nginx 及其配置文件..."
        apt purge -y nginx nginx-common
    elif command -v dnf >/dev/null; then
        echo "正在使用 'dnf' 卸载 Nginx..."
        dnf remove -y nginx
    elif command -v yum >/dev/null; then
        echo "正在使用 'yum' 卸载 Nginx..."
        yum remove -y nginx
    fi
    
    echo -e "${GREEN}Nginx 卸载完成。${NC}"
    echo "注意：部分日志文件或您手动创建的配置文件可能需要手动删除。"
}

# 函数：查询配置文件位置
find_config() {
    echo -e "\n${YELLOW}--- 查询 Nginx 配置文件位置 ---${NC}"
    if ! command -v nginx >/dev/null; then
        echo -e "${RED}错误：Nginx 未安装，无法查询。${NC}"
        return
    fi
    
    CONFIG_PATH=$(nginx -t 2>&1 | grep 'configuration file' | head -n 1 | awk '{print $5}')
    
    echo "-----------------------------------------------------"
    if [ -n "$CONFIG_PATH" ]; then
        echo -e "主配置文件路径: ${GREEN}${CONFIG_PATH}${NC}"
        
        # 根据系统类型判断站点目录
        if [ -d "/etc/nginx/sites-available" ]; then
            echo -e "站点配置文件目录: ${GREEN}/etc/nginx/sites-available${NC}"
            echo -e "已启用的站点目录: ${GREEN}/etc/nginx/sites-enabled${NC}"
        elif [ -d "/etc/nginx/conf.d" ]; then
            echo -e "站点配置文件目录: ${GREEN}/etc/nginx/conf.d${NC}"
        fi
    else
        echo -e "${RED}错误：未能自动定位到 Nginx 配置文件。${NC}"
    fi
    echo "-----------------------------------------------------"
}

# --- 主逻辑区域 ---

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}此脚本需要以 root 权限运行，请使用 sudo。${NC}"
  exit 1
fi

# 显示菜单
echo "==================================="
echo "     Nginx 管理脚本"
echo "==================================="
echo "请选择要执行的操作:"
echo "  1. 安装 Nginx"
echo "  2. 卸载 Nginx"
echo "  3. 查询配置文件位置"
echo "==================================="

# 读取用户输入
read -p "请输入您的选择 [1-3]: " choice

# 根据用户输入执行相应操作
case "$choice" in
    1)
        install_nginx
        ;;
    2)
        uninstall_nginx
        ;;
    3)
        find_config
        ;;
    *)
        echo -e "\n${RED}无效的选择，请输入 1, 2, 或 3。脚本退出。${NC}"
        exit 1
        ;;
esac

echo -e "\n${GREEN}操作完成。${NC}"
exit 0
