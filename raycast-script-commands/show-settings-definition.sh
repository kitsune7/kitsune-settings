#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Show Settings Definition
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 🔎
# @raycast.packageName Settings
# @raycast.description Show an alias or function definition
# @raycast.argument1 {"type":"text","placeholder":"Alias or function name","optional":true}

# Documentation:
# @raycast.author tophy
# @raycast.authorURL https://raycast.com/tophy

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec /bin/zsh "${SCRIPT_DIR}/run-zsh-command.zshlib" show "$@"
