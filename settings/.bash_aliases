# ALIASES

alias ll='ls -la'
alias cd..='cd ..'
alias ..='cd ..'

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
alias drop='git stash; git stash drop stash@{0}'
alias cred='git config credential.helper store'

alias mv='mv -i'
alias cp='cp -i'
alias ln='ln -i'

alias c='clear'


# FUNCTIONS

cdl () {
  cd $1
  ls
}

clone () {
  git clone https://github.com/kitsune7/$1
}
