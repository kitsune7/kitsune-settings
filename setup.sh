#!/usr/bin/env zsh

function load () {
  file="$1.zsh"
  if [ -f "$HOME/Git/kitsune-settings/setup/$file" ]
  then
    source "$HOME/Git/kitsune-settings/setup/$file"
  fi
}

# The order of that these are loaded is important.
#load git
#load programs
load install-settings
#load mac-settings
#load local-files
#load github
