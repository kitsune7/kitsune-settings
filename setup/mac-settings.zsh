# Set the default shell
default_shell="zsh"
shell_path="$(which $default_shell)"
current_shell="$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')"
if [ "$current_shell" != "$shell_path" ]
then
  chsh -s "$shell_path"
fi

# Disable the keyboard layout indicator (language indicator)
defaults write kCFPreferencesAnyApplication TSMLanguageIndicatorEnabled 0
echo "Language indicator has been disabled. This change requires a system restart to take effect."

# Add Dvorak keyboard layout
if defaults read com.apple.HIToolbox AppleEnabledInputSources | grep -q "Dvorak"
then
  echo "Dvorak keyboard layout is already added."
else
  echo "Adding Dvorak keyboard layout..."
  defaults write com.apple.HIToolbox AppleInputSourceHistory -array-add '<dict><key>InputSourceKind</key><string>Keyboard Layout</string><key>KeyboardLayout ID</key><integer>16777219</integer><key>KeyboardLayout Name</key><string>Dvorak</string></dict>'

  # Update enabled input sources
  defaults write com.apple.HIToolbox AppleEnabledInputSources -array-add '<dict><key>InputSourceKind</key><string>Keyboard Layout</string><key>KeyboardLayout ID</key><integer>16777219</integer><key>KeyboardLayout Name</key><string>Dvorak</string></dict>'

  # Keep Mac Desktops from re-arranging themselves
  defaults write com.apple.dock "mru-spaces" -bool "false" && killall Dock

  # Restart the system preferences daemon
  killall cfprefsd

  echo "Dvorak keyboard layout has been added."
  echo "You may need to log out and log back in for the changes to take effect."
fi
echo
