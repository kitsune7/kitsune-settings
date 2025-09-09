alias activate="source venv/bin/activate"
alias a="activate"
alias d="deactivate"
alias j="jupyter"
alias py-run="python src/main.py"

function create-py () {
  projectName=$1

  mkdir $projectName
  cd $projectName
  venv

  git init
  echo "# $projectName" >> README.md
  mkdir src
  touch src/main.py

  code .
}

function venv () {
  if [ ! -d "venv" ]; then
    echo "No virtual environment found. Creating one..."
    python -m venv venv
  fi
  source venv/bin/activate
}
