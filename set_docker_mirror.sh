#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 必须使用 root 用户运行此脚本！${PLAIN}"
   exit 1
fi

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo -e "${RED}错误: 未检测到 Docker，请先安装 Docker。${PLAIN}"
    exit 1
fi

echo -e "-----------------------------------"
echo -e "${GREEN}   Docker 镜像加速器配置脚本   ${PLAIN}"
echo -e "-----------------------------------"

# 1. 获取用户输入
while true; do
    echo -e "${YELLOW}请输入镜像仓库地址 (例如: https://mirror.ccs.tencentyun.com)${PLAIN}"
    read -p "地址: " MIRROR_URL
    
    # 简单校验
    if [[ -z "$MIRROR_URL" ]]; then
        echo -e "${RED}地址不能为空，请重新输入。${PLAIN}"
    elif [[ ! "$MIRROR_URL" =~ ^https?:// ]]; then
        echo -e "${YELLOW}警告: 地址通常以 http:// 或 https:// 开头。${PLAIN}"
        read -p "确认要使用这个地址吗？[y/n]: " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            break
        fi
    else
        break
    fi
done

DAEMON_JSON="/etc/docker/daemon.json"
DIR_PATH="/etc/docker"

# 确保目录存在
if [ ! -d "$DIR_PATH" ]; then
    mkdir -p "$DIR_PATH"
fi

# 2. 备份现有文件
if [ -f "$DAEMON_JSON" ]; then
    echo -e "${YELLOW}检测到现有配置文件，正在备份至 ${DAEMON_JSON}.bak ...${PLAIN}"
    cp "$DAEMON_JSON" "${DAEMON_JSON}.bak"
else
    echo -e "${YELLOW}配置文件不存在，将创建新文件...${PLAIN}"
    echo "{}" > "$DAEMON_JSON"
fi

# 3. 使用 Python 修改 JSON (安全方式，不破坏其他配置)
# 这里嵌入一段 Python 脚本来处理 JSON，因为 shell 处理 JSON 很麻烦且容易出错
echo -e "${YELLOW}正在写入配置...${PLAIN}"

python3 -c "
import json
import sys

file_path = '$DAEMON_JSON'
new_mirror = '$MIRROR_URL'

try:
    with open(file_path, 'r') as f:
        content = f.read()
        if not content.strip():
            data = {}
        else:
            data = json.loads(content)
except Exception as e:
    print(f'解析 JSON 失败，重置为空: {e}')
    data = {}

# 确保 registry-mirrors 是一个列表
if 'registry-mirrors' not in data:
    data['registry-mirrors'] = []

# 逻辑：直接覆盖还是追加？
# 通常配置镜像加速器时，用户希望该加速器生效，因此这里采用【覆盖】策略
# 如果你想改为【追加】，请使用: if new_mirror not in data['registry-mirrors']: data['registry-mirrors'].append(new_mirror)
data['registry-mirrors'] = [new_mirror]

try:
    with open(file_path, 'w') as f:
        json.dump(data, f, indent=4)
    print('配置写入成功。')
except Exception as e:
    print(f'写入文件失败: {e}')
    sys.exit(1)
"

if [ $? -ne 0 ]; then
    echo -e "${RED}配置修改失败！请检查文件权限或 Python 环境。${PLAIN}"
    exit 1
fi

# 4. 重启 Docker
echo -e "${YELLOW}正在重启 Docker 服务...${PLAIN}"
systemctl daemon-reload
systemctl restart docker

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Docker 重启成功！${PLAIN}"
    echo -e "-----------------------------------"
    echo -e "当前生效的镜像源："
    docker info | grep "Registry Mirrors" -A 1
    echo -e "-----------------------------------"
else
    echo -e "${RED}Docker 重启失败，请检查服务日志 (journalctl -xe)。${PLAIN}"
    echo -e "${YELLOW}已备份原文件至 ${DAEMON_JSON}.bak${PLAIN}"
fi
