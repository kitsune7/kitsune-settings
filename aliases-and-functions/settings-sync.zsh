function settings-sync () {
  node "${SETTINGS_DIR}/custom-scripts/settings-sync.mjs" "$@"
  source "${HOME}/.zshrc"
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
