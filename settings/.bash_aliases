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
alias gc='git pull && git commit -m'
alias gp='git push'
alias gs='git status'
alias gr='git reset HEAD~'
alias drop='git stash -u'
alias pop='git stash pop'
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

alias owl="julia ~/Dropbox/School/CS\ 330/interpreter\ 2/owl.jl"


# Connect to my servers

alias ppssh='ssh -i ~/Dropbox/ssh/preview-play chris@178.128.177.77'
alias pprssh='ssh -i ~/Dropbox/ssh/preview-play root@178.128.177.77'


# FUNCTIONS

cdl () {
  cd $1
  ls
}

clone () {
  git clone https://github.com/kitsune7/$1
}
