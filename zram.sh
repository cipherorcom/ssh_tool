#!/bin/bash
# ============================================
# 💾 通用 ZRAM 管理脚本 (支持多发行版)
# 作者: ChatGPT (2025)
# ============================================

set -e

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 权限运行此脚本 (sudo)"
  exit 1
fi

# 检测发行版
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
else
  OS="unknown"
fi

CONFIG_DIR_SYSTEMD="/etc/systemd"
CONFIG_DIR_DEFAULT="/etc/default"
ZRAM_CONF_SYSTEMD="${CONFIG_DIR_SYSTEMD}/zram-generator.conf"
ZRAM_CONF_DEFAULT="${CONFIG_DIR_DEFAULT}/zramswap"

pause() {
  echo
  read -rp "🔹 按 Enter 返回主菜单..." _
}

menu() {
  clear
  echo "==============================="
  echo "   💾 通用 ZRAM 管理菜单"
  echo "==============================="
  echo "1️⃣  启用/配置 ZRAM 压缩 Swap"
  echo "2️⃣  查看当前状态"
  echo "3️⃣  关闭并删除配置"
  echo "4️⃣  退出"
  echo "==============================="
  read -rp "请选择操作 [1-4]: " choice

  case $choice in
    1) enable_zram ;;
    2) show_status ;;
    3) disable_zram ;;
    4) exit 0 ;;
    *) echo "❌ 无效选择"; sleep 1 ;;
  esac
  menu
}

enable_zram() {
  clear
  read -rp "请输入压缩 swap 占用物理内存百分比 (建议 25~50)： " percent
  percent=${percent:-50}

  echo "⚙️ 检查系统支持..."
  USE_GENERATOR=false
  USE_ZRAMSWAP=false

  if systemctl list-unit-files | grep -q systemd-zram-setup@; then
    USE_GENERATOR=true
  elif systemctl list-unit-files | grep -q zramswap.service; then
    USE_ZRAMSWAP=true
  fi

  if [ "$USE_GENERATOR" = false ] && [ "$USE_ZRAMSWAP" = false ]; then
    echo "⚙️ 尝试安装必要组件..."
    if [[ "$OS" =~ (debian|ubuntu) ]]; then
      apt update -y
      apt install -y zram-tools || echo "ℹ️ 未找到 zram-generator，使用 zram-tools"
    elif [[ "$OS" =~ (centos|rocky|alma|fedora) ]]; then
      dnf install -y zram-generator || echo "ℹ️ 未找到 zram-generator"
    fi
    if systemctl list-unit-files | grep -q systemd-zram-setup@; then
      USE_GENERATOR=true
    elif systemctl list-unit-files | grep -q zramswap.service; then
      USE_ZRAMSWAP=true
    fi
  fi

  mkdir -p "$CONFIG_DIR_SYSTEMD"
  mkdir -p "$CONFIG_DIR_DEFAULT"

  if [ "$USE_GENERATOR" = true ]; then
    echo "⚙️ 使用 zram-generator 启动..."
    cat > "$ZRAM_CONF_SYSTEMD" <<EOF
[zram0]
zram-size = ram/${percent}%
compression-algorithm = zstd
swap-priority = 100
EOF
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl restart systemd-zram-setup@zram0.service || echo "⚠️ 启动失败，请确认 systemd-zram-setup@ 服务存在"
    systemctl enable systemd-zram-setup@zram0.service
  elif [ "$USE_ZRAMSWAP" = true ]; then
    echo "⚙️ 使用 zramswap.service 启动..."
    cat > "$ZRAM_CONF_DEFAULT" <<EOF
ALGO=zstd
PERCENT=${percent}
PRIORITY=100
EOF
    systemctl daemon-reload
    systemctl enable zramswap.service
    systemctl restart zramswap.service
  else
    echo "❌ 无可用 ZRAM 机制，请手动安装 zram-generator 或 zram-tools"
    pause
    return
  fi

  echo "✅ 已启用 ZRAM 压缩交换区"
  echo
  show_status
  pause
}

show_status() {
  clear
  echo "=== 当前 Swap 状态 ==="
  swapon --show || echo "暂无 swap 启用"
  echo
  echo "=== ZRAM 设备信息 ==="
  zramctl || echo "未检测到 ZRAM 设备"
  echo

  if [ -f "$ZRAM_CONF_SYSTEMD" ]; then
    echo "=== zram-generator 配置 ==="
    cat "$ZRAM_CONF_SYSTEMD"
  elif [ -f "$ZRAM_CONF_DEFAULT" ]; then
    echo "=== zramswap 配置 ==="
    cat "$ZRAM_CONF_DEFAULT"
  else
    echo "未找到任何配置文件"
  fi
  pause
}

disable_zram() {
  clear
  echo "⚙️ 正在关闭 ZRAM..."
  swapoff -a || true

  systemctl disable zramswap.service 2>/dev/null || true
  systemctl stop zramswap.service 2>/dev/null || true
  systemctl disable systemd-zram-setup@zram0.service 2>/dev/null || true
  systemctl stop systemd-zram-setup@zram0.service 2>/dev/null || true

  rm -f "$ZRAM_CONF_SYSTEMD"
  rm -f "$ZRAM_CONF_DEFAULT"

  echo "✅ 已关闭并删除配置"
  pause
}

menu
