# ALIASES

alias ll='ls -la'
alias cd..='cd ..'
alias ..='cd ..'
alias g='cd ~/Git'
alias d='cd ~/Dropbox'
alias s='cd ~/Git/kitsune-settings'

alias vi=vim
alias svi='sudo vim'

alias ping='ping -c 5'
alias fastping='ping -c 100 -s.2'
alias ports='netstat -tulanp'
alias wget='wget -c'

alias ga='git add .'
alias gc='git commit -m'
alias gp='git push'
alias gs='git status'
alias gr='git reset HEAD~'
alias gb='git branch'
alias drop='git stash save --include-untracked && git stash drop stash@{0}'
alias pop='git stash pop'
alias list='git stash list'
alias cred='git config credential.helper store'

alias mv='mv -i'
alias cp='cp -i'
alias ln='ln -i'

alias c='clear'
alias help='cat ~/Git/kitsune-settings/settings/.bash_aliases'
alias edit='vim ~/Git/kitsune-settings/settings/.bash_aliases'
alias reload='~/Git/kitsune-settings/install -f && source ~/.bash_aliases'

alias python='python3'
alias pip='python3 -m pip'


# React programming

alias rndocs="chrome 'https://facebook.github.io/react-native/docs/components-and-apis#basic-components'"
alias stackoverflow="chrome 'http://stackoverflow.com/'"

newcomponent () {
  # $1: Name of component
  # $2: Component extension
  # $3: Style extension
  mkdir $1
  cd $1
  index=`cat ~/Git/kitsune-settings/snippets/index.$2`
  echo "${index//\$1/$1}" > index.$2
  touch $1.$2
  touch style.$3
  cd ..
}

rnc () {
  newcomponent $1 'js' 'js'
}

tsc () {
  newcomponent $1 'tsx' 'css'
  cd $1
  mv index.tsx index.ts
  cd ../
}


# FUNCTIONS

save () {
  _cd=`pwd`
  cd ~/Git/kitsune-settings/
  git pull
  git add .
  git commit -m "Auto-saving updates to settings"
  git push
  cd $_cd
}

stash () {
  git stash save --include-untracked "$1"
}

acp () {
  git pull
  git add .
  git commit -m "$1"
  git push
}

ss () {
  cd ~/Git/kitsune-settings
  acp $1
  reload
}

cdl () {
  cd $1
  ls
}

chrome () {
  /usr/bin/open -a '/Applications/Google Chrome.app' $1
}

clone () {
  git clone https://github.com/kitsune7/$1
}

install-autocomplete () {
  curl https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash -o ~/.git-completion.bash
}
