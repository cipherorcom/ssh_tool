#!/usr/bin/env bash
set -Eeuo pipefail

# install-seaweedfs.sh
# Ubuntu/Debian + systemd
# Installs SeaweedFS single-node with Master, Volume, Filer HTTP, S3, WebDAV.

SEAWEED_USER="seaweedfs"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/seaweedfs"
DATA_DIR="/var/lib/seaweedfs"
LOG_DIR="/var/log/seaweedfs"

DEFAULT_MASTER_PORT="9333"
DEFAULT_VOLUME_PORT="8080"
DEFAULT_FILER_PORT="8888"
DEFAULT_S3_PORT="8333"
DEFAULT_WEBDAV_PORT="7333"
DEFAULT_VOLUME_MAX="30"

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "请用 root 运行，或使用: sudo bash $0"
    exit 1
  fi
}

ask() {
  local prompt="$1"
  local default="$2"
  local value
  read -r -p "${prompt} [${default}]: " value
  echo "${value:-$default}"
}

choose_bind_ip() {
  local choice
  local custom_ip

  echo "请选择监听 IP："
  echo "  1) 0.0.0.0      监听所有网卡，适合内网/容器/需要外部访问"
  echo "  2) 127.0.0.1    仅本机访问，适合前面有 Nginx/Caddy 反代"
  echo "  3) 自己输入     例如内网 IP: 192.168.1.10"
  echo

  while true; do
    read -r -p "请输入选项 [1/2/3，默认 1]: " choice
    choice="${choice:-1}"

    case "$choice" in
      1)
        echo "0.0.0.0"
        return 0
        ;;
      2)
        echo "127.0.0.1"
        return 0
        ;;
      3)
        while true; do
          read -r -p "请输入自定义监听 IP: " custom_ip

          if [ -z "$custom_ip" ]; then
            echo "IP 不能为空。"
            continue
          fi

          if echo "$custom_ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
            echo "$custom_ip"
            return 0
          fi

          echo "IP 格式看起来不正确，请输入类似 192.168.1.10 的 IPv4 地址。"
        done
        ;;
      *)
        echo "无效选项，请输入 1、2 或 3。"
        ;;
    esac
  done
}

check_port_number() {
  local name="$1"
  local port="$2"

  if ! echo "$port" | grep -Eq '^[0-9]+$'; then
    echo "错误: ${name} 端口不是数字: ${port}"
    exit 1
  fi

  if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    echo "错误: ${name} 端口超出范围: ${port}"
    exit 1
  fi
}

port_in_use() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    ss -ltn | awk '{print $4}' | grep -Eq "[:.]${port}$"
  else
    netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"
  fi
}

download_weed() {
  local arch
  local arch_regex
  local api
  local release_url
  local tmpdir

  arch="$(uname -m)"

  case "$arch" in
    x86_64|amd64)
      arch_regex='linux_amd64'
      ;;
    aarch64|arm64)
      arch_regex='linux_arm64'
      ;;
    armv7l)
      arch_regex='linux_arm'
      ;;
    *)
      echo "暂不支持的架构: ${arch}"
      exit 1
      ;;
  esac

  echo "安装依赖..."
  apt-get update
  apt-get install -y curl ca-certificates tar gzip coreutils sed grep gawk iproute2

  echo "获取 SeaweedFS 最新 release 下载地址..."
  api="https://api.github.com/repos/seaweedfs/seaweedfs/releases/latest"

  release_url="$(
    curl -fsSL "$api" \
      | grep -E '"browser_download_url":' \
      | grep -E "${arch_regex}.*\.tar\.gz" \
      | head -n 1 \
      | sed -E 's/.*"([^"]+)".*/\1/'
  )"

  if [ -z "${release_url}" ]; then
    echo "无法自动找到 ${arch_regex} 的 release 包。"
    echo "可手动下载 weed 二进制后放到: ${INSTALL_DIR}/weed"
    exit 1
  fi

  tmpdir="$(mktemp -d)"

  echo "下载: ${release_url}"
  curl -fL "$release_url" -o "${tmpdir}/seaweedfs.tar.gz"

  tar -xzf "${tmpdir}/seaweedfs.tar.gz" -C "$tmpdir"

  if [ ! -f "${tmpdir}/weed" ]; then
    echo "压缩包中未找到 weed 二进制。"
    exit 1
  fi

  install -m 0755 "${tmpdir}/weed" "${INSTALL_DIR}/weed"
  rm -rf "$tmpdir"

  echo "已安装: $(${INSTALL_DIR}/weed version || true)"
}

create_user_and_dirs() {
  if ! id "$SEAWEED_USER" >/dev/null 2>&1; then
    useradd --system --home "$DATA_DIR" --shell /usr/sbin/nologin "$SEAWEED_USER"
  fi

  mkdir -p "$CONFIG_DIR" \
           "$DATA_DIR/master" \
           "$DATA_DIR/volume" \
           "$DATA_DIR/filer" \
           "$DATA_DIR/webdav-cache" \
           "$LOG_DIR"

  chown -R "$SEAWEED_USER:$SEAWEED_USER" "$DATA_DIR" "$LOG_DIR"
  chmod 0750 "$DATA_DIR" "$LOG_DIR"
  chmod 0755 "$CONFIG_DIR"
}

write_s3_config() {
  local access_key="$1"
  local secret_key="$2"

  cat > "${CONFIG_DIR}/s3.json" <<EOF
{
  "identities": [
    {
      "name": "admin",
      "credentials": [
        {
          "accessKey": "${access_key}",
          "secretKey": "${secret_key}"
        }
      ],
      "actions": [
        "Admin",
        "Read",
        "List",
        "Tagging",
        "Write"
      ]
    }
  ]
}
EOF

  chown root:"$SEAWEED_USER" "${CONFIG_DIR}/s3.json"
  chmod 0640 "${CONFIG_DIR}/s3.json"
}

write_env() {
  cat > "${CONFIG_DIR}/seaweedfs.env" <<EOF
BIND_IP="${BIND_IP}"
MASTER_PORT="${MASTER_PORT}"
VOLUME_PORT="${VOLUME_PORT}"
FILER_PORT="${FILER_PORT}"
S3_PORT="${S3_PORT}"
WEBDAV_PORT="${WEBDAV_PORT}"
VOLUME_MAX="${VOLUME_MAX}"

MASTER_DIR="${DATA_DIR}/master"
VOLUME_DIR="${DATA_DIR}/volume"
FILER_DIR="${DATA_DIR}/filer"
WEBDAV_CACHE_DIR="${DATA_DIR}/webdav-cache"

S3_CONFIG="${CONFIG_DIR}/s3.json"
EOF

  chown root:"$SEAWEED_USER" "${CONFIG_DIR}/seaweedfs.env"
  chmod 0640 "${CONFIG_DIR}/seaweedfs.env"
}

write_systemd_units() {
  cat > /etc/systemd/system/seaweedfs-master.service <<'EOF'
[Unit]
Description=SeaweedFS Master
After=network-online.target
Wants=network-online.target

[Service]
User=seaweedfs
Group=seaweedfs
EnvironmentFile=/etc/seaweedfs/seaweedfs.env
ExecStart=/usr/local/bin/weed master -ip.bind=${BIND_IP} -port=${MASTER_PORT} -mdir=${MASTER_DIR}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  cat > /etc/systemd/system/seaweedfs-volume.service <<'EOF'
[Unit]
Description=SeaweedFS Volume
After=network-online.target seaweedfs-master.service
Wants=network-online.target seaweedfs-master.service

[Service]
User=seaweedfs
Group=seaweedfs
EnvironmentFile=/etc/seaweedfs/seaweedfs.env
ExecStart=/usr/local/bin/weed volume -ip.bind=${BIND_IP} -port=${VOLUME_PORT} -dir=${VOLUME_DIR} -max=${VOLUME_MAX} -mserver=127.0.0.1:${MASTER_PORT}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  cat > /etc/systemd/system/seaweedfs-filer.service <<'EOF'
[Unit]
Description=SeaweedFS Filer HTTP
After=network-online.target seaweedfs-master.service seaweedfs-volume.service
Wants=network-online.target seaweedfs-master.service seaweedfs-volume.service

[Service]
User=seaweedfs
Group=seaweedfs
EnvironmentFile=/etc/seaweedfs/seaweedfs.env
WorkingDirectory=/var/lib/seaweedfs/filer
ExecStart=/usr/local/bin/weed filer -ip.bind=${BIND_IP} -port=${FILER_PORT} -master=127.0.0.1:${MASTER_PORT}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  cat > /etc/systemd/system/seaweedfs-s3.service <<'EOF'
[Unit]
Description=SeaweedFS S3 API
After=network-online.target seaweedfs-filer.service
Wants=network-online.target seaweedfs-filer.service

[Service]
User=seaweedfs
Group=seaweedfs
EnvironmentFile=/etc/seaweedfs/seaweedfs.env
ExecStart=/usr/local/bin/weed s3 -ip.bind=${BIND_IP} -port=${S3_PORT} -filer=127.0.0.1:${FILER_PORT} -config=${S3_CONFIG} -port.iceberg=0
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  cat > /etc/systemd/system/seaweedfs-webdav.service <<'EOF'
[Unit]
Description=SeaweedFS WebDAV
After=network-online.target seaweedfs-filer.service
Wants=network-online.target seaweedfs-filer.service

[Service]
User=seaweedfs
Group=seaweedfs
EnvironmentFile=/etc/seaweedfs/seaweedfs.env
ExecStart=/usr/local/bin/weed webdav -ip.bind=${BIND_IP} -port=${WEBDAV_PORT} -filer=127.0.0.1:${FILER_PORT} -cacheDir=${WEBDAV_CACHE_DIR}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
}

enable_and_start() {
  systemctl enable seaweedfs-master seaweedfs-volume seaweedfs-filer seaweedfs-s3 seaweedfs-webdav

  systemctl restart seaweedfs-master
  sleep 2

  systemctl restart seaweedfs-volume
  sleep 2

  systemctl restart seaweedfs-filer
  sleep 2

  systemctl restart seaweedfs-s3
  systemctl restart seaweedfs-webdav
}

smoke_test() {
  echo
  echo "执行基础连通性检查..."

  set +e

  curl -fsS "http://127.0.0.1:${MASTER_PORT}/dir/status" >/dev/null
  local master_ok=$?

  curl -fsS "http://127.0.0.1:${FILER_PORT}/" >/dev/null
  local filer_ok=$?

  curl -fsS "http://127.0.0.1:${WEBDAV_PORT}/" >/dev/null
  local webdav_ok=$?

  bash -c ":</dev/tcp/127.0.0.1/${S3_PORT}" >/dev/null 2>&1
  local s3_ok=$?

  set -e

  [ "$master_ok" -eq 0 ] && echo "Master OK:  http://127.0.0.1:${MASTER_PORT}" || echo "Master 检查失败，请看 journalctl -u seaweedfs-master"
  [ "$filer_ok" -eq 0 ] && echo "HTTP OK:    http://127.0.0.1:${FILER_PORT}" || echo "Filer HTTP 检查失败，请看 journalctl -u seaweedfs-filer"
  [ "$webdav_ok" -eq 0 ] && echo "WebDAV OK:  http://127.0.0.1:${WEBDAV_PORT}" || echo "WebDAV 检查失败，请看 journalctl -u seaweedfs-webdav"
  [ "$s3_ok" -eq 0 ] && echo "S3 OK:      http://127.0.0.1:${S3_PORT}" || echo "S3 检查失败，请看 journalctl -u seaweedfs-s3"
}

print_summary() {
  echo
  echo "安装完成。"
  echo
  echo "服务状态："
  systemctl --no-pager --full status seaweedfs-master seaweedfs-volume seaweedfs-filer seaweedfs-s3 seaweedfs-webdav || true

  echo
  echo "访问地址："
  echo "  Master:  http://<server-ip>:${MASTER_PORT}"
  echo "  HTTP:    http://<server-ip>:${FILER_PORT}"
  echo "  S3:      http://<server-ip>:${S3_PORT}"
  echo "  WebDAV:  http://<server-ip>:${WEBDAV_PORT}"
  echo
  echo "S3 凭据："
  echo "  AWS_ACCESS_KEY_ID=${S3_ACCESS_KEY}"
  echo "  AWS_SECRET_ACCESS_KEY=${S3_SECRET_KEY}"
  echo
  echo "测试 S3，例如："
  echo "  AWS_ACCESS_KEY_ID='${S3_ACCESS_KEY}' AWS_SECRET_ACCESS_KEY='${S3_SECRET_KEY}' aws --endpoint-url http://127.0.0.1:${S3_PORT} s3 mb s3://test-bucket"
  echo "  AWS_ACCESS_KEY_ID='${S3_ACCESS_KEY}' AWS_SECRET_ACCESS_KEY='${S3_SECRET_KEY}' aws --endpoint-url http://127.0.0.1:${S3_PORT} s3 ls"
  echo
  echo "测试 HTTP/Filer："
  echo "  curl -F file=@/etc/hosts http://127.0.0.1:${FILER_PORT}/test/hosts"
  echo "  curl http://127.0.0.1:${FILER_PORT}/test/hosts"
  echo
  echo "测试 WebDAV，例如使用 cadaver："
  echo "  apt-get install -y cadaver"
  echo "  cadaver http://127.0.0.1:${WEBDAV_PORT}/"
  echo
  echo "查看日志："
  echo "  journalctl -u seaweedfs-master -f"
  echo "  journalctl -u seaweedfs-volume -f"
  echo "  journalctl -u seaweedfs-filer -f"
  echo "  journalctl -u seaweedfs-s3 -f"
  echo "  journalctl -u seaweedfs-webdav -f"
  echo
  echo "安全提醒：当前脚本默认是 HTTP 明文服务。生产环境建议只绑定 127.0.0.1 或内网 IP，并在前面加 Nginx/Caddy 做 HTTPS 和访问控制。"
}

main() {
  need_root

  echo "SeaweedFS 单机安装脚本"
  echo "将安装 Master + Volume + Filer HTTP + S3 + WebDAV"
  echo

  BIND_IP="$(choose_bind_ip)"
  MASTER_PORT="$(ask "Master 端口" "$DEFAULT_MASTER_PORT")"
  VOLUME_PORT="$(ask "Volume HTTP 端口" "$DEFAULT_VOLUME_PORT")"
  FILER_PORT="$(ask "Filer HTTP 端口" "$DEFAULT_FILER_PORT")"
  S3_PORT="$(ask "S3 API 端口" "$DEFAULT_S3_PORT")"
  WEBDAV_PORT="$(ask "WebDAV 端口" "$DEFAULT_WEBDAV_PORT")"
  VOLUME_MAX="$(ask "Volume 最大卷数量 -max" "$DEFAULT_VOLUME_MAX")"

  S3_ACCESS_KEY="$(ask "S3 Access Key" "seaweedfs_admin")"
  S3_SECRET_KEY="$(ask "S3 Secret Key" "$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)")"

  check_port_number "Master" "$MASTER_PORT"
  check_port_number "Volume" "$VOLUME_PORT"
  check_port_number "Filer" "$FILER_PORT"
  check_port_number "S3" "$S3_PORT"
  check_port_number "WebDAV" "$WEBDAV_PORT"

  for p in "$MASTER_PORT" "$VOLUME_PORT" "$FILER_PORT" "$S3_PORT" "$WEBDAV_PORT"; do
    if port_in_use "$p"; then
      echo "错误: 端口 ${p} 已被占用。请重新运行脚本选择其他端口。"
      exit 1
    fi
  done

  echo
  echo "即将安装，配置如下："
  echo "  Bind IP:     ${BIND_IP}"
  echo "  Master:      ${MASTER_PORT}"
  echo "  Volume:      ${VOLUME_PORT}"
  echo "  Filer HTTP:  ${FILER_PORT}"
  echo "  S3:          ${S3_PORT}"
  echo "  WebDAV:      ${WEBDAV_PORT}"
  echo "  Volume Max:  ${VOLUME_MAX}"
  echo "  Data Dir:    ${DATA_DIR}"
  echo

  read -r -p "确认继续？[y/N]: " confirm
  case "$confirm" in
    y|Y|yes|YES)
      ;;
    *)
      echo "已取消。"
      exit 0
      ;;
  esac

  download_weed
  create_user_and_dirs
  write_s3_config "$S3_ACCESS_KEY" "$S3_SECRET_KEY"
  write_env
  write_systemd_units
  enable_and_start
  smoke_test
  print_summary
}

main "$@"
