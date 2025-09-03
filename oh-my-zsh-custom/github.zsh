function new-ssh-key () {
  ssh-keygen -t ed25519 -C "chris.kofox@gmail.com"
  eval "$(ssh-agent -s)"
  if [ ! -f "~/.ssh/config" ]
  then
    touch "~/.ssh/config"
  fi
  echo "Host github.com\n  AddKeysToAgent yes\n  IdentityFile ~/.ssh/id_ed25519" > ~/.ssh/config
  ssh-add --apple-use-keychain ~/.ssh/id_ed25519

  pbcopy < ~/.ssh/id_ed25519.pub
  echo "Public key copied to clipboard!"
  echo "You can go ahead and add this new key to Github."
  echo "https://github.com/settings/ssh/new"
}

function dependabot-approve () {
  "${SETTINGS_DIR}/custom-scripts/dependabot-approve.py" "$@"
}

alias pn="process-notifications"
function process-notifications () {
  "${SETTINGS_DIR}/custom-scripts/process-notifications.py" "$@"
}

alias prr="prs-reviewed"
function prs-reviewed () {
  gh search prs --reviewed-by @me --review approved --updated "$(date +%F)" | wc -l
}
