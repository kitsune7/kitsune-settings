alias activate="source venv/bin/activate"
alias a="activate"
alias d="deactivate"
alias j="jupyter"
alias py-run="python src/main.py"

function create-py () {
  projectName=$1
  description=${2:-"A new Python project"}
  moduleName=$(echo "$projectName" | perl -pe 's/-/_/g')

  mkdir -p "${projectName}/src/${moduleName}"
  mkdir -p "${projectName}/tests"
  cd $projectName
  git init
  uv init
  gitignore
  mit-license

  echo '"""
Initialization file for the ${moduleName} module.
"""

__version__ = "0.1.0"
' > "${projectName}/src/${moduleName}/__init__.py"
  replace-in-file '    main()' "    sys.exit(main())" hello.py
  mv hello.py "src/${moduleName}/cli.py"

  replace-in-file 'Add your description here' "$description" pyproject.toml
  echo "
[project.scripts]
${projectName} = \"${moduleName}.cli:main\"

[build-system]
requires = [\"hatchling\"]
build-backend = \"hatchling.build\"

[tool.hatch.build.targets.wheel]
packages = [\"src/${moduleName}\"]
" >> pyproject.toml
  uv add --dev ruff pytest
  echo '
  [tool.ruff]
  line-length = 100
  lint.select = ["E", "F", "I", "N", "W"]
  ' >> pyproject.toml
  replace-in-file '    ' '  ' pyproject.toml

  zed .
}

function venv () {
  if [ ! -d "venv" ]; then
    echo "No virtual environment found. Creating one..."
    python -m venv venv
  fi
  source venv/bin/activate
}
