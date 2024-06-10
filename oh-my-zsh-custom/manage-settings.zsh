alias edit="code ${SETTINGS_DIR}"
alias reload="${SETTINGS_DIR}/sync; exec zsh"
alias save="save-repo-changes ${SETTINGS_DIR} 'Auto-save updates to settings'; reload"
alias sync="${SETTINGS_DIR}/sync"

function save-workrc() {
  source "${HOME}/.workrc"
  cp "${HOME}/.workrc" "${ICLOUD_BACKUP_DIR}/workrc"
}

function show-workrc() {
  cat "${HOME}/.workrc"
}

function edit-workrc() {
  code "${HOME}/.workrc"
}

function restore-workrc() {
  cp "${ICLOUD_BACKUP_DIR}/workrc" "${HOME}/.workrc"
}

function setup-icloud-dir() {
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
