function kplop () {
  install-plop
  plop --plopfile "$SETTINGS_DIR/plopfile.js" "$@"
}

function install-plop () {
  if ! command -v plop 2>&1 >/dev/null
  then
    npm install -g plop
  fi
}
