function parse() {
  # Usage in other functions:
  # message=$(parse --message "$@")
  # data=$(parse --data "$@" || parse -d "$@")
  # name=$(parse --name "$@" || parse -n "$@" || echo "Default data")
  # help=$(parse --flag --help "$@" || parse --flag -h "$@")
  #
  # Positional parameters are still accessible after parsing
  # e.g., echo "First positional: ${1-}"
  #
  # Example with flags:
  # if [[ $(parse --flag --help "$@") == "true" ]]; then
  #   echo "Help requested"
  # fi

  local param_name=""
  local pattern=""
  local flag_only=false
  
  if [[ $1 == "--flag" ]]; then
    flag_only=true
    shift
  fi
  
  if [[ $1 == --* ]]; then
    param_name="${1:2}"
    pattern="--${param_name}"
  elif [[ $1 == -* ]]; then
    param_name="${1:1}"
    pattern="-${param_name}"
  else
    echo ""
    return 1
  fi
  
  shift

  # If flag_only is true, just check if the flag exists
  if [[ "$flag_only" == true ]]; then
      for arg in "$@"; do
          if [[ "$arg" == "$pattern" ]]; then
              echo "true"
              return 0
          fi
      done
      echo "false"
      return 1
  fi
  
  # Otherwise, look for the parameter with a value
  while (( $# > 0 )); do
    if [[ "$1" == "$pattern" && $# -gt 1 ]]; then
      echo "$2"
      return 0
    elif [[ "$1" == "$pattern="* ]]; then
      echo "${1#*=}"
      return 0
    fi
    shift
  done
  
  # Parameter not found
  echo ""
  return 1
}

function select_option() {
  local help=$(parse --help "$@" || parse -h "$@")

  if [[ "$help" == "true" ]]; then
    echo "Usage: select_option [--help] [--message <message>] <option1> <option2> ..."
    return 0
  fi

  local message=$(parse --message "$@" || parse -m "$@" || echo "Please select an option:")
  local choices=("$@")
  
  npm list -g | grep @inquirer/prompts || npm install -g @inquirer/prompts > /dev/null 2>&1
  selected=$(node "${SETTINGS_DIR}/custom-scripts/select.mjs" "$message" "${choices[@]}" 2>/dev/null)
  echo "You selected: $selected"
}