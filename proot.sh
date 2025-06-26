#!/bin/bash

# =================================================================
#  PRoot 环境一键安装脚本
#
#  功能:
#  自动下载并配置一个完整的 Linux 发行版 rootfs，
#  并生成一个启动脚本以便通过 PRoot 进入该环境。
# =================================================================

# --- 配置 ---
# 颜色代码
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- 函数定义 ---

# 1. 检查依赖
check_deps() {
    echo "正在检查依赖项..."
    local missing_deps=0
    for cmd in proot curl tar; do
        if ! command -v $cmd >/dev/null; then
            echo -e "${RED}错误: 命令 '$cmd' 未找到。${NC}"
            missing_deps=1
        fi
    done

    if [ $missing_deps -eq 1 ]; then
        echo "请先安装缺失的依赖项。"
        echo "在 Debian/Ubuntu 上: sudo apt install proot curl tar"
        echo "在 Termux (安卓) 上: pkg install proot curl tar"
        echo "在 CentOS/RHEL 上: sudo yum install proot curl tar"
        exit 1
    fi
    echo -e "${GREEN}所有依赖项均已满足。${NC}"
}

# 2. 检测架构
detect_arch() {
    echo "正在检测系统架构..."
    case "$(uname -m)" in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv*) ARCH="armhf" ;;
        i*86) ARCH="i386" ;;
        *)
            echo -e "${RED}错误: 不支持的系统架构: $(uname -m)${NC}"
            exit 1
            ;;
    esac
    echo -e "检测到架构: ${GREEN}${ARCH}${NC}"
}

# 3. 安装发行版
setup_distro() {
    echo "==============================="
    echo " 请选择要安装的 Linux 发行版:"
    echo "   1) Ubuntu 22.04 (Jammy)"
    echo "   2) Debian 12 (Bookworm)"
    echo "   3) Alpine 3.20 (Edge)"
    echo "==============================="
    read -p "请输入您的选择 [1-3]: " choice

    case "$choice" in
        1)
            DISTRO="ubuntu"
            RELEASE="jammy"
            INSTALL_DIR="proot-ubuntu"
            ;;
        2)
            DISTRO="debian"
            RELEASE="bookworm"
            INSTALL_DIR="proot-debian"
            ;;
        3)
            DISTRO="alpine"
            RELEASE="3.20"
            INSTALL_DIR="proot-alpine"
            ;;
        *)
            echo -e "${RED}无效的选择。${NC}"
            exit 1
            ;;
    esac

    if [ -d "$INSTALL_DIR" ]; then
        read -p "目录 '$INSTALL_DIR' 已存在。是否覆盖? (y/n): " overwrite_confirm
        if [[ "${overwrite_confirm,,}" != "y" ]]; then
            echo "操作已取消。"
            exit 0
        fi
        rm -rf "$INSTALL_DIR"
    fi

    echo "正在创建安装目录: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"

    # 从 Linux Containers 官方镜像源下载，稳定可靠
    ROOTFS_URL="https://images.linuxcontainers.org/images/${DISTRO}/${RELEASE}/${ARCH}/default/latest/rootfs.tar.xz"
    
    echo "正在从以下地址下载 rootfs:"
    echo "$ROOTFS_URL"
    # 使用 curl 下载文件，-L 表示跟随重定向
    curl -L -o "${INSTALL_DIR}.tar.xz" "$ROOTFS_URL"
    if [ $? -ne 0 ]; then
        echo -e "${RED}下载失败，请检查网络或URL。${NC}"
        rm -f "${INSTALL_DIR}.tar.xz" # 清理失败的下载
        exit 1
    fi

    echo "正在解压文件系统，请稍候..."
    # 使用 tar 解压，-C 指定解压目录
    tar -xf "${INSTALL_DIR}.tar.xz" -C "$INSTALL_DIR"
    if [ $? -ne 0 ]; then
        echo -e "${RED}解压失败。${NC}"
        exit 1
    fi

    echo "正在清理临时文件..."
    rm "${INSTALL_DIR}.tar.xz"

    echo -e "${GREEN}文件系统已成功安装到 '$INSTALL_DIR' 目录！${NC}"
}

# 4. 创建启动脚本
create_launcher() {
    LAUNCHER_SCRIPT="start-${DISTRO}.sh"
    echo "正在创建启动脚本: ${LAUNCHER_SCRIPT}"

    # 使用 cat 和 here document (EOF) 来创建脚本文件
    cat <<EOF > "$LAUNCHER_SCRIPT"
#!/bin/bash

# 清理可能存在的旧的 proot 进程
proot --kill-all

# PRoot 启动命令
# -0: 以 root (UID 0) 身份运行
# -r: 指定新的根目录
# -b: 绑定必要的系统目录
# -w: 指定进入后的工作目录
proot \\
    -0 \\
    -r "$PWD/$INSTALL_DIR" \\
    -b /dev \\
    -b /proc \\
    -b /sys \\
    -w /root \\
    /usr/bin/env -i HOME=/root TERM="\$TERM" LANG=\$LANG PATH=/bin:/usr/bin:/sbin:/usr/sbin /bin/bash --login
EOF

    # 授予启动脚本可执行权限
    chmod +x "$LAUNCHER_SCRIPT"
    echo -e "${GREEN}启动脚本创建成功！${NC}"
}


# --- 主逻辑 ---
main() {
    check_deps
    detect_arch
    setup_distro
    create_launcher

    echo "================================================================="
    echo -e "${GREEN}恭喜！PRoot 环境已全部设置完毕！${NC}"
    echo
    echo -e "现在，您可以运行以下命令来进入新的 Linux 环境："
    echo -e "  ${YELLOW}./${LAUNCHER_SCRIPT}${NC}"
    echo
    echo -e "进入后，您将拥有一个隔离的 ${DISTRO} 系统环境。"
    echo "================================================================="
}

# 执行主函数
main
