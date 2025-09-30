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

alias wt="worktree"
function worktree () {
  WORKTREE_NAME=${1:-"test-copy"}
  git worktree add "../$WORKTREE_NAME" "$WORKTREE_NAME"
  cd "../$WORKTREE_NAME"
  read -p "Branch name (leave empty for default branch): " BRANCH_NAME
  if [ -n "$BRANCH_NAME" ]; then
    git checkout -b "$BRANCH_NAME" # Assume the user is simply testing code for a PR
  else
    ide . # Assume the user wants to work on a separate code change
  fi
}

alias cdw="cd-default-worktree"
function cd-default-worktree() {
    # Get the repository name (basename of the main worktree directory)
    local repo_name=$(basename "$(git rev-parse --show-toplevel)")

    # Get current worktree path
    local current_worktree=$(git rev-parse --show-toplevel)
    local current_name=$(basename "$current_worktree")

    # Check if we're already in the default worktree
    if [[ "$current_name" == "$repo_name" ]]; then
        echo "Already in default worktree: $current_worktree"
        return 0
    fi

    # Move up one directory and into the default worktree
    local parent_dir=$(dirname "$current_worktree")
    local target_dir="$parent_dir/$repo_name"

    if [[ -d "$target_dir" ]]; then
        cd "$target_dir" || return 1
        echo "Switched to default worktree: $target_dir"
    else
        echo "Error: Default worktree not found at $target_dir"
        return 1
    fi
}

alias rmw="rm-worktree"
function rm-worktree () {
  WORKTREE_NAME=${1:-"test-copy"}
  cd-default-worktree
  git worktree remove "$WORKTREE_NAME"
  rm -rf "../$WORKTREE_NAME"
}

alias clw="clear-worktrees"
function clear-worktrees() {
  # Get the repository name (basename of the main worktree directory)
  local repo_name=$(basename "$(git rev-parse --show-toplevel)")

  echo "Repository name: $repo_name"
  echo "Checking worktrees..."

  # Parse git worktree list and remove non-matching worktrees
  git worktree list | while read -r path branch rest; do
    local worktree_name=$(basename "$path")

    if [[ "$worktree_name" != "$repo_name" ]]; then
      echo "Removing worktree at: $path"
      rm-worktree "$worktree_name"
    else
      echo "Keeping main worktree: $path"
    fi
  done
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
