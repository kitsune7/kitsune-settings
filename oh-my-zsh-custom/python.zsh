alias activate="source venv/bin/activate"
alias a="activate"
alias d="deactivate"
alias j="jupyter"
alias py-run="python3 src/main.py"

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
    python3 -m venv venv
    python3 -m pip install --upgrade pip
    python3 -m pip --version
  fi
  source venv/bin/activate
}
