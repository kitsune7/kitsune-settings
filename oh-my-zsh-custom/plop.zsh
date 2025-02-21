function run-plop () {
  PLOP_NAME=${1}
  TARGET_PROJECT=${2}
  install-plop
  PLOPFILES=($SETTINGS_DIR/plopfiles/*)
  PLOPFILE=$(select_option "${PLOPFILES[@]}")
  plop --plopfile $PLOPFILE $TARGET_PROJECT
}

function install-plop () {
  if ! command -v plop 2>&1 >/dev/null
  then
    npm install -g plop
  fi
}
