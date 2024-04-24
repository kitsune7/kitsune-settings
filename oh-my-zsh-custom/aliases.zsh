settingsDir="$HOME/Git/kitsune-settings"
iCloudDir="$HOME/Library/Mobile Documents/com~apple~CloudDocs"

alias g="cd ~/Git; ls"
alias s="cd $settingsDir; ls"
alias k="s"
alias h="cd $HOME; ls -a"

alias edit="code $settingsDir/oh-my-zsh-custom/aliases.zsh"
alias reload="$settingsDir/sync; exec zsh"
alias save="saveRepoChanges $settingsDir 'Auto-save updates to settings'; reload"
alias sync="$settingsDir/sync"

alias size="du -hs"
alias c="clear"
alias la="ls -a"
alias ..="cd .."
alias cd..="cd .."
alias count='grep "^.*$" -c'

alias ga="git add ."
alias gc="git commit -m"
alias guc="git reset HEAD~"
alias gs="git status"
alias gb="git branch"
alias gcd="git checkout develop; git pull"
alias ac="git add .; git commit -m"
alias list="git stash list"
alias stash="git stash save"
alias pop="git stash pop"
alias drop="git stash save --include-untracked && git stash drop stash@{0}"
alias clearbranch="git branch | grep -v 'master\|main\|development\|develop' | xargs git branch -D"
alias start="npm start"

alias webstorm=/Applications/WebStorm.app/Contents/MacOS/webstorm
alias python="python3"
alias pip="python3 -m pip"
alias vi="vim"

function ll {
  cd "$(llama "$@")"
}

function cdl {
  cd $1
  ls -la
}

function replace-in-file() {
  perl -pi -e "s/$1/$2/g" $3
}

function new-ssh-key () {
  ssh-keygen -t ed25519 -C "chris.kofox@gmail.com"
  eval "$(ssh-agent -s)"
  if [ ! -f "~/.ssh/config" ]
  then
    touch "~/.ssh/config"
  fi
  echo "Host github.com\nAddKeysToAgent yes\nIdentityFile ~/.ssh/id_ed25519"
  ssh-add --apple-use-keychain ~/.ssh/id_ed25519
  
  pbcopy < ~/.ssh/id_ed25519.pub
  echo "Public key copied to clipboard!"
  echo "You can go ahead and add this new key to Github."
  echo "https://github.com/settings/ssh/new"
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
  sudo find / -type f -iname $1 2>/dev/null
}

function localfind () {
  searchPath=${2:-"./"}
  find $searchPath -type f -iname $1
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
  code --line "$lineNumber" "$1"
}

function killport () {
  port=${1:-8080}
  kill -9 $(lsof -t -i tcp:${port})
}

function findPackageJson () {
  find . -name package.json -not \( -path "*/node_modules*" -prune \) -not \( -path "*/dist*" -prune \)
}
