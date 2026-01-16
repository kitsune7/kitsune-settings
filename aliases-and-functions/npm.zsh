alias start="npm start"
alias outdated="npm outdated"

function dev () {
  if [ -f "pnpm-lock.yaml" ]; then
    pnpm dev
  else
    npm run dev
  fi
}

function sb () {
  if [ -f "pnpm-lock.yaml" ]; then
    pnpm storybook
  else
    npm run storybook
  fi
}

function update () {
  if [ -f "pnpm-lock.yaml" ]; then
    pnpm update --save
  else
    npm update --save
  fi
}

function update-pnpm () {
  npm install -g pnpm@latest
}

function update-npm () {
  npm install -g npm@latest
}

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
  if [ ! -d "node_modules/${module}" ]; then
    echo "Module ${module} not found in node_modules"
    return
  fi

  # Remove the package from ~/Git/module-edits if it already exists
  if [ -d "${HOME}/Git/module-edits/${module}" ]
  then
    echo -n "This module already exists in ~/Git/module-edits. Would you like to replace it with a fresh copy (y/n)? "
    read REPLY
    echo    # move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
      echo "Removing existing module"
      rm -rf "${HOME}/Git/module-edits/${module}"
    fi
  fi

  # Clear the vite cache if it exists
  if [ -d ./node_modules/.vite ]; then
    rm -rf ./node_modules/.vite
  fi

  # Move the module
  if [ -n "$workspace" ]
  then
    cd $(workspacePath "$workspace")
  fi
  if [[ "${module}" == *"/"* ]]
  then
    local scope="${module%%/*}"
    mkdir -p "${HOME}/Git/module-edits/$scope"
    mv "node_modules/${module}" "${HOME}/Git/module-edits/${scope}"
  else
    mv "node_modules/${module}" "${HOME}/Git/module-edits"
  fi

  # Link the module
  cd "${HOME}/Git/module-edits/${module}"
  npm link
  cd $projectPath

  if [ -n "${workspace}" ]
  then
    npm link "${module}" --workspace "${workspace}"
  else
    npm link "${module}"
  fi

  ide "${HOME}/Git/module-edits/${module}"
}

function rmModule () {
  local module=$1

  if [ -d "~/Git/module-edits/${module}" ]; then
    npm unlink
    rm -rf ~/Git/module-edits/${module}
  fi

  npm unlink $module
}

# TODO: Make it so this also unlinks the modules globally
function clearModules () {
  rm -rf ~/Git/module-edits/*
  # For each module
  # npm rm -g $module
}

# TODO: Fix this function so it works correctly
function workspacePath () {
  workspace=$1
  findPackageJson | while read -r packageJson; do
    workspaceName=$(cat $packageJson | jq -r ".name")
    echo "found ${workspaceName}"
    if test "${workspaceName}" == "${workspace}"
    then
      dirname $packageJson
      return
    fi
  done
}
