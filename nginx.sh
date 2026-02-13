#!/bin/bash
# =========================================================================
# Script Name: Nginx Installation and Management Tool
# Description: Installs Nginx, sets up CDN Proxy, and Local Reverse Proxy.
# Version:     3.4.1 (Added URL-based Local Proxy with WebSocket support)
# =========================================================================

set -euo pipefail

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Global Variables ---
SITES_AVAILABLE="/etc/nginx/sites-available"
SITES_ENABLED="/etc/nginx/sites-enabled"
SSL_DIR="/etc/nginx/ssl"
NGINX_USER="www-data"
PKG_MGR=""
IS_RHEL=false
CONF_EXT=""
OPENSSL_PKG="openssl"

CERT_PATH=""
KEY_PATH=""

# --- Helpers ---
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：此脚本必须以 root 权限运行。请使用 sudo。${NC}"
    exit 1
  fi
}

detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    ID_LIKE_LOWER=$(echo "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')
    ID_LOWER=$(echo "${ID:-}" | tr '[:upper:]' '[:lower:]')

    if [[ "$ID_LOWER" =~ (debian|ubuntu) || "$ID_LIKE_LOWER" =~ (debian|ubuntu) ]]; then
      PKG_MGR="apt-get"
      IS_RHEL=false
      NGINX_USER="www-data"
      SITES_AVAILABLE="/etc/nginx/sites-available"
      SITES_ENABLED="/etc/nginx/sites-enabled"
      SSL_DIR="/etc/nginx/ssl"
      CONF_EXT=""
      OPENSSL_PKG="openssl"
    elif [[ "$ID_LOWER" =~ (almalinux|centos|rhel|rocky) || "$ID_LIKE_LOWER" =~ (rhel|fedora|centos) ]]; then
      if command -v dnf >/dev/null 2>&1; then
        PKG_MGR="dnf"
      else
        PKG_MGR="yum"
      fi
      IS_RHEL=true
      NGINX_USER="nginx"
      SITES_AVAILABLE="/etc/nginx/conf.d"
      SITES_ENABLED="/etc/nginx/conf.d"
      SSL_DIR="/etc/pki/nginx"
      CONF_EXT=".conf"
      OPENSSL_PKG="openssl"
    else
      echo -e "${RED}错误：未识别的发行版（仅支持 Debian/Ubuntu 与 AlmaLinux/CentOS/RHEL）。${NC}"
      exit 1
    fi
  else
    echo -e "${RED}错误：无法检测系统 (缺少 /etc/os-release)。${NC}"
    exit 1
  fi
}

install_pkgs() {
  case "$PKG_MGR" in
    apt-get)
      apt-get update -y
      DEBIAN_FRONTEND=noninteractive apt-get install -y nginx curl "$OPENSSL_PKG"
      ;;
    dnf)
      $PKG_MGR install -y epel-release || true
      $PKG_MGR install -y nginx curl "$OPENSSL_PKG" policycoreutils-python-utils || true
      ;;
    yum)
      $PKG_MGR install -y epel-release || true
      $PKG_MGR install -y nginx curl "$OPENSSL_PKG" policycoreutils-python || true
      ;;
  esac
}

ensure_layout() {
  if $IS_RHEL; then
    mkdir -p "$SITES_AVAILABLE" "$SSL_DIR"
  else
    mkdir -p "$SITES_AVAILABLE" "$SITES_ENABLED" "$SSL_DIR"
    local conf="/etc/nginx/nginx.conf"
    if [ -f "$conf" ]; then
      if ! grep -qE 'include[[:space:]]+/etc/nginx/sites-enabled/\*' "$conf"; then
        sed -i '/http[[:space:]]*{/a \    include /etc/nginx/sites-enabled/*;' "$conf"
      fi
    fi
  fi
}

start_enable_nginx() {
  systemctl enable --now nginx
}

config_firewall() {
  echo -e "${BLUE}正在配置防火墙...${NC}"
  if command -v ufw >/dev/null 2>&1; then
    ufw allow 'Nginx Full' || true
    ufw reload || true
  elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-service=http || true
    firewall-cmd --permanent --add-service=https || true
    firewall-cmd --reload || true
  fi
}

selinux_allow_proxy_and_contexts() {
  if $IS_RHEL && command -v getenforce >/dev/null 2>&1; then
    if [[ "$(getenforce)" != "Disabled" ]]; then
      if command -v setsebool >/dev/null 2>&1; then
        setsebool -P httpd_can_network_connect 1 || true
      fi
      if command -v semanage >/dev/null 2>&1; then
        semanage fcontext -a -t httpd_config_t "$SITES_AVAILABLE(/.*)?" 2>/dev/null || true
        semanage fcontext -a -t cert_t "$SSL_DIR(/.*)?" 2>/dev/null || true
      fi
      restorecon -Rv /etc/nginx >/dev/null 2>&1 || true
    fi
  fi
}

check_nginx_installed() {
  command -v nginx >/dev/null 2>&1
}

# --- SSL Functions ---
ssl_from_paste() {
  local domain_name=$1
  echo -e "${BLUE}--- 通过粘贴内容提供SSL证书 ---${NC}"
  mkdir -p "$SSL_DIR"
  CERT_PATH="$SSL_DIR/$domain_name.crt"
  KEY_PATH="$SSL_DIR/$domain_name.key"

  echo -e "${YELLOW}请粘贴证书内容 (结束按 Ctrl+D)：${NC}"
  cat > "$CERT_PATH"
  if [ ! -s "$CERT_PATH" ]; then echo -e "${RED}错误：证书文件为空。${NC}"; return 1; fi

  echo -e "${YELLOW}请粘贴私钥内容 (结束按 Ctrl+D)：${NC}"
  cat > "$KEY_PATH"
  if [ ! -s "$KEY_PATH" ]; then echo -e "${RED}错误：私钥文件为空。${NC}"; return 1; fi

  chmod 600 "$KEY_PATH"
  chown root:root "$KEY_PATH" "$CERT_PATH" || true
  return 0
}

ssl_generate_self_signed() {
  local domain_name=$1
  echo -e "${BLUE}--- 生成自签名SSL证书 ---${NC}"
  mkdir -p "$SSL_DIR"
  CERT_PATH="$SSL_DIR/$domain_name.crt"
  KEY_PATH="$SSL_DIR/$domain_name.key"

  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$KEY_PATH" -out "$CERT_PATH" \
    -subj "/C=US/ST=State/L=City/O=Self-Signed/OU=IT/CN=$domain_name" >/dev/null 2>&1

  chmod 600 "$KEY_PATH"
  chown root:root "$KEY_PATH" "$CERT_PATH" || true
  echo -e "${GREEN}已成功生成自签名证书。${NC}"
  return 0
}

ssl_from_path() {
  echo -e "${BLUE}--- 提供已有的证书文件路径 ---${NC}"
  read -rp "证书路径 (例如: /etc/letsencrypt/live/domain/fullchain.pem): " user_cert_path
  if [ ! -f "$user_cert_path" ]; then echo -e "${RED}错误：找不到证书文件。${NC}"; return 1; fi

  read -rp "私钥路径 (例如: /etc/letsencrypt/live/domain/privkey.pem): " user_key_path
  if [ ! -f "$user_key_path" ]; then echo -e "${RED}错误：找不到私钥文件。${NC}"; return 1; fi

  CERT_PATH=$user_cert_path
  KEY_PATH=$user_key_path
  echo -e "${GREEN}证书路径已确认。${NC}"
  return 0
}

handle_ssl_configuration() {
  local domain_name=$1
  CERT_PATH=""; KEY_PATH=""
  echo -e "\n请选择配置SSL证书的方式:"
  echo "1) 粘贴证书和私钥内容"
  echo "2) 生成自签名证书 (开发/测试)"
  echo "3) 输入服务器上已有证书和私钥的路径"
  read -rp "请输入选项 [1-3]: " ssl_choice
  case ${ssl_choice:-} in
    1) ssl_from_paste "$domain_name" ;;
    2) ssl_generate_self_signed "$domain_name" ;;
    3) ssl_from_path ;;
    *) echo -e "${RED}无效选项。${NC}"; return 1 ;;
  esac
}

# --- Core Logic ---
install_nginx() {
  if check_nginx_installed; then
    echo -e "${GREEN}Nginx 已安装。${NC}"
  else
    echo -e "${BLUE}开始安装 Nginx...${NC}"
    install_pkgs
  fi
  ensure_layout
  start_enable_nginx
  config_firewall
  selinux_allow_proxy_and_contexts
  echo -e "${GREEN}Nginx 安装并基础配置完成！${NC}"
}

enable_site() {
  local domain_name=$1
  local cfg_path=$2
  echo -e "${BLUE}正在启用站点 ${domain_name}...${NC}"
  if ! $IS_RHEL; then ln -sf "$cfg_path" "$SITES_ENABLED/$domain_name"; fi

  # 捕获测试结果，如果失败，先打印错误，再执行回滚清理
  if nginx_test_output=$(nginx -t 2>&1); then
    systemctl reload nginx
    echo -e "${GREEN}站点 ${domain_name} 已启用！${NC}"
  else
    echo -e "${RED}Nginx 配置测试失败！错误信息如下：${NC}"
    echo -e "${YELLOW}${nginx_test_output}${NC}"
    echo -e "${RED}正在回滚配置...${NC}"
    if ! $IS_RHEL; then rm -f "$SITES_ENABLED/$domain_name"; fi
  fi
}

# --- 通用 Nginx 配置文件生成器 ---
write_nginx_config() {
  local domain=$1
  local proxy_conf=$2
  local use_ssl=$3
  local cfg_path
  
  if $IS_RHEL; then cfg_path="$SITES_AVAILABLE/${domain}${CONF_EXT}"; else cfg_path="$SITES_AVAILABLE/${domain}"; fi
  if [ -f "$cfg_path" ]; then echo -e "${RED}错误：配置已存在：$cfg_path${NC}"; return 1; fi

  if $use_ssl; then
    cat > "$cfg_path" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain;

    ssl_certificate     $CERT_PATH;
    ssl_certificate_key $KEY_PATH;
    client_max_body_size 0;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    access_log /var/log/nginx/${domain}.access.log;
    error_log  /var/log/nginx/${domain}.error.log;

    location / {
$proxy_conf
    }
}
EOF
  else
    cat > "$cfg_path" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain;

    access_log /var/log/nginx/${domain}.access.log;
    error_log  /var/log/nginx/${domain}.error.log;

    location / {
$proxy_conf
    }
}
EOF
  fi

  echo -e "${GREEN}已创建配置：$cfg_path${NC}"
  selinux_allow_proxy_and_contexts
  enable_site "$domain" "$cfg_path"
}

create_website_config() {
  echo -e "${BLUE}--- 添加一个静态网站 ---${NC}"
  read -rp "请输入域名 (例如: www.example.com): " domain_name
  [ -z "${domain_name:-}" ] && { echo -e "${RED}错误：域名不能为空。${NC}"; return 1; }

  local default_web_root="/var/www/$domain_name"
  read -rp "网站根目录 (默认: $default_web_root): " web_root
  web_root=${web_root:-$default_web_root}
  mkdir -p "$web_root"
  chown -R "$NGINX_USER:$NGINX_USER" "$web_root" || true
  
  if [ ! -f "$web_root/index.html" ]; then
    echo "<!DOCTYPE html><html><head><title>$domain_name</title></head><body><h1>Welcome to $domain_name!</h1></body></html>" > "$web_root/index.html"
  fi

  local site_conf="
        root $web_root;
        index index.html index.htm;
        try_files \$uri \$uri/ =404;
  "
  write_nginx_config "$domain_name" "$site_conf" false
}

create_cdn_proxy() {
  echo -e "${BLUE}--- 添加 CDN 线路加速 (反代远程服务器) ---${NC}"
  read -rp "请输入本地域名（例如: cdn.example.com）: " domain_name
  [ -z "${domain_name:-}" ] && return 1

  read -rp "请输入源站完整 URL（例如: https://origin.com）: " target_url
  [ -z "${target_url:-}" ] && return 1

  local use_ssl=false
  read -rp "是否启用 HTTPS（SSL）？[y/N]: " enable_ssl
  if [[ "${enable_ssl:-}" =~ ^[yY]$ ]]; then
      use_ssl=true
      handle_ssl_configuration "$domain_name" || return 1
  fi

  local proxy_conf="
        proxy_pass $target_url;
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_set_header Connection \"\";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_ssl_server_name on;
        proxy_read_timeout 300;
        proxy_send_timeout 300;
  "
  write_nginx_config "$domain_name" "$proxy_conf" "$use_ssl"
}

create_local_proxy() {
  echo -e "${BLUE}--- 添加本地服务反代 (支持 WebSocket) ---${NC}"
  read -rp "请输入访问域名（例如: app.example.com）: " domain_name
  [ -z "${domain_name:-}" ] && return 1

  read -rp "请输入本地服务完整 URL（例如: http://127.0.0.1:8080 或 https://127.0.0.1:8443）: " local_url
  [ -z "${local_url:-}" ] && return 1

  local use_ssl=false
  read -rp "外部访问是否启用 HTTPS（SSL）？[y/N]: " enable_ssl
  if [[ "${enable_ssl:-}" =~ ^[yY]$ ]]; then
      use_ssl=true
      handle_ssl_configuration "$domain_name" || return 1
  fi

  local proxy_conf="
        proxy_pass $local_url;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";
        
        # 允许 HTTPS 本地服务
        proxy_ssl_server_name on;
  "
  write_nginx_config "$domain_name" "$proxy_conf" "$use_ssl"
}

delete_site() {
  echo -e "${BLUE}--- 删除一个站点配置 ---${NC}"
  local candidates=()
  if $IS_RHEL; then
    mapfile -t candidates < <(ls -1 "$SITES_AVAILABLE"/*.conf 2>/dev/null || true)
  else
    mapfile -t candidates < <(ls -1 "$SITES_AVAILABLE"/* 2>/dev/null || true)
  fi

  if [ ${#candidates[@]} -eq 0 ]; then
    echo -e "${YELLOW}没有找到任何站点配置文件。${NC}"
    return
  fi

  select site_to_delete in "${candidates[@]}"; do
    [ -n "${site_to_delete:-}" ] && break || echo -e "${RED}无效选择。${NC}"
  done

  local filename
  filename=$(basename "$site_to_delete")
  read -rp "确认删除站点 '${filename}' 配置？[y/N]: " confirmation
  [[ "${confirmation:-}" =~ ^[yY]$ ]] || { echo "已取消。"; return; }

  if ! $IS_RHEL; then rm -f "$SITES_ENABLED/${filename}"; fi
  rm -f "$SITES_AVAILABLE/${filename}"

  local base="${filename%.*}"
  if [ -f "$SSL_DIR/$base.crt" ]; then
    read -rp "删除证书文件？[y/N]: " del_cert
    if [[ "${del_cert:-}" =~ ^[yY]$ ]]; then rm -f "$SSL_DIR/$base.crt" "$SSL_DIR/$base.key"; fi
  fi
  systemctl reload nginx || true
  echo -e "${GREEN}站点 '${filename}' 已删除。${NC}"
}

list_sites() {
  echo -e "\n${BLUE}--- 当前已启用的 Nginx 站点 ---${NC}"
  if $IS_RHEL; then
    ls -1 "$SITES_ENABLED"/*.conf 2>/dev/null || echo "无"
  else
    ls -1 "$SITES_ENABLED"/* 2>/dev/null || echo "无"
  fi
  echo ""
}

show_menu() {
  echo -e "\n${BLUE}Nginx 管理工具 (增强版 v3.4.1)${NC}"
  echo "==========================================="
  echo "1) 安装/修复 Nginx"
  echo "2) 添加静态网站"
  echo "3) 添加 CDN 线路加速 (反代远程服务器)"
  echo "4) 添加本地服务反代 (输入完整URL，支持 WebSocket)"
  echo "5) 删除站点"
  echo "6) 列出已启用站点"
  echo "7) 退出"
  echo "==========================================="
  read -rp "请输入选项 [1-7]: " main_choice
}

# --- Main ---
check_root
detect_os

while true; do
  show_menu
  case ${main_choice:-} in
    1) install_nginx ;;
    2) create_website_config ;;
    3) create_cdn_proxy ;;
    4) create_local_proxy ;;
    5) delete_site ;;
    6) list_sites ;;
    7) exit 0 ;;
    *) echo -e "${RED}无效选项。${NC}" ;;
  esac
  read -rp "按 [Enter] 返回主菜单..."
done
