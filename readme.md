# kitsune-settings

A collection of settings I like to have in my home directory

# Installation

To install the settings to your home directory, just clone the repository and run `install` from the cloned directory.

```bash
git clone https://github.com/kitsune7/kitsune-settings.git
cd ./kitsune-settings
./install
```

The `install` script copies everything in the settings directory to the logged in user's home directory.

Usage: `install [-h | [-fq]]`

The following options are available for `install`:

```
-h  Shows usage string.

-f  Does not prompt you when overwriting existing files.
    This may overwrite previous settings you had in your home directory. Use with discretion.

-q  Hides most output from the program. To keep all output hidden, it is recommended to use this in conjunction with -f.
```