#!/bin/bash
#========================================
# Linux Swap Management Script
#----------------------------------------
# 功能：
#   1️⃣ 增加 Swap（支持输入单位 MB/GB）
#   2️⃣ 查看 Swap 状态
#   3️⃣ 删除 Swap
#----------------------------------------
# 使用：sudo ./swap_manager.sh
#========================================

SWAP_FILE="/swapfile"

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本"
    exit 1
fi

#----------------------------------------
# 函数定义
#----------------------------------------

add_swap() {
    echo -e "\n🔹 请输入要创建的 Swap 大小（支持 MB 或 GB，例如 2048M 或 4G）："
    read -r SWAP_SIZE_INPUT

    # 判断输入是否合法
    if [[ ! "$SWAP_SIZE_INPUT" =~ ^[0-9]+[MmGg]?$ ]]; then
        echo "❌ 输入无效，请输入例如 2048M 或 4G"
        return
    fi

    # 转换为 MB
    if [[ "$SWAP_SIZE_INPUT" =~ [Gg]$ ]]; then
        SIZE_MB=$(( ${SWAP_SIZE_INPUT%[Gg]} * 1024 ))
    elif [[ "$SWAP_SIZE_INPUT" =~ [Mm]$ ]]; then
        SIZE_MB=${SWAP_SIZE_INPUT%[Mm]}
    else
        SIZE_MB=$SWAP_SIZE_INPUT
    fi

    # 检查是否存在
    if [ -f "$SWAP_FILE" ]; then
        echo "⚠️  Swap 文件已存在，请先删除后再创建。"
        return
    fi

    echo "🧩 创建 ${SIZE_MB}MB 的 Swap 文件中..."
    fallocate -l "${SIZE_MB}M" "$SWAP_FILE" || {
        echo "❌ 创建失败，请检查磁盘空间。"
        return
    }

    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE"
    swapon "$SWAP_FILE"

    # 写入 /etc/fstab
    if ! grep -q "$SWAP_FILE" /etc/fstab; then
        echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
    fi

    echo "✅ 成功创建并启用了 Swap（${SIZE_MB}MB）"
    free -h
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

#----------------------------------------
# 主菜单
#----------------------------------------

while true; do
    echo -e "\n============== Swap 管理菜单 =============="
    echo "1️⃣  增加 Swap"
    echo "2️⃣  查看 Swap 状态"
    echo "3️⃣  删除 Swap"
    echo "4️⃣  退出"
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
#!/bin/bash
#========================================
# Linux Swap Management Script
#----------------------------------------
# 功能：
#   1️⃣ 增加 Swap（支持输入单位 MB/GB）
#   2️⃣ 查看 Swap 状态
#   3️⃣ 删除 Swap
#----------------------------------------
# 使用：sudo ./swap_manager.sh
#========================================

SWAP_FILE="/swapfile"

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本"
    exit 1
fi

#----------------------------------------
# 函数定义
#----------------------------------------

add_swap() {
    echo -e "\n🔹 请输入要创建的 Swap 大小（支持 MB 或 GB，例如 2048M 或 4G）："
    read -r SWAP_SIZE_INPUT

    # 判断输入是否合法
    if [[ ! "$SWAP_SIZE_INPUT" =~ ^[0-9]+[MmGg]?$ ]]; then
        echo "❌ 输入无效，请输入例如 2048M 或 4G"
        return
    fi

    # 转换为 MB
    if [[ "$SWAP_SIZE_INPUT" =~ [Gg]$ ]]; then
        SIZE_MB=$(( ${SWAP_SIZE_INPUT%[Gg]} * 1024 ))
    elif [[ "$SWAP_SIZE_INPUT" =~ [Mm]$ ]]; then
        SIZE_MB=${SWAP_SIZE_INPUT%[Mm]}
    else
        SIZE_MB=$SWAP_SIZE_INPUT
    fi

    # 检查是否存在
    if [ -f "$SWAP_FILE" ]; then
        echo "⚠️  Swap 文件已存在，请先删除后再创建。"
        return
    fi

    echo "🧩 创建 ${SIZE_MB}MB 的 Swap 文件中..."
    fallocate -l "${SIZE_MB}M" "$SWAP_FILE" || {
        echo "❌ 创建失败，请检查磁盘空间。"
        return
    }

    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE"
    swapon "$SWAP_FILE"

    # 写入 /etc/fstab
    if ! grep -q "$SWAP_FILE" /etc/fstab; then
        echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
    fi

    echo "✅ 成功创建并启用了 Swap（${SIZE_MB}MB）"
    free -h
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

#----------------------------------------
# 主菜单
#----------------------------------------

while true; do
    echo -e "\n============== Swap 管理菜单 =============="
    echo "1️⃣  增加 Swap"
    echo "2️⃣  查看 Swap 状态"
    echo "3️⃣  删除 Swap"
    echo "4️⃣  退出"
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
