alias edit="code ${SETTINGS_DIR}"
alias reload="${SETTINGS_DIR}/sync; exec zsh"
alias save="save-repo-changes ${SETTINGS_DIR} 'Auto-save updates to settings'; reload"
alias sync="${SETTINGS_DIR}/sync"

function show () {
  # Shows the custom aliases and functions provided to `oh-my-zsh`
  # Usage: show [OPTIONS] [ALIAS_OR_FUNCTION_NAME]
  # Options:
  #  -d|--directory <DIRECTORY>  The directory to search for aliases and functions
  #  -p|--plain                  Show the alias or function definition without line numbers

  BAT_ARGS=()
  PARAMS=""
  DIRECTORY="${HOME}/.oh-my-zsh/custom"
  while (( "$#" )); do
    case "$1" in
      -p|--plain)
        args+=( '-p' )
        shift
        ;;
      -d|--directory)
        if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
          DIRECTORY="$2"
          shift 2
        else
          echo "Error: Argument for $1 is missing" >&2
          return 1
        fi
        ;;
      *)
        PARAMS="${PARAMS} $1"
        shift
        ;;
    esac
  done

  eval set -- "${PARAMS}"

  if [[ $# -eq 0 ]]
  then
    node "${SETTINGS_DIR}/node-scripts/show.mjs" $DIRECTORY
  else
    node "${SETTINGS_DIR}/node-scripts/show.mjs" $DIRECTORY "$1" | bat -l zsh "${BAT_ARGS[@]}"
  fi
}

function show-local () {
  show -d "${HOME}/.local-scripts" $@
}

function save-local () {
  for file in "$HOME"/.local-scripts/*.zsh; do
      [ -r "$file" ] && source "$file"
  done

  cp -R "${HOME}/.local-scripts" "${ICLOUD_BACKUP_DIR}/local-scripts"
}

function edit-local () {
  code "${HOME}/.local-scripts"
}

function restore-local () {
  cp -R "${ICLOUD_BACKUP_DIR}/local-scripts" "${HOME}/.local-scripts"
}

function setup-icloud-dir () {
  if [ -z "${ICLOUD_DIR}" ]; then
    echo "${ICLOUD_DIR} doesn't exist yet."
    echo "Log into iCloud and then run \`setup-icloud-dir\` again."
    return 1
  fi
  mkdir -p "${ICLOUD_DIR}/Projects"
  mkdir -p "${ICLOUD_DIR}/Areas"
  mkdir -p "${ICLOUD_DIR}/Resources"
  mkdir -p "${ICLOUD_DIR}/Archive"
  mkdir -p "${ICLOUD_BACKUP_DIR}"
}
