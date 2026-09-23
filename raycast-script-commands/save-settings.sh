#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Save Settings
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 💾
# @raycast.packageName Settings
# @raycast.description Sync, compile, commit, and push settings
# @raycast.argument1 {"type":"text","placeholder":"Commit message","optional":true}

# Documentation:
# @raycast.author tophy
# @raycast.authorURL https://raycast.com/tophy

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec /bin/zsh "${SCRIPT_DIR}/run-zsh-command.zshlib" save "$@"
