# ALIASES

alias ls='ls --color=auto'
alias ll='ls -la'
alias l.='ls -d .* --color=auto'
alias cd..='cd ..'
alias ..='cd ..'
alias grep='grep --color=auto'
alias diff='colordiff'
alias mount='mount | column -t'
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

# Safety nets
alias rm='rm -I --preserve-root'
alias chown='chown --preserve-root'
alias chmod='chmod --preserve-root'
alias chgrp='chgrp --preserve-root'
alias mv='mv -i'
alias cp='cp -i'
alias ln='ln -i'

alias c='clear'


# FUNCTIONS

cdl () {
  cd $1
  ls
}
