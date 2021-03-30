shopt -s extglob
shopt -s dotglob

# Any commands that use the settings directory rely on this variable
settingsDir="$HOME/Git/kitsune-settings"
platformTools="$HOME/Library/Android/sdk/platform-tools"

# ALIASES
alias size="du -hs"
alias l="ls"
alias ll="ls -la"
alias cd..="cd .."
alias ..="cd .."
alias g="cdl ~/Git"
alias d="cdl ~/Dropbox"
alias s="cdl $settingsDir"
alias k="s"
alias h="cd $HOME"

alias vi="vim"
alias svi="sudo vim"

alias ping="ping -c 5"
alias fastping="ping -c 100 -s.2"
alias wget="wget -c"

alias ga="git add ."
alias gc="git commit -m"
alias gp='git push origin head'
alias gs="git status"
alias gundo="git reset HEAD~"
alias gcm="git checkout master; git pull"
alias gb="git branch"
alias gbd="git branch -D"
alias drop="git stash save --include-untracked && git stash drop stash@{0}"
alias pop="git stash pop"
alias list="git stash list"
alias cred="git config credential.helper store"
alias undo-last-commit="git reset --soft HEAD~1"
alias gitignore="curl https://gist.githubusercontent.com/kitsune7/b9b453f7f48b0ee8adb84cf1e928dd07/raw/e689d9a723d64093f07bc750004fffcbe9b0a785/.gitignore --output .gitignore"
alias clearbranch="git branch | grep -v 'master\|main\|cb-message-campaigns' | xargs git branch -d"

alias dev="npm run dev"
alias start="npm start"
alias webstorm=/Applications/WebStorm.app/Contents/MacOS/webstorm
alias stagingToProd='replaceInFile "s/staging/psql-db/g" .env'
alias prodToStaging='replaceInFile "s/psql-db/staging/g" .env'
alias psqlStaging=$(echo "psql --host=$DB_DEV_HOST --port=$DB_PORT --username=$DB_DEV_USERNAME --password --dbname=$DB_NAME")

alias mv="mv -i"
alias cp="cp -i"
alias ln="ln -i"

alias c="clear"
alias help="cat $settingsDir/settings/.bash_aliases"
alias kfind="help | grep "
alias edit="vim $settingsDir/settings/.bash_aliases"
alias reload="$settingsDir/install -f && source ~/.bash_aliases"
alias latest="git --git-dir $settingsDir/.git pull; reload"

alias python="python3"
alias pip="python3 -m pip"

alias rs="run-server ~/Git/db-app-server && run-server ~/Git/metrics-rest-api && run-server ~/Git/synchronization-microservice"
alias ks="killservers"
alias vs="viewservers"

alias adb="$platformTools/adb"
alias fastboot="$platformTools/fastboot"

# React programming
alias rndocs="chrome 'https://facebook.github.io/react-native/docs/components-and-apis#basic-components'"
alias stack="chrome 'http://stackoverflow.com/'"

jesttest () {
  npx jest --runInBand $1
}

newcomponent () {
  # $1: Name of component
  # $2: Component extension
  # $3: Style extension
  mkdir $1
  cd $1
  index=`cat "$settingsDir/snippets/index.$2"`
  echo "${index//\$1/$1}" > "index.$2"
  touch "$1.$2"
  touch "style.$3"
  cd ..
}

rnc () {
  newcomponent "$1" "js" "js"
}

tsc () {
  newcomponent "$1" "tsx" "css"
  cd "$1"
  mv index.tsx index.ts
  cd ../
}

function tmb () {
  pip install leveldb

  if [ ! -d "$HOME/Git/tampermonkey-scripts" ]; then
    git clone git@github.com:kitsune7/tampermonkey-scripts.git
  fi

  scriptPath="$settingsDir/scripts/BackupTampermonkeyScripts/backup_tampermonkey_scripts.py"
  chromeProfileDirectory="$HOME/Library/Application Support/Google/Chrome/Default"

  extensionId=$(egrep -r --include=manifest.json '"name": "Tampermonkey"' "$chromeProfileDirectory/Extensions" | awk -F'/' '{ print $(NF-2) }')

  enableKSettingScripts
  runOnMac "$scriptPath" "\"$chromeProfileDirectory/Local Extension Settings/$extensionId/\"" "$HOME/Git/tampermonkey-scripts"
}
function tamperMonkeyBackup () { tmb; }

function enableKSettingScripts () {
  chmod -R +x "$settingsDir/scripts"
}

# FUNCTIONS

alias isLinux='"$OSTYPE" == "linux-gnu"'
alias isMac='"$OSTYPE" == "darwin"*'

function runOnLinux () {
  if [[ "$OSTYPE" == "linux-gnu" ]]; then
    $@
  fi
}

function runOnMac () {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    $@
  fi
}

function replaceInFile () {
  runOnMac sed -i '' "$1" "$2"
  runOnLinux sed -i "$1" "$2"
}

function showSnippets () {
  ls "$settingsDir"/snippets/*
}

function loadSnippet () {
  cp "$settingsDir/snippets/$1" .

  argc=$#
  argv=("$@")
  for (( i=1; i<argc; i++ )); do
    replaceInFile "/s/\$$i/${argv[i]}/g" "./$1"
  done
}

function gh () {
  git log --pretty=short -u -L "$1":"$2"
}

# New Repository
function nr () {
  name=${1:-"new-repo"}
  description=${2:-}

  mkdir "$name"
  cd "$name"

  loadSnippet "package.json" "$name" "$description"
  loadSnippet "readme.md" "$name" "$description"
  loadSnippet ".gitignore"

  git init
  acp 'Initial commit'
}

sysfind () {
  sudo find / -iname $1 2>/dev/null
}

localfind () {
  find / -iname $1 2>/dev/null
}

save () {
  _cd=`pwd`
  cd $settingsDir
  git pull
  git add .
  git commit -m "Auto-saving updates to settings"
  git push
  cd $_cd
  reload
}

editmodule () {
  lineNumber=${2:-0}
  webstorm --line "$lineNumber" "$1"
}

server () {
  path=${1:-./dist/}
  http-server "$path" -a localhost -c-1 -p 5000 -P http://localhost:5000?
}

stash () {
  git stash save --include-untracked "$1"
}

acp () {
  git add .
  git commit -m "$1"
  git push origin `git rev-parse --abbrev-ref HEAD` && git push --tags
}

gnb () {
  git checkout -b "$1"
}

pr () {
  gnb "$1"; acp "$2"
}

gt () {
  git tag -a v$1 -m "$2" && npm run postversion
}

version () {
  git add .
  git commit -m "$1"
  echo "Commit message: \"$1\""
  npx standard-version
}

major () {
  version "BREAKING CHANGE: $1"
}
minor () {
  version "feat: $1"
}
patch () {
  version "patch: $1"
}

ss () {
  cd "$settingsDir"
  acp "$1"
  reload
}

cdl () {
  cd "$1"
  ls
}

chrome () {
  /usr/bin/open -a "/Applications/Google Chrome.app" "$1"
}

clone () {
  git clone "https://github.com/kitsune7/$1"
}

install-autocomplete () {
  curl https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash -o ~/.git-completion.bash
}

add-pre-commit () {
  cp "$settingsDir/snippets/pre-commit" ./.git/hooks/pre-commit
  chmod 755 ./.git/hooks/pre-commit
}

run-server () {
  if [ -d "$1/.git" ]; then
    cd $1
    git stash
    git stash drop stash@{0}
    git checkout master
    git pull
    yarn
    npm run dev &
  else
    echo "$1 doesn't have a .git directory."
    killservers
    exit 1
  fi
}

killjobs () {
  kill $(jobs -p)
}

killport () {
  port=${1:-8080}
  kill `lsof -ti:$port`
}

killservers () {
  kill `lsof -ti:8080,8081,8082` > /dev/null 2>&1
  reset
}

viewservers () {
  lsof -ti:8080,8081,8082 | xargs -n1 lsof -Pp | grep 'DIR\|(LISTEN)\|NAME' | perl -ne 'print if ++$k{$_}==1'
}

updatecommon () {
  if [ -z ${1+x} ]; then
    echo "Usage: updatecommon <semantic version number>"
  else
    version=`grep common.git package.json | grep -E -o '[0-9]+\.[0-9]+\.[0-9]+(-[a-z]+\.[0-9]*)?'`
    escapedVersion=`echo "$version" | sed 's/\\./\\\\./g'`

    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "/common.git/s/$escapedVersion/$1/" package.json
    else
      sed -i "/common.git/s/$escapedVersion/$1/" package.json
    fi

    yarn
  fi
}

jsonpost () {
  curl -d "$1" -H 'Content-Type: application/json' -X POST "$2"
}

httpscert () {
  brew install openssl
  openssl genrsa -des3 -passout pass:x -out server.pass.key 2048
  openssl rsa -passin pass:x -in server.pass.key -out private.key
  rm server.pass.key
  openssl req -new -key private.key -out server.csr
  openssl x509 -req -sha256 -days 365 -in server.csr -signkey private.key -out certificate.crt
}

cdr () {
  searchStart=${1:-./src}
  workingDir=`find "$searchStart" -type f -exec stat -lt "%F %T" {} \+ | cut -d' ' -f6- | sort -n | tail -1 | sed -En "s/([0-9-]+ [0-9:]* |\/[a-zA-Z0-9.]+$)//gp"`
  cd "$workingDir"
}

