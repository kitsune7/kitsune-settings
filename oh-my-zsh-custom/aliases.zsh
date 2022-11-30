settingsDir="$HOME/Git/kitsune-settings"

alias g="cd ~/Git; ls"
alias s="cd $settingsDir; ls"
alias k="s"
alias h="cd $HOME; ls -a"

alias edit="vim $settingsDir/oh-my-zsh-custom/aliases.zsh"
alias reload="$settingsDir/install; exec zsh"
alias save="saveRepoChanges $settingsDir 'Auto-save updates to settings'; reload"
alias install="$settingsDir/install"

alias size="du -hs"
alias c="clear"
alias la="ls -a"
alias ..="cd .."
alias cd..="cd .."

alias ga="git add ."
alias gc="git commit -m"
alias gs="git status"
alias gb="git branch"
alias list="git stash list"
alias stash="git stash save"
alias pop="git stash pop"
alias drop="git stash save --include-untracked && git stash drop stash@{0}"
alias clearbranch="git branch | grep -v 'master\|main' | xargs git branch -d"
alias start="npm start"

alias webstorm=/Applications/WebStorm.app/Contents/MacOS/webstorm
alias python="python3"
alias pip="python3 -m pip"
alias vi="vim"
alias cat="bat"

function ll {
  cd "$(llama "$@")"
}

function killtag () {
  if [[ "$1" == v*.*.* ]]; then
    git push --delete origin "$1"
    git tag -d "$1"
  else
    echo 'Invalid semantic version tag. Did you forget to prefix the version with "v"?'
  fi
}

function gcm () {
  if [ -n "$(git branch --list master)" ]; then
    git checkout master
  else
    git checkout main
  fi
  gpull
}

function acp () {
  git add .
  git commit -m "$1"
  git push origin "$(git rev-parse --abbrev-ref HEAD)" && git push --tags
}

function gnb () {
  git checkout -b "$1"
}

function pr () {
  git checkout -b "$1"
  acp "$2"
}


function sysfind () {
  sudo find / -iname $1 2>/dev/null
}

function localfind () {
  find / -iname $1 2>/dev/null
}

function saveRepoChanges () {
  commitMessage=${2:-"Save updates"}
  _cd=$(pwd)
  cd "$1" || return
  acp "$commitMessage"
  cd "$_cd" || return
}

function editmodule () {
  lineNumber=${2:-0}
  webstorm --line "$lineNumber" "$1"
}
