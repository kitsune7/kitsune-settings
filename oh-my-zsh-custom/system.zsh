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

function cdl () {
  directory=$1
  cd $directory
  ls -la
}

function replace-in-file () {
  searchStr=$1
  replaceStr=$2
  filePath=$3

  perl -pi -e "s/$searchStr/$replaceStr/g" $filePath
}

function sysfind () {
  fileName=$1
  sudo find / -type f -iname $fileName 2>/dev/null
}

function localfind () {
  fileName=$1
  searchPath=${2:-"./"}
  find $searchPath -type f -iname $fileName
}

function killport () {
  port=${1:-8080}
  kill -9 $(lsof -t -i tcp:${port})
}
