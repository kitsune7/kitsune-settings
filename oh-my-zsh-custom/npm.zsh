alias start="npm start"
alias dev="npm run dev"
alias sb="npm run storybook"
alias update="npm update --save"
alias outdated="npm outdated"

function findPackageJson () {
  find . -name package.json -not \( -path "*/node_modules*" -prune \) -not \( -path "*/dist*" -prune \)
}

function editModule () {
  local module=$1
  local projectPath=$(pwd)
  local workspace=""

  if test -n "$2" && { test "$2" == "-w" || test "$2" == "--workspace"; } && test -n "$3"
  then
    workspace=$3
  fi
  
  # Ensure the module is in node_modules
  echo "Clearing existing links by installing node_modules"
  npm i
  if [ ! -d node_modules/$module ]; then
    echo "Module $module not found in node_modules"
    return
  fi

  # Remove the package from ~/Git/module-edits if it already exists
  if [ -d "$HOME/Git/module-edits/$module" ]
  then
    echo -n "This module already exists in ~/Git/module-edits. Would you like to replace it with a fresh copy (y/n)? "
    read REPLY
    echo    # move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
      echo "Removing existing module"
      rm -rf ~/Git/module-edits/$module
    fi
  fi
  
  # Clear the vite cache if it exists
  if [ -d ./node_modules/.vite ]; then
    rm -rf ./node_modules/.vite
  fi

  # Move the module
  if [[ "$module" == *"/"* ]]
  then
    local scope="${module%%/*}"
    mkdir -p "$HOME/Git/module-edits/$scope"
    mv "node_modules/$module" "$HOME/Git/module-edits/$scope"
  else
    mv "node_modules/$module" "$HOME/Git/module-edits"
  fi

  # Link the module
  cd "$HOME/Git/module-edits/$module"
  npm link
  cd $projectPath

  if [ -n "$workspace" ]
  then
    npm link "$module" --workspace "$workspace"
  else
    npm link "$module"
  fi
  
  code $HOME/Git/module-edits/$module
}

function rmModule () {
  local module=$1

  if [ -d "~/Git/module-edits/$module" ]; then
    npm unlink
    rm -rf ~/Git/module-edits/$module
  fi

  npm unlink $module
}

function workspacePath () {
  local workspace=$1
  findPackageJson | while read -r packageJson; do
    local name=$(cat $packageJson | jq -r ".name")
    if [ "$name" == "$workspace" ]; then
      echo $(dirname $packageJson)
      return
    fi
  done
}