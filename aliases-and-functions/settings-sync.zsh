function settings-sync () {
  run-script settings-sync "$@"
  reload-shell-functions
}

function reload-shell-functions () {
  # Only safe because every file in the custom directory is pure alias and
  # function definitions. Anything with side effects (PATH, fpath, compinit)
  # belongs in ~/.zshrc, which needs a brand new shell to pick up.
  local file
  for file in "${ZSH:-$HOME/.oh-my-zsh}"/custom/*.zsh(.N); do
    source "$file"
  done
}

function sync-entry () {
  settings-sync sync "$1"
}

function push-entry () {
  settings-sync push "$1"
}

function pull-entry () {
  settings-sync pull "$1"
}

function sync-all () {
  settings-sync sync --all
}

function push-all () {
  settings-sync push --all
}

function pull-all () {
  settings-sync pull --all
}

function list-sync-entries () {
  settings-sync list
}

alias se="sync-entry"
alias pe="push-entry"
alias ple="pull-entry"
alias sa="sync-all"
alias pa="push-all"
alias pla="pull-all"
alias lse="list-sync-entries"
