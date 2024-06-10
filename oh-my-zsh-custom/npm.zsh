alias start="npm start"
alias dev="npm run dev"
alias sb="npm run storybook"
alias update="npm update --save"
alias outdated="npm outdated"

function findPackageJson () {
  find . -name package.json -not \( -path "*/node_modules*" -prune \) -not \( -path "*/dist*" -prune \)
}

function editmodule () {
  lineNumber=${2:-0}
  code --line "$lineNumber" "$1"
}
