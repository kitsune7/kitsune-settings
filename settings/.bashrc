if [ -f ~/.bash_aliases ]; then
   source ~/.bash_aliases
fi

# PS1 stuff
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
DEFAULT="\e[39m"
DARK_GREY="\e[90m"
LIGHT_RED="\e[91m"
LIGHT_GREEN="\e[92m"
LIGHT_YELLOW="\e[93m"
LIGHT_BLUE="\e[94m"
LIGHT_MAGENTA="\e[95m"
LIGHT_CYAN="\e[96m"
WHITE="\e[97m"
DIM="\e[2m"
RESET="\e[0m"

LINE="$(echo $(for i in $(seq 1 $COLUMNS); do printf '-'; done))"

export PS1="$CYAN\u $GREEN\W $RESET$ "
