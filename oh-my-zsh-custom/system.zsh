alias size="du -hs"
alias c="clear"
alias la="ls -a"
alias ..="cd .."
alias cd..="cd .."
alias count='grep "^.*$" -c'

alias is-linux='"$OSTYPE" == "linux-gnu"'
alias is-mac='"$OSTYPE" == "darwin"*'
alias run-on-mac='[[ "$OSTYPE" == "darwin"* ]] && "$@"'
alias run-on-linux='[[ "$OSTYPE" == "linux-gnu" ]] && "$@"'

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

function sysfind () {
  sudo find / -type f -iname $1 2>/dev/null
}

function localfind () {
  searchPath=${2:-"./"}
  find $searchPath -type f -iname $1
}

function killport () {
  port=${1:-8080}
  kill -9 $(lsof -t -i tcp:${port})
}
