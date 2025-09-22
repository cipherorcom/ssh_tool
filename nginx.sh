#!/bin/bash
# =========================================================================
# Script Name: Nginx Installation and Management Tool
# Description: Installs Nginx and manages website/proxy configs with SSL.
# Author(s):   cipherorcom (base) + Gemini AI (features)
#              Revised for AlmaLinux/CentOS/RHEL/Debian/Ubuntu by ChatGPT
# Version:     3.1.1
# =========================================================================

set -euo pipefail

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Global Variables (will be adjusted by detect_os) ---
SITES_AVAILABLE="/etc/nginx/sites-available"
SITES_ENABLED="/etc/nginx/sites-enabled"
SSL_DIR="/etc/nginx/ssl"
NGINX_USER="www-data"   # Debian/Ubuntu default
PKG_MGR=""
IS_RHEL=false           # AlmaLinux/CentOS/RHEL family
CONF_EXT=""             # ".conf" on RHEL's conf.d, "" on Debian's sites-available
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
    *)
      echo -e "${RED}未知包管理器：$PKG_MGR${NC}"; exit 1;;
  esac
}

ensure_layout() {
  # 在需要的位置创建目录，并仅在 nginx.conf 存在时修改 include
  if $IS_RHEL; then
    mkdir -p "$SITES_AVAILABLE" "$SSL_DIR"
    # RHEL: /etc/nginx/nginx.conf 默认 include conf.d/*.conf; 无需修改
  else
    mkdir -p "$SITES_AVAILABLE" "$SITES_ENABLED" "$SSL_DIR"
    local conf="/etc/nginx/nginx.conf"
    if [ -f "$conf" ]; then
      # 如果尚未包含 sites-enabled，则插入一行
      if ! grep -qE 'include[[:space:]]+/etc/nginx/sites-enabled/\*' "$conf"; then
        # 在 http { 后插入 include 行（避免重复）
        sed -i '/http[[:space:]]*{/a \    include /etc/nginx/sites-enabled/*;' "$conf"
      fi
    else
      echo -e "${YELLOW}提示：未找到 $conf，将在安装 Nginx 后再处理站点布局。${NC}"
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
  # 仅在 RHEL/AlmaLinux 且 SELinux 开启时处理
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
  if command -v nginx >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
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

  if $IS_RHEL && command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" != "Disabled" ]]; then
    restorecon -Rv "$SSL_DIR" >/dev/null 2>&1 || true
  fi

  echo -e "${GREEN}证书和私钥已保存。${NC}"
  return 0
}

ssl_generate_self_signed() {
  local domain_name=$1
  echo -e "${BLUE}--- 生成自签名SSL证书 ---${NC}"

  if ! command -v openssl >/dev/null 2>&1; then
    echo -e "${YELLOW}检测到 'openssl' 未安装，正在安装...${NC}"
    case "$PKG_MGR" in
      apt-get) apt-get update -y && apt-get install -y openssl ;;
      dnf|yum) $PKG_MGR install -y openssl ;;
    esac
  fi

  mkdir -p "$SSL_DIR"
  CERT_PATH="$SSL_DIR/$domain_name.crt"
  KEY_PATH="$SSL_DIR/$domain_name.key"

  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$KEY_PATH" -out "$CERT_PATH" \
    -subj "/C=US/ST=State/L=City/O=Self-Signed/OU=IT/CN=$domain_name"

  chmod 600 "$KEY_PATH"
  chown root:root "$KEY_PATH" "$CERT_PATH" || true

  if $IS_RHEL && command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" != "Disabled" ]]; then
    restorecon -Rv "$SSL_DIR" >/dev/null 2>&1 || true
  fi

  echo -e "${GREEN}已成功生成自签名证书和私钥。${NC}"
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

  if $IS_RHEL && command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" != "Disabled" ]]; then
    restorecon -Rv "$(dirname "$CERT_PATH")" >/dev/null 2>&1 || true
    restorecon -Rv "$(dirname "$KEY_PATH")"  >/dev/null 2>&1 || true
  fi
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

create_web_root() {
  local web_root=$1
  mkdir -p "$web_root"
  chown -R "$NGINX_USER:$NGINX_USER" "$web_root" || true

  if $IS_RHEL && command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" != "Disabled" ]]; then
    if command -v semanage >/dev/null 2>&1; then
      semanage fcontext -a -t httpd_sys_content_t "${web_root}(/.*)?" 2>/dev/null || true
    fi
    restorecon -Rv "$web_root" >/dev/null 2>&1 || true
  fi
}

create_website_config() {
  echo -e "${BLUE}--- 添加一个新的静态网站 ---${NC}"
  read -rp "请输入域名 (例如: www.example.com): " domain_name
  [ -z "${domain_name:-}" ] && { echo -e "${RED}错误：域名不能为空。${NC}"; return 1; }

  local default_web_root="/var/www/$domain_name"
  read -rp "网站根目录 (默认: $default_web_root): " web_root
  web_root=${web_root:-$default_web_root}
  create_web_root "$web_root"

  if [ ! -f "$web_root/index.html" ]; then
    cat > "$web_root/index.html" <<EOF
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8"/>
  <title>Welcome to $domain_name!</title>
  <style>body{width:35em;margin:0 auto;font-family:Tahoma,Verdana,Arial,sans-serif;}</style>
</head>
<body>
  <h1>Welcome to $domain_name!</h1>
  <p>Nginx server block for <strong>$domain_name</strong> is working.</p>
  <p>Web root: <code>$web_root</code></p>
</body>
</html>
EOF
  fi

  local cfg_path
  if $IS_RHEL; then
    cfg_path="$SITES_AVAILABLE/${domain_name}${CONF_EXT}"
  else
    cfg_path="$SITES_AVAILABLE/${domain_name}"
  fi

  if [ -f "$cfg_path" ]; then
    echo -e "${RED}错误：配置已存在：$cfg_path${NC}"; return 1;
  fi

  cat > "$cfg_path" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain_name;

    root $web_root;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    access_log /var/log/nginx/${domain_name}.access.log;
    error_log  /var/log/nginx/${domain_name}.error.log;
}
EOF

  echo -e "${GREEN}已创建配置：$cfg_path${NC}"
  enable_site "$domain_name" "$cfg_path"
}

create_proxy_config() {
  echo -e "${BLUE}--- 添加一个新的反向代理 ---${NC}"
  read -rp "请输入域名 (例如: app.example.com): " domain_name
  [ -z "${domain_name:-}" ] && { echo -e "${RED}错误：域名不能为空。${NC}"; return 1; }

  read -rp "请输入要代理的后端地址 (例如: 127.0.0.1:8080): " proxy_pass_addr
  [ -z "${proxy_pass_addr:-}" ] && { echo -e "${RED}错误：后端地址不能为空。${NC}"; return 1; }

  local use_ssl=false
  read -rp "是否为此站点启用 SSL (https)? [y/N]: " enable_ssl
  if [[ "${enable_ssl:-}" =~ ^[yY]$ ]]; then
    use_ssl=true
    handle_ssl_configuration "$domain_name" || { echo -e "${RED}SSL配置失败。${NC}"; return 1; }
  fi

  local cfg_path
  if $IS_RHEL; then
    cfg_path="$SITES_AVAILABLE/${domain_name}${CONF_EXT}"
  else
    cfg_path="$SITES_AVAILABLE/${domain_name}"
  fi

  if [ -f "$cfg_path" ]; then
    echo -e "${RED}错误：配置已存在：$cfg_path${NC}"; return 1;
  fi

  if $use_ssl; then
    cat > "$cfg_path" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain_name;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain_name;

    ssl_certificate     $CERT_PATH;
    ssl_certificate_key $KEY_PATH;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    access_log /var/log/nginx/${domain_name}.access.log;
    error_log  /var/log/nginx/${domain_name}.error.log;

    location / {
        proxy_pass http://$proxy_pass_addr;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade  \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300;
        proxy_send_timeout 300;
    }
}
EOF
  else
    cat > "$cfg_path" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain_name;

    access_log /var/log/nginx/${domain_name}.access.log;
    error_log  /var/log/nginx/${domain_name}.error.log;

    location / {
        proxy_pass http://$proxy_pass_addr;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_read_timeout 300;
        proxy_send_timeout 300;
    }
}
EOF
  fi

  echo -e "${GREEN}已创建配置：$cfg_path${NC}"
  selinux_allow_proxy_and_contexts
  enable_site "$domain_name" "$cfg_path"
}

enable_site() {
  local domain_name=$1
  local cfg_path=$2

  echo -e "${BLUE}正在启用站点 ${domain_name}...${NC}"
  if $IS_RHEL; then
    # RHEL: 已处于 conf.d 目录下，无需软链
    :
  else
    ln -sf "$cfg_path" "$SITES_ENABLED/$domain_name"
  fi

  if nginx -t; then
    systemctl reload nginx
    echo -e "${GREEN}站点 ${domain_name} 已启用！${NC}"
    echo -e "${YELLOW}确保域名已正确解析到本机 IP。${NC}"
  else
    echo -e "${RED}Nginx 配置测试失败！回滚...${NC}"
    if ! $IS_RHEL; then
      rm -f "$SITES_ENABLED/$domain_name"
    fi
  fi
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

  if ! $IS_RHEL; then
    rm -f "$SITES_ENABLED/${filename}"
  fi
  rm -f "$SITES_AVAILABLE/${filename}"

  local base="${filename%.*}"
  local cert_file_to_delete="$SSL_DIR/$base.crt"
  if [ -f "$cert_file_to_delete" ]; then
    read -rp "检测到 ${base} 的证书，要一并删除吗？[y/N]: " del_cert
    if [[ "${del_cert:-}" =~ ^[yY]$ ]]; then
      rm -f "$SSL_DIR/$base.crt" "$SSL_DIR/$base.key"
      echo -e "${BLUE}已删除 SSL 证书文件。${NC}"
    fi
  fi

  systemctl reload nginx || true
  echo -e "${GREEN}站点 '${filename}' 已删除。${NC}"
}

list_sites() {
  echo -e "\n${BLUE}--- 当前已启用的 Nginx 站点 ---${NC}"
  if $IS_RHEL; then
    ls -1 "$SITES_ENABLED"/*.conf 2>/dev/null | sed 's#.*/##' || echo -e "${YELLOW}无${NC}"
  else
    if [ -d "$SITES_ENABLED" ] && compgen -G "$SITES_ENABLED/*" >/dev/null; then
      for s in "$SITES_ENABLED"/*; do
        [ -L "$s" ] && echo -e "-> ${GREEN}$(basename "$s")${NC} -> $(readlink -f "$s")"
      done
    else
      echo -e "${YELLOW}没有找到任何启用的站点。${NC}"
    fi
  fi
  echo ""
}

show_menu() {
  echo -e "\n${BLUE}Nginx 管理工具 v3.1.1${NC}"
  echo "============================="
  echo "1) 安装/修复 Nginx"
  echo "2) 添加静态网站"
  echo "3) 添加反向代理"
  echo "4) 删除站点"
  echo "5) 列出已启用站点"
  echo "6) 退出"
  echo "============================="
  read -rp "请输入选项 [1-6]: " main_choice
}

# --- Main ---
check_root
detect_os
# 注意：此处不再在安装前调用 ensure_layout，避免 nginx.conf 不存在导致的 grep/sed 报错

while true; do
  show_menu
  case ${main_choice:-} in
    1) install_nginx ;;
    2) create_website_config ;;
    3) create_proxy_config ;;
    4) delete_site ;;
    5) list_sites ;;
    6) exit 0 ;;
    *) echo -e "${RED}无效选项。${NC}" ;;
  esac
  read -rp "按 [Enter] 返回主菜单..."
done
