<!-- @format -->

# kitsune-settings

A collection of settings I like to have in my home directory

## Installation

Just run the command below in terminal to get everything set up on a new computer.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/kitsune7/kitsune-settings/main/setup"
```

## Sync data

The `sync` script copies everything in the settings directory to the logged in user's home directory.

Usage: `sync [-h | [-fq]]`

The following options are available for `sync`:

```text
-h  Shows usage string.

-f  Does not prompt you when overwriting existing files.
    This may overwrite previous settings you had in your home directory. Use with discretion.

-q  Hides most output from the program. To keep all output hidden, it is recommended to use this in conjunction with -f.
```
