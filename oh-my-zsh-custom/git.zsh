alias ga="git add ."
alias gc="git commit -m"
alias gpull="git pull"
alias gpush="git push"
alias guc="git reset HEAD~"
alias gs="git status"
alias gb="git branch"
alias gcm="checkoutMainBranch; git pull"
alias gcmc="gcm; clearbranch"
alias ac="git add .; git commit -m"
alias list="git stash list"
alias stash="git stash save --include-untracked"
alias pop="git stash pop"
alias drop="git stash save --include-untracked && git stash drop stash@{0}"
alias clearbranch="git branch | grep -v 'master\|main\|development\|develop' | xargs git branch -D"
alias cred="git config credential.helper store"

function reclone () {
  if test -d "./.git"
  then
    REPO_NAME=$(pwd)
    REPO_URL=$(git remote get-url origin)
    cd ..
    rm -rf "$REPO_NAME"
    git clone "$REPO_URL"
    cd "$REPO_NAME"
    git status
  else
    echo "\`reclone\` must be run from within a git repository."
  fi
}

function clone () {
  if test -d "${HOME}/Git"; then
    cd "${HOME}/Git"
  else
    mkdir "${HOME}/Git" && cd "${HOME}/Git"
  fi

  git clone "$1" && cd "$(basename "$1" .git)"
  ide .
}

function get-default-branch () {
  git remote show origin | grep 'HEAD branch' | cut -d' ' -f5
}

function pullhead () {
  WORKING_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  PROTECTED_BRANCHES=("master" "main" "develop")

  if echo "${PROTECTED_BRANCHES[@]}" | fgrep --word-regexp "$WORKING_BRANCH"; then
    echo "This command is for feature branches only. You are on a protected branch."
    return
  fi

  if test "$(git status --porcelain)"; then
    git stash save 'Auto-stash before pull'

    checkoutMainBranch
    git branch -D "$WORKING_BRANCH"
    git pull
    git checkout "$WORKING_BRANCH"

    git stash pop
  else
    checkoutMainBranch
    git branch -D "$WORKING_BRANCH"
    git pull
    git checkout "$WORKING_BRANCH"
  fi
}

function checkoutMainBranch () {
  if [ -n "$(git branch --list master)" ]; then
    git checkout master
  elif [ -n "$(git branch --list main)" ]; then
    git checkout main
  else
    git checkout develop
  fi
}

function acp () {
  git add .
  git commit -m "$1"
  git push origin "$(git rev-parse --abbrev-ref HEAD)" && git push --tags
}

function gnb () {
  git checkout -b "$1"
}

function pr () {
  git checkout -b "$1"
  acp "$2"
  gh pr create --web
}

function open-pr () {
  gh pr create --web
}

function killtag () {
  if [[ "$1" == v*.*.* ]]; then
    git push --delete origin "$1"
    git tag -d "$1"
  else
    echo 'Invalid semantic version tag. Did you forget to prefix the version with "v"?'
  fi
}

function save-repo-changes () {
  commitMessage=${2:-"Save updates"}
  _cd=$(pwd)
  cd "$1" || return
  git add .
  git commit -m "$commitMessage"
  git push origin HEAD
  cd "$_cd" || return
}
