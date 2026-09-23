#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Show Local
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 📜
# @raycast.packageName Settings
# @raycast.description Show local automation definitions

# Documentation:
# @raycast.author tophy
# @raycast.authorURL https://raycast.com/tophy

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec /bin/zsh "${SCRIPT_DIR}/run-zsh-command.zshlib" show-local "$@"
