alias mv='mv -i'
alias cp='cp -i'
alias ln="ln -i"
alias python="python3"
alias pip="python3 -m pip"
alias vi="vim"
alias sha256sum='shasum --algorithm 256'

# Use Cursor instead of VSCode by default
function code () {
  if command -v cursor >/dev/null 2>&1; then
    cursor "$@"
  else
    /usr/local/bin/code "$@"
  fi
}
