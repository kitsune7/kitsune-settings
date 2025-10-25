alias activate="source venv/bin/activate"
alias a="activate"
alias d="deactivate"
alias j="jupyter"
alias py-run="python src/main.py"


function u () {
  moduleName=$(basename "$PWD" | perl -pe 's/-/_/g')
  uv run "${moduleName}" $@
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
  echo '"""
Initialization file for the ${moduleName} module.
"""

__version__ = "0.1.0"
' > "${projectName}/src/${moduleName}/__init__.py"

  echo "import sys


def main():
    print(\"Hello from ${projectName}!\")


if __name__ == \"__main__\":
    sys.exit(main())
" > "src/${moduleName}/cli.py"

  # Set up pyproject.toml
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

  # Set up tests
  mkdir -p "tests"
  echo "\"\"\"Tests for the CLI interface.\"\"\"

  from iot_rag.cli import main


  class TestCLI:
      \"\"\"Test suite for the CLI interface.\"\"\"

      def test_cli_main(capsys):
          \"\"\"Test the main function of the CLI.\"\"\"
          main()
          captured = capsys.readouterr()
          assert \"Hello from ${projectName}!\" in captured.out
" > "tests/test_cli.py"
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
