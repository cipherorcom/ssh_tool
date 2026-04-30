#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#   System  : CentOS 6/7, Debian 8+, Ubuntu 16+
#   Desc    : BBR一键加速 + TCP深度调优
#   Version : 2.0.3
#=================================================

# ────────────────────────── 颜色定义 ──────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
CYAN='\033[0;96m'
BOLD='\033[1m'
PLAIN='\033[0m'

sh_ver="2.0.2"

# ────────────────────────── 通用工具函数 ──────────────────────────
info()    { echo -e "${BLUE}[INFO]${PLAIN}  $*"; }
ok()      { echo -e "${GREEN}[  OK]${PLAIN}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${PLAIN}  $*"; }
error()   { echo -e "${RED}[FAIL]${PLAIN}  $*"; }
die()     { error "$*"; exit 1; }

hr() {
    echo -e "${BLUE}──────────────────────────────────────────────────────${PLAIN}"
}

banner() {
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║                                                      ║"
    echo "  ║     BBR 一键加速 + TCP 深度调优  v${sh_ver}           ║"
    echo "  ║     适用于 CentOS 6/7 · Debian 8+ · Ubuntu 16+       ║"
    echo "  ║                                                      ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${PLAIN}"
}

# ────────────────────────── Root 权限检查 ──────────────────────────
[[ $EUID -ne 0 ]] && die "请使用 root 用户运行此脚本"

# ────────────────────────── curl 自举安装 ──────────────────────────
if ! command -v curl &>/dev/null; then
    warn "未检测到 curl，正在自动安装..."
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y curl -qq
    elif command -v yum &>/dev/null; then
        yum install -y curl -q
    fi
    command -v curl &>/dev/null || die "curl 安装失败，请手动安装后重试"
    ok "curl 安装完成"
fi

# ────────────────────────── 系统信息检测 ──────────────────────────
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
elif [[ -f /etc/redhat-release ]]; then
    OS="centos"
    VER=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
else
    die "不支持的操作系统"
fi

ARCH=$(uname -m)
[[ $ARCH == "x86_64" ]] && ARCH_NAME="amd64" || ARCH_NAME=$ARCH

# ────────────────────────── 依赖检查与安装 ──────────────────────────
check_dependencies() {
    hr
    info "检查系统依赖..."

    if [[ "$OS" =~ centos|rhel|fedora ]]; then
        PKG_INSTALL="yum install -y -q"
        DEPS="ca-certificates wget curl"
    elif [[ "$OS" =~ debian|ubuntu ]]; then
        PKG_INSTALL="apt-get install -y -qq"
        DEPS="ca-certificates wget curl"
    else
        warn "未知包管理器，跳过依赖检查"
        return 0
    fi

    local need_install=()
    for dep in $DEPS; do
        local installed=0
        if [[ "$dep" == "ca-certificates" ]]; then
            [[ -f /etc/ssl/certs/ca-certificates.crt || -f /etc/pki/tls/certs/ca-bundle.crt ]] && installed=1
        else
            command -v "$dep" &>/dev/null && installed=1
        fi
        [[ $installed -eq 0 ]] && need_install+=("$dep")
    done

    if [[ ${#need_install[@]} -gt 0 ]]; then
        warn "缺少依赖: ${need_install[*]}，正在安装..."
        if [[ "$OS" =~ debian|ubuntu ]]; then
            apt-get update -qq
            $PKG_INSTALL "${need_install[@]}"
            update-ca-certificates 2>/dev/null
        else
            $PKG_INSTALL "${need_install[@]}"
            update-ca-trust force-enable 2>/dev/null
        fi
        [[ $? -eq 0 ]] && ok "依赖安装完成" || warn "部分依赖安装失败，可能影响运行"
    else
        ok "所有依赖已就绪"
    fi
}

# ────────────────────────── 虚拟化检测 ──────────────────────────
check_virt() {
    hr
    info "检测虚拟化类型..."

    if command -v systemd-detect-virt &>/dev/null; then
        virt_type=$(systemd-detect-virt)
    elif command -v virt-what &>/dev/null; then
        virt_type=$(virt-what | head -1)
    elif grep -q "openvz" /proc/vz/version 2>/dev/null || grep -q "openvz" /proc/cpuinfo 2>/dev/null; then
        virt_type="openvz"
    else
        virt_type="unknown"
    fi

    ok "虚拟化类型: ${BOLD}${virt_type}${PLAIN}"

    if [[ "$virt_type" == "openvz" ]]; then
        echo ""
        echo -e "${RED}  ┌─────────────────────────────────────────────────┐${PLAIN}"
        echo -e "${RED}  │  ⚠  警告：检测到 OpenVZ 虚拟化                  │${PLAIN}"
        echo -e "${RED}  │     OpenVZ 容器无法更换内核，无法启用 BBR        │${PLAIN}"
        echo -e "${RED}  │     建议更换为 KVM / Xen 虚拟化的 VPS            │${PLAIN}"
        echo -e "${RED}  └─────────────────────────────────────────────────┘${PLAIN}"
        echo ""
        read -rp "  是否继续（可能失败）? [y/N]: " continue_openvz
        [[ ! "$continue_openvz" =~ ^[Yy]$ ]] && exit 1
    fi
}

# ────────────────────────── /boot 空间检查 ──────────────────────────
check_boot_space() {
    hr
    info "检查 /boot 分区空间..."
    local boot_available
    boot_available=$(df -m /boot 2>/dev/null | tail -1 | awk '{print $4}')

    if [[ -n "$boot_available" ]]; then
        if [[ $boot_available -lt 100 ]]; then
            warn "/boot 空间不足（可用: ${boot_available}MB），建议清理旧内核后再继续"
            read -rp "  是否继续? [y/N]: " continue_boot
            [[ ! "$continue_boot" =~ ^[Yy]$ ]] && exit 1
        else
            ok "/boot 空间充足（可用: ${boot_available}MB）"
        fi
    fi
}

# ────────────────────────── 网络连通性检查 ──────────────────────────
check_network() {
    hr
    info "检查网络连接..."

    local test_hosts=(
        "https://www.google.com"
        "https://cloudflare.com"
        "https://github.com"
        "https://1.1.1.1"
    )

    for host in "${test_hosts[@]}"; do
        if curl -s --connect-timeout 5 --max-time 8 "$host" > /dev/null 2>&1; then
            ok "网络连接正常（${host}）"
            return 0
        fi
    done

    if ping -c 2 -W 3 8.8.8.8 > /dev/null 2>&1; then
        warn "IP 可达但 HTTPS 访问受限，请检查防火墙/DNS"
        return 0
    fi

    error "网络连接失败，请检查网络配置"
    return 1
}

# ────────────────────────── CentOS EOL 源修复（改用官方 Vault）──────────────────────────
fixCentOSRepo() {
    [[ ! "$OS" =~ centos ]] && return
    [[ "$VER" != "6" && "$VER" != "7" && "$VER" != "8" ]] && return

    hr
    warn "CentOS ${VER} 官方源已停服，切换到官方 Vault 源..."
    mkdir -p /etc/yum.repos.d/backup
    mv /etc/yum.repos.d/CentOS-*.repo /etc/yum.repos.d/backup/ 2>/dev/null

    local vault_base="https://vault.centos.org"

    if [[ "$VER" == "7" ]]; then
        cat > /etc/yum.repos.d/CentOS-Vault.repo <<EOF
[base]
name=CentOS-7-Vault-Base
baseurl=${vault_base}/7.9.2009/os/\$basearch/
gpgcheck=0
enabled=1

[updates]
name=CentOS-7-Vault-Updates
baseurl=${vault_base}/7.9.2009/updates/\$basearch/
gpgcheck=0
enabled=1

[extras]
name=CentOS-7-Vault-Extras
baseurl=${vault_base}/7.9.2009/extras/\$basearch/
gpgcheck=0
enabled=1
EOF
    elif [[ "$VER" == "6" ]]; then
        cat > /etc/yum.repos.d/CentOS-Vault.repo <<EOF
[base]
name=CentOS-6-Vault-Base
baseurl=${vault_base}/6.10/os/\$basearch/
gpgcheck=0
enabled=1

[updates]
name=CentOS-6-Vault-Updates
baseurl=${vault_base}/6.10/updates/\$basearch/
gpgcheck=0
enabled=1
EOF
    elif [[ "$VER" == "8" ]]; then
        cat > /etc/yum.repos.d/CentOS-Vault.repo <<EOF
[baseos]
name=CentOS-8-Vault-BaseOS
baseurl=${vault_base}/8.5.2111/BaseOS/\$basearch/os/
gpgcheck=0
enabled=1

[appstream]
name=CentOS-8-Vault-AppStream
baseurl=${vault_base}/8.5.2111/AppStream/\$basearch/os/
gpgcheck=0
enabled=1

[extras]
name=CentOS-8-Vault-Extras
baseurl=${vault_base}/8.5.2111/extras/\$basearch/os/
gpgcheck=0
enabled=1
EOF
    fi

    yum clean all >/dev/null 2>&1
    ok "CentOS ${VER} Vault 源配置完成（使用官方 vault.centos.org）"
}

# ────────────────────────── BBR 状态检测 ──────────────────────────
check_bbr_status() {
    local cc
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    [[ "$cc" == "bbr" ]]
}

# ────────────────────────── 内核版本检测 ──────────────────────────
check_kernel_native_bbr() {
    local kver major minor
    kver=$(uname -r | cut -d- -f1)
    major=$(echo "$kver" | cut -d. -f1)
    minor=$(echo "$kver" | cut -d. -f2)

    if [[ $major -gt 5 ]] || [[ $major -eq 5 && $minor -ge 4 ]]; then
        ok "内核 ${kver} 原生支持 BBR（最佳）"
        return 0
    elif [[ $major -eq 4 && $minor -ge 9 ]] || [[ $major -ge 5 ]]; then
        warn "内核 ${kver} 支持 BBR（建议升级到 5.4+）"
        return 0
    else
        error "内核 ${kver} 不支持 BBR，需要升级内核"
        return 1
    fi
}

# ────────────────────────── sysctl 兼容写入（兼容 LXC/容器）──────────────────────────
# 优先用 sysctl -w 逐条写入，避免 sysctl -p 在容器内遇到不支持的参数时中途退出
sysctl_apply_file() {
    local conf_file="$1"
    local failed=0
    local skipped=0

    while IFS= read -r line; do
        # 跳过注释行和空行
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # 提取 key=value（去除空格）
        local key value
        key=$(echo "$line" | cut -d= -f1 | tr -d ' ')
        value=$(echo "$line" | cut -d= -f2- | tr -d ' ')
        [[ -z "$key" || -z "$value" ]] && continue

        # 尝试写入，捕获错误
        local err
        err=$(sysctl -w "${key}=${value}" 2>&1)
        if [[ $? -ne 0 ]]; then
            # 静默跳过不支持的参数（容器内常见）
            warn "跳过不支持的参数: ${key} (${err})"
            (( skipped++ ))
        fi
    done < "$conf_file"

    return 0
}

# ────────────────────────── 启用 BBR ──────────────────────────
enable_bbr() {
    hr
    if check_bbr_status; then
        ok "BBR 已处于启用状态，无需重复操作"
        return 0
    fi

    check_kernel_native_bbr || { warn "请先升级内核再启用 BBR"; return 1; }

    info "正在写入 BBR 配置..."

    cat > /etc/sysctl.d/99-bbr.conf <<'EOF'
# ── BBR 拥塞控制 ──
net.core.default_qdisc         = fq
net.ipv4.tcp_congestion_control = bbr

# ── 发送 / 接收缓冲区 ──
net.core.rmem_max               = 33554432
net.core.wmem_max               = 33554432
net.ipv4.tcp_rmem               = 4096 87380 33554432
net.ipv4.tcp_wmem               = 4096 65536 33554432

# ── 连接队列 ──
net.core.netdev_max_backlog     = 10000
net.ipv4.tcp_max_syn_backlog    = 8192
net.core.somaxconn              = 8192

# ── TCP 快速选项 ──
net.ipv4.tcp_fastopen           = 3
net.ipv4.tcp_slow_start_after_idle = 0
EOF

    # 使用兼容方式逐条写入（兼容 LXC/Docker 等容器环境）
    sysctl_apply_file /etc/sysctl.d/99-bbr.conf

    # 兜底：强制写入最关键的两条
    sysctl -w net.core.default_qdisc=fq 2>/dev/null || true
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null || true

    if check_bbr_status; then
        echo ""
        echo -e "${GREEN}  ┌─────────────────────────────────────────────────┐${PLAIN}"
        echo -e "${GREEN}  │  ✅  BBR 启用成功！网络加速已生效                │${PLAIN}"
        echo -e "${GREEN}  └─────────────────────────────────────────────────┘${PLAIN}"
        echo ""
    else
        echo ""
        error "BBR 启用失败，当前环境可能不支持修改拥塞控制算法"
        echo ""
        echo -e "${YELLOW}  可能原因：${PLAIN}"
        echo "    1. LXC/OpenVZ 容器且宿主机未授予 net_admin 权限"
        echo "    2. 内核未编译 BBR 模块（运行: modprobe tcp_bbr 验证）"
        echo "    3. 容器平台锁定了该参数"
        echo ""
        echo -e "${YELLOW}  手动验证命令：${PLAIN}"
        echo "    modprobe tcp_bbr && echo ok"
        echo "    echo bbr > /proc/sys/net/ipv4/tcp_congestion_control"
        echo "    sysctl net.ipv4.tcp_congestion_control"
        return 1
    fi
}

# ────────────────────────── TCP 深度调优 ──────────────────────────
tcp_tune() {
    hr
    info "正在应用 TCP 深度调优..."
    echo ""
    echo -e "${YELLOW}  本操作将优化以下参数：${PLAIN}"
    echo "    • TIME_WAIT 连接回收与复用"
    echo "    • TCP 连接保活 (keepalive)"
    echo "    • MTU 探测 & PMTU"
    echo "    • 本地端口范围扩展"
    echo "    • SYN Cookie 防 SYN Flood"
    echo "    • 连接追踪表 (nf_conntrack)"
    echo "    • 文件描述符上限"
    echo ""
    read -rp "  确认写入? [y/N]: " confirm_tune
    [[ ! "$confirm_tune" =~ ^[Yy]$ ]] && { warn "已取消"; return; }

    cat > /etc/sysctl.d/99-tcp-tune.conf <<'EOF'
# ════════════════════════════════════════════
#   TCP 深度调优
# ════════════════════════════════════════════

# ── TIME_WAIT ──────────────────────────────
# 加快 TIME_WAIT 回收（仅在 NAT 环境关闭）
net.ipv4.tcp_tw_reuse           = 1
# TIME_WAIT 最大数量，超出直接丢弃
net.ipv4.tcp_max_tw_buckets     = 20000

# ── 连接保活 ───────────────────────────────
# 空闲 60s 后开始发送 keepalive 探测包
net.ipv4.tcp_keepalive_time     = 60
# 探测间隔 10s
net.ipv4.tcp_keepalive_intvl    = 10
# 最多探测 6 次无响应则断开
net.ipv4.tcp_keepalive_probes   = 6

# ── SYN 握手 ───────────────────────────────
# SYN Cookie 防 SYN Flood
net.ipv4.tcp_syncookies         = 1
# SYN 重试次数
net.ipv4.tcp_syn_retries        = 3
net.ipv4.tcp_synack_retries     = 3
# SYN 等待队列
net.ipv4.tcp_max_syn_backlog    = 8192
net.core.somaxconn              = 8192

# ── 端口范围 ───────────────────────────────
net.ipv4.ip_local_port_range    = 1024 65535

# ── MTU 探测（推荐开启，减少分片）──────────
net.ipv4.tcp_mtu_probing        = 1

# ── 内存与缓冲区 ───────────────────────────
net.core.rmem_default           = 262144
net.core.wmem_default           = 262144
net.core.rmem_max               = 33554432
net.core.wmem_max               = 33554432
net.ipv4.tcp_rmem               = 4096 87380 33554432
net.ipv4.tcp_wmem               = 4096 65536 33554432
net.ipv4.tcp_mem                = 786432 1048576 26777216

# ── 连接队列/网卡接收队列 ──────────────────
net.core.netdev_max_backlog     = 10000

# ── TCP 选项 ───────────────────────────────
# 启用 TCP Fast Open
net.ipv4.tcp_fastopen           = 3
# 关闭空闲后慢启动（提升长肥管道性能）
net.ipv4.tcp_slow_start_after_idle = 0
# 选择性确认（提升丢包恢复效率）
net.ipv4.tcp_sack               = 1
# 时间戳（配合 tw_reuse 使用）
net.ipv4.tcp_timestamps         = 1
# 窗口扩展（大带宽必备）
net.ipv4.tcp_window_scaling     = 1
# 有序 ACK
net.ipv4.tcp_no_metrics_save    = 1

# ── 连接追踪表（如有 nf_conntrack 模块）──────
net.netfilter.nf_conntrack_max              = 1000000
net.netfilter.nf_conntrack_tcp_timeout_established = 7200

# ── 文件描述符 ─────────────────────────────
fs.file-max                     = 1000000
EOF

    # 使用兼容方式逐条写入（自动跳过不支持的参数）
    sysctl_apply_file /etc/sysctl.d/99-tcp-tune.conf

    # 提升系统文件描述符限制（持久化）
    if ! grep -q "# tcp-tune" /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf <<'EOF'

# tcp-tune: 提升文件描述符限制
* soft nofile 1000000
* hard nofile 1000000
root soft nofile 1000000
root hard nofile 1000000
EOF
    fi

    echo ""
    echo -e "${GREEN}  ┌─────────────────────────────────────────────────┐${PLAIN}"
    echo -e "${GREEN}  │  ✅  TCP 调优配置已写入                         │${PLAIN}"
    echo -e "${GREEN}  │     配置文件: /etc/sysctl.d/99-tcp-tune.conf    │${PLAIN}"
    echo -e "${GREEN}  │     无需重启，参数立即生效                       │${PLAIN}"
    echo -e "${GREEN}  └─────────────────────────────────────────────────┘${PLAIN}"
    echo ""
}

# ────────────────────────── Ubuntu/Debian 升级内核 ──────────────────────────
upgrade_kernel_debian() {
    hr
    info "为 $OS $VER 升级内核..."

    local kver major minor
    kver=$(uname -r | cut -d- -f1)
    major=$(echo "$kver" | cut -d. -f1)
    minor=$(echo "$kver" | cut -d. -f2)

    if [[ $major -gt 5 ]] || [[ $major -eq 5 && $minor -ge 4 ]]; then
        ok "当前内核 ${kver} 已满足要求，直接启用 BBR"
        enable_bbr
        return 0
    fi

    info "使用官方镜像源更新软件包列表..."

    # 恢复/使用官方源（海外 VPS 直连官方源更可靠）
    if [[ "$OS" == "ubuntu" ]]; then
        sed -i 's|https\?://mirrors\.[a-z0-9.]*\.[a-z]*/ubuntu|http://archive.ubuntu.com/ubuntu|g' /etc/apt/sources.list 2>/dev/null
    elif [[ "$OS" == "debian" ]]; then
        sed -i 's|https\?://mirrors\.[a-z0-9.]*\.[a-z]*/debian|http://deb.debian.org/debian|g' /etc/apt/sources.list 2>/dev/null
    fi

    apt-get update -qq

    local DPKG_ARCH
    DPKG_ARCH=$(dpkg --print-architecture)

    if [[ "$OS" == "ubuntu" ]]; then
        case "$VER" in
            20.*|22.*|24.*)
                info "安装 linux-generic（Ubuntu ${VER}）..."
                apt-get install -y linux-generic ;;
            18.*)
                info "安装 HWE 内核（Ubuntu 18.04）..."
                apt-get install -y --install-recommends linux-generic-hwe-18.04 ;;
            *)
                info "安装通用内核..."
                apt-get install -y --install-recommends linux-generic-hwe-16.04 2>/dev/null || \
                apt-get install -y linux-generic ;;
        esac
    elif [[ "$OS" == "debian" ]]; then
        info "安装 linux-image-${DPKG_ARCH}..."
        apt-get install -y linux-image-"$DPKG_ARCH"
    fi

    if [[ $? -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}  ┌─────────────────────────────────────────────────┐${PLAIN}"
        echo -e "${GREEN}  │  ✅  内核升级完成，请重启后再启用 BBR           │${PLAIN}"
        echo -e "${GREEN}  └─────────────────────────────────────────────────┘${PLAIN}"
        echo ""
    else
        error "内核升级失败"
        return 1
    fi
}

# ────────────────────────── CentOS 升级内核 ──────────────────────────
upgrade_kernel_centos() {
    hr

    if [[ -n "$VER" && "$VER" -ge 8 ]] 2>/dev/null; then
        echo ""
        echo -e "${RED}  ┌─────────────────────────────────────────────────────┐${PLAIN}"
        echo -e "${RED}  │  ⚠  不支持 CentOS ${VER}+ 内核升级                   │${PLAIN}"
        echo -e "${RED}  │     CentOS 8+ 已停止维护，强升内核易导致系统损坏     │${PLAIN}"
        echo -e "${YELLOW}  │                                                     │${PLAIN}"
        echo -e "${YELLOW}  │  推荐迁移至：                                       │${PLAIN}"
        echo -e "${GREEN}  │    ✔  Ubuntu 20.04 / 22.04 / 24.04                │${PLAIN}"
        echo -e "${GREEN}  │    ✔  Debian 11 / 12                              │${PLAIN}"
        echo -e "${GREEN}  │    ✔  Rocky Linux 8/9 / AlmaLinux 8/9             │${PLAIN}"
        echo -e "${RED}  └─────────────────────────────────────────────────────┘${PLAIN}"
        echo ""
        read -n1 -rp "  按任意键返回..." _; return 1
    fi

    info "为 CentOS $VER 升级内核..."

    local kver major minor
    kver=$(uname -r | cut -d- -f1)
    major=$(echo "$kver" | cut -d. -f1)
    minor=$(echo "$kver" | cut -d. -f2)

    if [[ $major -gt 5 ]] || [[ $major -eq 5 && $minor -ge 4 ]]; then
        ok "内核 ${kver} 已支持 BBR，直接启用"
        enable_bbr
        return 0
    fi

    fixCentOSRepo

    if [[ "$VER" == "7" ]]; then
        grep -q "^timeout=" /etc/yum.conf || echo "timeout=60" >> /etc/yum.conf
        grep -q "^retries=" /etc/yum.conf || echo "retries=3"  >> /etc/yum.conf

        info "导入 ELRepo GPG 密钥（官方）..."
        rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org 2>/dev/null

        info "安装 ELRepo 源（官方）..."
        yum install -y https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm 2>/dev/null || \
            { error "ELRepo 安装失败"; return 1; }

        yum clean all -q

        echo ""
        echo -e "${YELLOW}  ┌─────────────────────────────────────────────────┐${PLAIN}"
        echo -e "${YELLOW}  │  ℹ  正在下载内核（约 150-200MB），请耐心等待   │${PLAIN}"
        echo -e "${YELLOW}  │     如长时间无进度，可按 Ctrl+C 中断重试        │${PLAIN}"
        echo -e "${YELLOW}  └─────────────────────────────────────────────────┘${PLAIN}"
        echo ""

        local attempt=1 success=0
        while [[ $attempt -le 3 ]]; do
            info "尝试安装内核（第 ${attempt}/3 次）..."
            yum --enablerepo=elrepo-kernel install -y kernel-ml kernel-ml-devel && success=1 && break
            error "安装失败，${attempt}/3 次"; yum clean all -q; ((attempt++)); sleep 3
        done

        if [[ $success -eq 1 ]]; then
            grub2-set-default 0
            grub2-mkconfig -o /boot/grub2/grub.cfg
            echo ""
            echo -e "${GREEN}  ✅  内核升级完成，请重启后再启用 BBR${PLAIN}"
            echo ""
        else
            error "内核升级失败（3 次均未成功），请手动操作或更换系统"
            return 1
        fi
    else
        error "CentOS $VER 不支持自动升级内核"
        return 1
    fi
}

# ────────────────────────── 清理旧内核 ──────────────────────────
remove_old_kernels() {
    hr
    info "检测已安装内核..."

    if [[ "$OS" =~ centos|rhel ]]; then
        local installed_kernels kernel_count old_kernels
        installed_kernels=$(rpm -qa | grep '^kernel-[0-9]' | sort -V)
        kernel_count=$(echo "$installed_kernels" | wc -l)

        if [[ $kernel_count -gt 2 ]]; then
            echo ""
            warn "发现 ${kernel_count} 个内核，将保留最新 2 个，以下内核将被删除："
            echo "$installed_kernels" | head -n -2 | sed 's/^/    /'
            echo ""
            read -rp "  确认删除? [y/N]: " confirm_remove
            if [[ "$confirm_remove" =~ ^[Yy]$ ]]; then
                old_kernels=$(echo "$installed_kernels" | head -n -2)
                [[ -n "$old_kernels" ]] && echo "$old_kernels" | xargs yum remove -y -q
                ok "旧内核清理完成"
            else
                warn "已取消"
            fi
        else
            ok "当前内核数量 ${kernel_count} 个，无需清理"
        fi

    elif [[ "$OS" =~ debian|ubuntu ]]; then
        local current_kernel installed_kernels
        current_kernel=$(uname -r)
        installed_kernels=$(dpkg -l | grep 'linux-image-[0-9]' | awk '{print $2}')

        echo ""
        info "当前运行内核: ${BOLD}${current_kernel}${PLAIN}"
        info "已安装内核列表："
        echo "$installed_kernels" | sed 's/^/    /'
        echo ""
        read -rp "  清理非当前内核? [y/N]: " confirm_remove
        if [[ "$confirm_remove" =~ ^[Yy]$ ]]; then
            for kernel in $installed_kernels; do
                if [[ "$kernel" != *"$current_kernel"* ]]; then
                    info "移除: $kernel"
                    apt-get purge -y "$kernel" -qq 2>/dev/null
                fi
            done
            apt-get autoremove -y -qq
            ok "旧内核清理完成"
        else
            warn "已取消"
        fi
    fi
}

# ────────────────────────── 系统状态展示 ──────────────────────────
show_status() {
    hr
    local bbr_status bbr_mod qdisc cc
    check_bbr_status  && bbr_status="${GREEN}✅ 已启用${PLAIN}" || bbr_status="${RED}❌ 未启用${PLAIN}"
    if lsmod | grep -q bbr; then
        bbr_mod="${GREEN}✅ 已加载（模块）${PLAIN}"
    elif grep -q 'CONFIG_TCP_CONG_BBR=y' /boot/config-$(uname -r) 2>/dev/null \
      || zcat /proc/config.gz 2>/dev/null | grep -q 'CONFIG_TCP_CONG_BBR=y'; then
        bbr_mod="${GREEN}✅ 已内置（built-in）${PLAIN}"
    elif check_bbr_status; then
        bbr_mod="${GREEN}✅ 运行中（内置）${PLAIN}"
    else
        bbr_mod="${RED}❌ 未加载${PLAIN}"
    fi
    qdisc=$(sysctl -n net.core.default_qdisc        2>/dev/null || echo "未设置")
    cc=$(sysctl -n net.ipv4.tcp_congestion_control  2>/dev/null || echo "未设置")

    printf "  ${CYAN}%-18s${PLAIN} %s\n"    "操作系统:"   "$OS $VER"
    printf "  ${CYAN}%-18s${PLAIN} %s\n"    "系统架构:"   "$ARCH"
    printf "  ${CYAN}%-18s${PLAIN} %s\n"    "内核版本:"   "$(uname -r)"
    printf "  ${CYAN}%-18s${PLAIN}${bbr_status}\n" "BBR 状态:"
    printf "  ${CYAN}%-18s${PLAIN}${bbr_mod}\n"    "BBR 模块:"
    printf "  ${CYAN}%-18s${PLAIN} %s\n"    "队列算法:"   "$qdisc"
    printf "  ${CYAN}%-18s${PLAIN} %s\n"    "拥塞控制:"   "$cc"

    # TCP 调优状态
    if [[ -f /etc/sysctl.d/99-tcp-tune.conf ]]; then
        printf "  ${CYAN}%-18s${PLAIN} ${GREEN}✅ 已应用${PLAIN}\n" "TCP 调优:"
    else
        printf "  ${CYAN}%-18s${PLAIN} ${YELLOW}⬜ 未应用${PLAIN}\n" "TCP 调优:"
    fi
    hr
}

# ────────────────────────── 主菜单 ──────────────────────────
show_menu() {
    clear
    banner
    show_status

    echo -e "  ${BOLD}请选择操作：${PLAIN}"
    echo ""
    echo -e "  ${GREEN}1.${PLAIN}  安装 / 启用 BBR              ${YELLOW}← 推荐先选此项${PLAIN}"
    echo -e "  ${GREEN}2.${PLAIN}  TCP 深度调优                  ${YELLOW}← 进一步优化网络性能${PLAIN}"
    echo -e "  ${GREEN}3.${PLAIN}  升级内核（Ubuntu / Debian）"
    echo -e "  ${GREEN}4.${PLAIN}  升级内核（CentOS 7）"
    echo -e "  ${GREEN}5.${PLAIN}  清理旧内核                    ${YELLOW}← 释放 /boot 空间${PLAIN}"
    echo -e "  ${GREEN}6.${PLAIN}  查看当前系统状态"
    echo ""
    echo -e "  ${GREEN}0.${PLAIN}  退出"
    echo ""
    hr
    read -rp "  请输入选项 [0-6]: " choice
    echo ""

    case $choice in
        1)
            if check_kernel_native_bbr 2>/dev/null; then
                enable_bbr
            else
                warn "当前内核不支持 BBR，请先选 3 或 4 升级内核"
            fi
            ;;
        2)
            tcp_tune
            ;;
        3)
            if [[ "$OS" =~ debian|ubuntu ]]; then
                check_boot_space
                upgrade_kernel_debian
                read -rp "  是否现在重启? [y/N]: " reboot_now
                [[ "$reboot_now" =~ ^[Yy]$ ]] && reboot
            else
                error "此选项仅适用于 Ubuntu / Debian"
            fi
            ;;
        4)
            if [[ "$OS" =~ centos|rhel ]]; then
                check_boot_space
                upgrade_kernel_centos
                read -rp "  是否现在重启? [y/N]: " reboot_now
                [[ "$reboot_now" =~ ^[Yy]$ ]] && reboot
            else
                error "此选项仅适用于 CentOS / RHEL"
            fi
            ;;
        5)
            remove_old_kernels
            ;;
        6)
            show_status
            ;;
        0)
            echo -e "${GREEN}  感谢使用 BBR 脚本，再见！${PLAIN}"
            echo ""
            exit 0
            ;;
        *)
            error "无效选项，请输入 0-6"
            ;;
    esac

    echo ""
    read -n1 -rp "  按任意键继续..." _
    echo ""
    show_menu
}

# ════════════════════════════════════════════
#   入口：预检查 → 智能判断 → 主菜单
# ════════════════════════════════════════════
clear
banner

echo -e "${BLUE}  ◆ 执行环境预检查...${PLAIN}"
echo ""

check_dependencies
check_network
check_virt
fixCentOSRepo

echo ""
ok "预检查完成！"
echo ""
sleep 1

# 智能判断：BBR 已启用且内核达标时，直接展示状态
if check_bbr_status && check_kernel_native_bbr >/dev/null 2>&1; then
    show_status
    echo -e "${GREEN}  ✅  系统状态良好，BBR 已启用，可选择进一步 TCP 调优（选项 2）${PLAIN}"
    echo ""
fi

show_menu
