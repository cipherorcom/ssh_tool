#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Zsh + Oh My Zsh + Powerlevel10k + 插件 安装脚本
# -----------------------------------------------------------------------------

# 如果任何命令失败，立即退出脚本
set -e

build_url() {
  local url="$1"
  if [ -n "$GITHUB_PROXY" ]; then
    local proxy_prefix="${GITHUB_PROXY%/}"
    printf "%s/%s" "$proxy_prefix" "$url"
  else
    printf "%s" "$url"
  fi
}

# 目录已存在则跳过，保证脚本可重复运行
clone_if_missing() {
  local url="$1" dest="$2"
  if [ -d "$dest" ]; then
    echo "Already installed, skipping: $dest"
  else
    git clone --depth=1 "$(build_url "$url")" "$dest"
  fi
}

# 1. 安装依赖包
echo "Updating packages and installing dependencies (curl, wget, unzip, vim, zip, git, zsh)..."
apt update
apt install curl wget unzip vim zip git zsh -y

# 2. 非交互式安装 Oh My Zsh
echo "Installing Oh My Zsh..."
# 设置 RUNZSH=no 来防止它自动启动 zsh 并停止当前脚本
# 设置 CHSH=no 来防止它尝试更改默认 shell（这通常需要交互式输入密码）
export RUNZSH=no
export CHSH=no
if [ -d "$HOME/.oh-my-zsh" ]; then
  echo "Oh My Zsh already installed, skipping."
else
  sh -c "$(curl -fsSL "$(build_url "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh")")" "" --unattended
fi

# 3. 安装 Powerlevel10k 主题
echo "Installing Powerlevel10k theme..."
# 定义 ZSH_CUSTOM 目录，默认为 $HOME/.oh-my-zsh/custom
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

clone_if_missing "https://github.com/romkatv/powerlevel10k.git" \
  "$ZSH_CUSTOM_DIR/themes/powerlevel10k"
      
# 4. 在 .zshrc 中设置主题
echo "Setting ZSH_THEME to Powerlevel10k..."
sed -i 's/^ZSH_THEME=".*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc"

# 5. 安装插件 (修正了原脚本的安装路径和激活方式)
echo "Installing zsh-autosuggestions (command auto-suggestion)..."
clone_if_missing "https://github.com/zsh-users/zsh-autosuggestions" \
  "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
      
echo "Installing zsh-syntax-highlighting (command syntax highlighting)..."
clone_if_missing "https://github.com/zsh-users/zsh-syntax-highlighting.git" \
  "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"
      
# 6. 在 .zshrc 中激活插件
echo "Activating plugins in .zshrc..."
# 查找以 'plugins=' 开头的行，然后将该行最后那个 ')' 
# 替换为 ' zsh-autosuggestions zsh-syntax-highlighting)'
if ! grep -q "zsh-autosuggestions" "$HOME/.zshrc"; then
  sed -i '/^plugins=/ s/)/ zsh-autosuggestions zsh-syntax-highlighting)/' "$HOME/.zshrc"
else
  echo "Plugins already activated in .zshrc, skipping."
fi

# 7. 最终提示
echo ""
echo "✅ Installation complete!"
echo "Please complete the following steps manually:"
echo ""
echo "1. Change your default shell to Zsh (this may require your password):"
echo "   chsh -s $(which zsh)"
echo ""
echo "2. Log out and log back in to apply changes."
echo ""
echo "3. When you first start Zsh, run 'p10k configure' to set up your Powerlevel10k prompt."
echo ""
