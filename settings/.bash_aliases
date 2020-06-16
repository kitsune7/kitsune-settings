# Any commands that use the settings directory rely on this variable
settingsDir="$HOME/Git/kitsune-settings"

# ALIASES
alias size="du -hs"
alias l="ls"
alias ll="ls -la"
alias cd..="cd .."
alias ..="cd .."
alias g="cd ~/Git"
alias d="cd ~/Dropbox"
alias s="cd $settingsDir"

alias vi="vim"
alias svi="sudo vim"

alias ping="ping -c 5"
alias fastping="ping -c 100 -s.2"
alias ports="netstat -tulanp"
alias wget="wget -c"

alias ga="git add ."
alias gc="git commit -m"
alias gp="git push origin `git rev-parse --abbrev-ref HEAD`"
alias gs="git status"
alias gr="git reset HEAD~"
alias gcm="git checkout master; git pull"
alias gb="git branch"
alias gbd="git branch -D"
alias drop="git stash save --include-untracked && git stash drop stash@{0}"
alias pop="git stash pop"
alias list="git stash list"
alias cred="git config credential.helper store"
alias undo-last-commit="git reset --soft HEAD~1"

alias dev="npm run dev"
alias start="npm start"

alias mv="mv -i"
alias cp="cp -i"
alias ln="ln -i"

alias c="clear"
alias help="cat $settingsDir/settings/.bash_aliases"
alias edit="vim $settingsDir/settings/.bash_aliases"
alias reload="$settingsDir/install -f && source ~/.bash_aliases"

alias python="python3"
alias pip="python3 -m pip"

alias app="run-db-app-server; run-metrics-api 8081"
alias mconfig="run-metrics-api; run-db-app-server 8081"


# React programming
alias rndocs="chrome 'https://facebook.github.io/react-native/docs/components-and-apis#basic-components'"
alias stack="chrome 'http://stackoverflow.com/'"

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


# FUNCTIONS

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

server () {
  http-server "$1" -a localhost -c-1
}

stash () {
  git stash save --include-untracked "$1"
}

acp () {
  git pull
  git add .
  git commit -m "$1"
  git push origin `git rev-parse --abbrev-ref HEAD` && git push --tags
}

gnb () {
  git checkout -b "$1"
}

gt () {
  git tag -a v$1 -m "$2" && npm run postversion
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
  port=${2:-8080}
  branch=${3:-master}
  git --git-dir $1/.git checkout $3
  git --git-dir $1/.git pull
  yarn --cwd $1
  PORT=$port npm run dev --prefix $1 &
  disown -h $!
}

run-metrics-api () {
  run-server ~/Git/metrics-rest-api $1 $2
}

run-db-app-server () {
  run-server ~/Git/db-app-server $1 $2
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
  reset -c
}

