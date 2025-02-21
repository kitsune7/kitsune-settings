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

function ll () {
  cd "$(llama "$@")"
}

function mv-contents () {
  sourceDir=$1
  targetDir=$2
  mv -f $sourceDir/{.,}* $targetDir
}

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

function uncomment-shell-line () {
  beginningOfUncommentedLine=$1
  filePath=$2

  replace-in-file "^#\s*$beginningOfUncommentedLine" "$beginningOfUncommentedLine" $filePath
}

function comment-shell-line () {
  beginningOfLine=$1
  filePath=$2

  replace-in-file "$beginningOfLine" "# $beginningOfLine" $filePath
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

function select_option() {
  local prompt="Please select an option:"
  local options=("$@")
  local PS3="$prompt "
  local selected

  select selected in "${options[@]}"; do
    if [[ -n "$selected" ]]; then
      echo "$selected"
      break
    else
      echo "Invalid option. Please try again."
    fi
  done
}
