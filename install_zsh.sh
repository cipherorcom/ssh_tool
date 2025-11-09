#!/usr/bin/env sh

# -----------------------------------------------------------------------------
# Zsh + Oh My Zsh + Powerlevel10k + 插件 安装脚本
# -----------------------------------------------------------------------------

# 如果任何命令失败，立即退出脚本
set -e

# 1. 安装依赖包
echo "Updating packages and installing dependencies (curl, wget, unzip, vim, zip, git, zsh)..."
apt update
apt install curl wget unzip vim zip git zsh -y

# 2. 非交互式安装 Oh My Zsh
echo "Installing Oh My Zsh..."
export RUNZSH=no
export CHSH=no
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# 3. 安装 Powerlevel10k 主题
echo "Installing Powerlevel10k theme..."
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
  "$ZSH_CUSTOM_DIR/themes/powerlevel10k"
      
# 4. 在 .zshrc 中设置主题
echo "Setting ZSH_THEME to Powerlevel10k..."
sed -i 's/^ZSH_THEME=".*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc"

# 5. 安装插件
echo "Installing zsh-autosuggestions (command auto-suggestion)..."
git clone https://github.com/zsh-users/zsh-autosuggestions \
  "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
      
echo "Installing zsh-syntax-highlighting (command syntax highlighting)..."
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
  "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"
      
# 6. 在 .zshrc 中激活插件 (*** 已修正 ***)
echo "Activating plugins in .zshrc..."
sed -i '/^plugins=/ s/)/ zsh-autosuggestions zsh-syntax-highlighting)/' "$HOME/.zshrc"


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
