# ssh_tool

Some SSH tools for VPS management and testing.

## 一键总控脚本
```
bash <(curl -s https://raw.githubusercontent.com/cipherorcom/ssh_tool/refs/heads/main/ssh_tools.sh)
```

## 脚本分类

### 系统基础
- swap 管理：`swap.sh`
- zram 管理：`zram.sh`
- zsh 一键安装：`zsh.sh`

### SSH / 网络与安全
- 修改 SSH 端口及密码：`change_ssh.sh`
- 出站优先级管理：`network.sh`
- UFW 管理：`ufw.sh`
- Fail2ban 管理：`fail2ban.sh`

### 服务与面板
- Nginx 管理：`nginx.sh`
- frps 管理：`frps.sh`
- frpc 管理：`frpc.sh`
- Sing-box 四合一：`sb.sh`
- Docker 管理：`set_docker_mirror.sh`（配合主菜单安装 Docker）
- 宝塔安装（由主菜单内置）

### 性能优化与测评
- BBR + TCP 调优：`bbr.sh`
- 融合怪测评：`ecs.sh`（远程拉取）
- NodeQuality 测评（远程拉取）

## 常用单脚本运行命令

### swap 管理
```
wget https://raw.githubusercontent.com/cipherorcom/ssh_tool/refs/heads/main/swap.sh && chmod +x swap.sh && ./swap.sh
```

### 修改 SSH 端口和用户密码
```
wget https://raw.githubusercontent.com/cipherorcom/ssh_tool/refs/heads/main/change_ssh.sh && chmod +x change_ssh.sh && ./change_ssh.sh
```

### Nginx 管理
支持 AlmaLinux / CentOS / RHEL 和 Debian / Ubuntu。
```
wget https://raw.githubusercontent.com/cipherorcom/ssh_tool/refs/heads/main/nginx.sh && chmod +x nginx.sh && ./nginx.sh
```

### frps 管理
```
wget https://raw.githubusercontent.com/cipherorcom/ssh_tool/refs/heads/main/frps.sh && chmod +x frps.sh && ./frps.sh
```

### Sing-box 脚本
修改自 [eooce](https://github.com/eooce/Sing-box/blob/main/sing-box.sh)，仅移除 nginx 相关代码。
```
wget https://raw.githubusercontent.com/cipherorcom/ssh_tool/refs/heads/main/sb.sh && chmod +x sb.sh && ./sb.sh
```

### ZRAM 管理
```
wget https://raw.githubusercontent.com/cipherorcom/ssh_tool/refs/heads/main/zram.sh && chmod +x zram.sh && ./zram.sh
```

### 融合怪测评脚本
```
curl -L https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh -o ecs.sh && chmod +x ecs.sh && bash ecs.sh
```

### NodeQuality 测评脚本
```
bash <(curl -sL https://run.NodeQuality.com)
```
