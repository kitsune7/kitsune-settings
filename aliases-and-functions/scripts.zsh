function _script_relative_path () {
  local script_path="$1"
  local scripts_dir="${SETTINGS_DIR}/custom-scripts"

  print -r -- "${script_path#${scripts_dir}/}"
}

function _script_binary_path () {
  local script_path="$1"
  local scripts_dir="${SETTINGS_DIR}/custom-scripts"
  local relative_path="${script_path#${scripts_dir}/}"
  local binary_name="${relative_path%.*}"

  binary_name="${binary_name//\//__}"

  print -r -- "${scripts_dir}/bin/${binary_name}"
}

function _script_select_match () {
  local query="$1"
  shift

  local -a candidates=("$@")
  local selection
  local index=1
  local candidate

  if (( ${#candidates[@]} == 1 )); then
    print -r -- "${candidates[1]}"
    return 0
  fi

  echo "Multiple scripts matched '${query}':" >&2
  for candidate in "${candidates[@]}"; do
    echo "  ${index}) $(_script_relative_path "${candidate}")" >&2
    (( index++ ))
  done

  if [[ ! -t 0 ]]; then
    echo "Error: Unable to choose a script in a non-interactive shell." >&2
    return 1
  fi

  while true; do
    printf "Select a script [1-%d]: " "${#candidates[@]}" >&2
    read -r selection

    if [[ "${selection}" == <-> ]] && (( selection >= 1 && selection <= ${#candidates[@]} )); then
      print -r -- "${candidates[$selection]}"
      return 0
    fi

    echo "Error: Invalid selection." >&2
  done
}

function _script_resolve_path () {
  local query="$1"
  local scripts_dir="${SETTINGS_DIR}/custom-scripts"
  local query_name="${query:t}"
  local query_stem="${query_name%.*}"
  local normalized_query="${query_stem:l}"
  local script_path
  local relative_path
  local file_name
  local file_stem
  local normalized_file_name
  local normalized_stem
  local normalized_relative
  local -a script_paths
  local -a exact_matches
  local -a prefix_matches
  local -a substring_matches

  if [[ -z "${query}" ]]; then
    echo "Error: Missing script name." >&2
    return 1
  fi

  if [[ ! -d "${scripts_dir}" ]]; then
    echo "Error: Custom scripts directory not found: ${scripts_dir}" >&2
    return 1
  fi

  script_paths=(${scripts_dir}/**/*(.N))
  for script_path in "${script_paths[@]}"; do
    [[ "${script_path}" == "${scripts_dir}/bin/"* ]] && continue

    relative_path="${script_path#${scripts_dir}/}"
    file_name="${relative_path:t}"
    file_stem="${file_name%.*}"
    normalized_file_name="${file_name:l}"
    normalized_stem="${file_stem:l}"
    normalized_relative="${relative_path:l}"

    if [[ "${normalized_stem}" == "${normalized_query}" || "${normalized_file_name}" == "${normalized_query}" || "${normalized_relative}" == "${normalized_query}" ]]; then
      exact_matches+=("${script_path}")
      continue
    fi

    if [[ "${normalized_stem}" == "${normalized_query}"* || "${normalized_file_name}" == "${normalized_query}"* || "${normalized_relative}" == "${normalized_query}"* ]]; then
      prefix_matches+=("${script_path}")
      continue
    fi

    if [[ "${normalized_stem}" == *"${normalized_query}"* || "${normalized_file_name}" == *"${normalized_query}"* || "${normalized_relative}" == *"${normalized_query}"* ]]; then
      substring_matches+=("${script_path}")
    fi
  done

  if (( ${#exact_matches[@]} > 0 )); then
    _script_select_match "${query}" "${exact_matches[@]}"
    return $?
  fi

  if (( ${#prefix_matches[@]} > 0 )); then
    _script_select_match "${query}" "${prefix_matches[@]}"
    return $?
  fi

  if (( ${#substring_matches[@]} > 0 )); then
    _script_select_match "${query}" "${substring_matches[@]}"
    return $?
  fi

  echo "Error: No scripts matched '${query}'." >&2
  return 1
}

function _script_build_go_binary () {
  local script_path="$1"
  local bin_dir="${SETTINGS_DIR}/custom-scripts/bin"
  local binary_path="$(_script_binary_path "${script_path}")"
  local relative_script_path="custom-scripts/$(_script_relative_path "${script_path}")"

  mkdir -p "${bin_dir}" || {
    echo "Error: Failed to create ${bin_dir}" >&2
    return 1
  }

  echo "Compiling $(_script_relative_path "${script_path}")..." >&2
  (
    cd "${SETTINGS_DIR}" &&
    command go build -o "${binary_path}" "./${relative_script_path}"
  ) || {
    echo "Error: Failed to compile $(_script_relative_path "${script_path}")" >&2
    return 1
  }

  print -r -- "${binary_path}"
}

function run-script () {
  if (( $# == 0 )); then
    echo "Usage: run-script <script-name> [args...]" >&2
    return 1
  fi

  local script_name="$1"
  shift

  local script_path="$(_script_resolve_path "${script_name}")" || return 1
  local extension="${script_path:e}"
  local binary_path

  case "${extension}" in
    go)
      binary_path="$(_script_binary_path "${script_path}")"
      if [[ ! -x "${binary_path}" ]]; then
        binary_path="$(_script_build_go_binary "${script_path}")" || return 1
      fi
      "${binary_path}" "$@"
      ;;
    mjs|js)
      command node "${script_path}" "$@"
      ;;
    py)
      "${script_path}" "$@"
      ;;
    sh)
      command bash "${script_path}" "$@"
      ;;
    zsh)
      command zsh "${script_path}" "$@"
      ;;
    *)
      if [[ -x "${script_path}" ]]; then
        "${script_path}" "$@"
      else
        echo "Error: Don't know how to run '$(_script_relative_path "${script_path}")'." >&2
        return 1
      fi
      ;;
  esac
}

function compile-all-scripts () {
  local scripts_dir="${SETTINGS_DIR}/custom-scripts"
  local script_path

  for script_path in ${scripts_dir}/**/*.go(.N); do
    [[ "${script_path}" == "${scripts_dir}/bin/"* ]] && continue
    _script_build_go_binary "${script_path}" || return 1
  done
}

function compile-script () {
  if (( $# != 1 )); then
    echo "Usage: compile-script <script-name>" >&2
    return 1
  fi

  local script_path="$(_script_resolve_path "$1")" || return 1
  if [[ "${script_path:e}" != "go" ]]; then
    echo "Error: '$(_script_relative_path "${script_path}")' is not a Go script." >&2
    return 1
  fi

  local binary_path="$(_script_build_go_binary "${script_path}")" || return 1

  echo "Built ${binary_path}"
}