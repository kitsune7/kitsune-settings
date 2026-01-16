# kitsune-settings

A collection of settings I like to have in my home directory

## Installation

Run the setup script below to get everything set up on a new computer.

```bash
/bin/zsh -c "$(curl -fsSL https://raw.githubusercontent.com/kitsune7/kitsune-settings/main/setup.sh)"
```

## Sync settings

Use the `settings-sync` function to sync entries defined in `settings-sync.yaml`.

```text
settings-sync list
settings-sync sync <name>|--all
settings-sync push <name>|--all
settings-sync pull <name>|--all

Examples:
settings-sync list
settings-sync sync home-settings
settings-sync push --all
settings-sync pull iterm2
```
