alias activate="source venv/bin/activate"
alias a="activate"
alias d="deactivate"
alias j="jupyter"
alias uvrun="uv run"
alias uvtest="uv run pytest"
alias uvadd="uv add"

function u () {
  projectName=$(basename "$PWD")
  uv run "${projectName}" $@
}

function create-py () {
  projectName=$1
  description=${2:-"A new Python project"}
  moduleName=$(echo "$projectName" | perl -pe 's/-/_/g')

  if [ -z "$projectName" ]; then
    echo "Usage: create-py <project-name> [description]"
    return 1
  fi

  # Create project structure
  mkdir -p "${projectName}/src/${moduleName}"
  cd $projectName
  git init
  uv init
  gitignore
  mit-license

  # Set up module files
  rm hello.py
  rm main.py

  # __init__.py
  echo '"""
Initialization file for the ${moduleName} module.
"""

__version__ = "0.1.0"
' > "src/${moduleName}/__init__.py"

  # cli.py
  echo "import sys


def main():
    print(\"Hello from ${projectName}!\")


if __name__ == \"__main__\":
    sys.exit(main())
" > "src/${moduleName}/cli.py"

  replace-in-file 'Add your description here' "$description" pyproject.toml
  # pyproject.toml
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
  echo '[tool.ruff]
line-length = 100
lint.select = ["E", "F", "I", "N", "W"]
' >> pyproject.toml
  replace-in-file '    ' '  ' pyproject.toml

  # Set up README.md
  echo "# ${projectName}

${description}
" > README.md

  mkdir -p "src/tests"
  # test_cli.py
  echo "\"\"\"Tests for the CLI interface.\"\"\"

from ${moduleName}.cli import main


def test_cli_main(capsys):
    \"\"\"Test the main function of the CLI.\"\"\"
    main()
    captured = capsys.readouterr()
    assert \"Hello from ${projectName}!\" in captured.out
" > "src/tests/test_cli.py"
  uv run pytest

  # Open for editing
  ide .
}

function venv () {
  if [ ! -d "venv" ]; then
    echo "No virtual environment found. Creating one..."
    python -m venv venv
  fi
  source venv/bin/activate
}
