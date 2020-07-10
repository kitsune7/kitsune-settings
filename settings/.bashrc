if [ -f ~/.bash_aliases ]; then
   source ~/.bash_aliases
fi

# PS1 stuff
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
DEFAULT=$(tput setaf 9)
WHITE=$(tput setaf 7)
BRIGHT=$(tput bold)
DIM=$(tput dim)
RESET=$(tput sgr0)
LINE="$(echo $(for i in $(seq 1 $COLUMNS); do printf '-'; done))"

export PS1='\[$CYAN\]\u \[$GREEN\]\W \[$RESET\]$ '

NPM_PACKAGES="${HOME}/.npm-packages"
export PATH="$PATH:$NPM_PACKAGES/bin"
export MANPATH="${MANPATH-$(manpath)}:$NPM_PACKAGES/share/man"

