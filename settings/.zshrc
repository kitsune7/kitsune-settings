export NVM_DIR="$HOME/.nvm"
# Put default Node on PATH without paying for a full `nvm use` on every shell.
# Full nvm (and bash completion) lazy-load on first `nvm` invocation.
if [ -s "$NVM_DIR/nvm.sh" ]; then
  if [ -r "$NVM_DIR/alias/default" ]; then
    _nvm_default=$(<"$NVM_DIR/alias/default")
    _nvm_default_path="$NVM_DIR/versions/node/v${_nvm_default#v}/bin"
    if [ -d "$_nvm_default_path" ]; then
      export PATH="$_nvm_default_path:$PATH"
    fi
    unset _nvm_default _nvm_default_path
  fi

  nvm() {
    unset -f nvm
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
    nvm "$@"
  }
fi

# Homebrew normally comes from ~/.zprofile (login shells). For non-login
# interactive shells that didn't inherit it, load once when missing.
if [[ -z "$HOMEBREW_PREFIX" && -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Load all .zsh files from .local-scripts directory
if [ -d "$HOME/.local-scripts" ]; then
  for file in "$HOME"/.local-scripts/*.zsh; do
    [ -r "$file" ] && source "$file"
  done
  unset file
fi

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"
unsetopt correct

plugins=(
  catimg
  command-not-found
  git
  git-extras
  gitfast
  history
  pip
  python
  safe-paste
  zsh-autosuggestions
  zsh-interactive-cd
)

source $ZSH/oh-my-zsh.sh

# Make it so you can run `exec zsh` without losing history
setopt inc_append_history

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

NPM_PACKAGES="${HOME}/.npm-packages"
export PATH="$PATH:$NPM_PACKAGES/bin"
export MANPATH="${MANPATH-$(manpath)}:$NPM_PACKAGES/share/man"

# pnpm setup
PNPM_HOME="$HOME/Library/pnpm"

# Go setup
if [ -d "$HOME/go" ]; then
  export GOPATH="${GOPATH:-$HOME/go}"
  export PATH=$PATH:$GOPATH/bin
fi

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/chris.bradshaw/.cache/lm-studio/bin"
# End of LM Studio CLI section

export ENABLE_LSP_TOOL=1
export RTK_TELEMETRY_DISABLED=1

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/chris/.lmstudio/bin"
# End of LM Studio CLI section

if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi
