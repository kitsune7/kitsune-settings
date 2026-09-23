#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Restore Local
# @raycast.mode silent

# Optional parameters:
# @raycast.icon ♻️
# @raycast.packageName Settings
# @raycast.description Restore local automations from iCloud backup

# Documentation:
# @raycast.author tophy
# @raycast.authorURL https://raycast.com/tophy

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec /bin/zsh "${SCRIPT_DIR}/run-zsh-command.zshlib" restore-local "$@"
