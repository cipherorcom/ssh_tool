#!/bin/bash
#========================================
# Linux Swap Management Script
#----------------------------------------
# 功能：
#   1) 增加 Swap（支持输入单位 MB/GB）
#   2) 查看 Swap 状态
#   3) 删除 Swap
#----------------------------------------

SWAP_FILE="/swapfile"

if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本"
    exit 1
fi

add_swap() {
    local swap_input="$1"
    local size_mb

    if [ -z "$swap_input" ]; then
        echo -e "\n🔹 请输入要创建的 Swap 大小（支持 MB 或 GB，例如 2048M 或 4G）："
        read -r swap_input
    fi

    if [[ ! "$swap_input" =~ ^[0-9]+[MmGg]?$ ]]; then
        echo "❌ 输入无效，请输入例如 2048M 或 4G"
        return 1
    fi

    if [[ "$swap_input" =~ [Gg]$ ]]; then
        size_mb=$(( ${swap_input%[Gg]} * 1024 ))
    elif [[ "$swap_input" =~ [Mm]$ ]]; then
        size_mb=${swap_input%[Mm]}
    else
        size_mb=$swap_input
    fi

    if [ -f "$SWAP_FILE" ]; then
        echo "⚠️  Swap 文件已存在，请先删除后再创建。"
        return 1
    fi

    echo "🧩 创建 ${size_mb}MB 的 Swap 文件中..."
    fallocate -l "${size_mb}M" "$SWAP_FILE" || {
        echo "❌ 创建失败，请检查磁盘空间。"
        return 1
    }

    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE"
    swapon "$SWAP_FILE"

    if ! grep -q "$SWAP_FILE" /etc/fstab; then
        echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
    fi

    echo "✅ 成功创建并启用了 Swap（${size_mb}MB）"
    free -h
    return 0
}

show_swap() {
    echo -e "\n📊 当前 Swap 状态：\n"
    swapon --show
    echo
    free -h
    echo
}

remove_swap() {
    echo -e "\n⚠️  正在删除 Swap..."

    if swapon --show | grep -q "$SWAP_FILE"; then
        echo "🔧 禁用 Swap..."
        swapoff "$SWAP_FILE"
    fi

    if grep -q "$SWAP_FILE" /etc/fstab; then
        echo "🧹 从 /etc/fstab 移除 Swap 记录..."
        sed -i "\|$SWAP_FILE|d" /etc/fstab
    fi

    if [ -f "$SWAP_FILE" ]; then
        echo "🗑️ 删除 Swap 文件..."
        rm -f "$SWAP_FILE"
    fi

    echo "✅ Swap 删除完成"
}

if [ -n "$AUTO_SWAP_SIZE_MB" ]; then
    if ! [[ "$AUTO_SWAP_SIZE_MB" =~ ^[0-9]+$ ]] || [ "$AUTO_SWAP_SIZE_MB" -lt 128 ]; then
        echo "❌ AUTO_SWAP_SIZE_MB 无效，必须是 >=128 的整数（单位 MB）"
        exit 1
    fi
    add_swap "${AUTO_SWAP_SIZE_MB}M"
    exit $?
fi

while true; do
    echo -e "\n============== Swap 管理菜单 =============="
    echo "1) 增加 Swap"
    echo "2) 查看 Swap 状态"
    echo "3) 删除 Swap"
    echo "4) 退出"
    echo "=========================================="
    read -p "请选择操作 [1-4]: " choice

    case "$choice" in
        1) add_swap ;;
        2) show_swap ;;
        3) remove_swap ;;
        4) echo "👋 退出"; exit 0 ;;
        *) echo "❌ 无效选项，请重新输入。" ;;
    esac
done
