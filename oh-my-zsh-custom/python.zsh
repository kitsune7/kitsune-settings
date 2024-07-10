alias activate="source venv/bin/activate"

function create-py() {
  projectName=$1
  
  mkdir $projectName
  cd $projectName
  python3 -m venv venv
  source venv/bin/activate
  python3 -m pip install --upgrade pip
  python3 -m pip --version
  code .
}
