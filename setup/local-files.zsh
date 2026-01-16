if [ ! -d "$HOME/.local-scripts" ]
then
  mkdir "$HOME/.local-scripts"
  touch "$HOME/.local-scripts/general.zsh"
fi

if [ -z "${ICLOUD_DIR}" ]; then
  echo "${ICLOUD_DIR} doesn\'t exist yet."
  echo "Log into iCloud and then press Enter to continue."
  read -r
fi
mkdir -p "${ICLOUD_DIR}/Projects"
mkdir -p "${ICLOUD_DIR}/Areas"
