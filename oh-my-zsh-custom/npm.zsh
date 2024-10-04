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
  
  # Ensure the module is in node_modules
  npm i
  if [ ! -d node_modules/$module ]; then
    echo "Module $module not found in node_modules"
    return
  fi

  # Remove the package from ~/Git/module-edits if it already exists
  if [ -d ~/Git/module-edits/$module ]; then
    read -p "This module already exists in ~/Git/module-edits. Would you like to replace it with a fresh copy (y/n)? " -n 1 -r
    echo    # move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
      rm -rf ~/Git/module-edits/$module
    fi
  fi
  
  # Clear the vite cache if it exists
  if [ -d ./node_modules/.vite ]; then
    rm -rf ./node_modules/.vite
  fi

  # Move the module, link it, and open it in VS Code
  mv node_modules/$module ~/Git/module-edits
  cd ~/Git/module-edits/$module
  npm link
  cd $projectPath
  npm link $module
  code ~/Git/module-edits/$module
}

function rmModule () {
  local module=$1

  if [ -d ~/Git/module-edits/$module ]; then
    npm unlink
    rm -rf ~/Git/module-edits/$module
  fi

  npm unlink $module
}
