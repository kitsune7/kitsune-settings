if [ ! -d "$HOME/Git" ]
then
  mkdir -p "$HOME/Git"
fi

SETTINGS_DIR="$HOME/Git/kitsune-settings"
if [ ! -d "$SETTINGS_DIR" ]
then
  git clone https://github.com/kitsune7/kitsune-settings.git "$SETTINGS_DIR"
fi

echo "Pulling settings..."
run-script settings-sync pull --all
source "${HOME}/.zshrc"
echo