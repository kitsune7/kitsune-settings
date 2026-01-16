# Homebrew
if ! command -v brew &> /dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "Installing Oh My Zsh..."
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# Zsh addons
ZSH_CUSTOM_PATH="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
if [ ! -d "${ZSH_CUSTOM_PATH}/themes/powerlevel10k" ]; then 
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM_PATH}/themes/powerlevel10k
fi
if [ ! -d "${ZSH_CUSTOM_PATH}/plugins/zsh-autosuggestions" ]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM_PATH}/plugins/zsh-autosuggestions
fi
if [ ! -d "${ZSH_CUSTOM_PATH}/plugins/zsh-syntax-highlighting" ]; then
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM_PATH}/plugins/zsh-syntax-highlighting
fi

# Homebrew helpers
brew_install () {
  local formula="$1"
  if ! brew list --formula "$formula" >/dev/null 2>&1; then
    brew install "$formula"
  else
    echo "Homebrew formula '${formula}' already installed."
  fi
}

brew_install_cask () {
  local cask="$1"
  local app_name="${2:-${cask}.app}"
  local app_path="/Applications/${app_name}"
  local user_app_path="$HOME/Applications/${app_name}"

  if [ -d "$app_path" ] || [ -d "$user_app_path" ]; then
    echo "Application '${app_name}' already in Applications."
    return 0
  fi

  if ! brew list --cask "$cask" >/dev/null 2>&1; then
    brew install --cask "$cask"
  else
    echo "Homebrew cask '${cask}' already installed."
  fi
}

# Homebrew packages
brew_install nvm
brew_install bat
brew_install jq
brew_install go
brew_install gh
brew_install uv
brew_install difftastic
brew_install_cask raycast Raycast.app
brew_install_cask zed Zed.app
brew_install_cask warp Warp.app
brew_install_cask obsidian Obsidian.app
brew_install_cask hammerspoon Hammerspoon.app
brew_install_cask jordanbaird-ice Ice.app

# Mergiraf
brew_install mergiraf
git config --global merge.mergiraf.name mergiraf
git config --global merge.mergiraf.driver 'mergiraf merge --git %O %A %B -s %S -x %X -y %Y -p %P -l %L'
if ! grep -q '* merge=mergiraf' ~/.config/git/attributes; then
  echo '* merge=mergiraf' >> ~/.config/git/attributes
fi

# Rust
if ! command -v rustup &> /dev/null; then
  echo "Installing Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
fi

echo
