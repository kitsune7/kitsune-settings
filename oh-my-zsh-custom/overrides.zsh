alias mv='mv -i'
alias cp='cp -i'
alias ln="ln -i"
alias python="python3"
alias pip="python3 -m pip"
alias vi="vim"
alias sha256sum='shasum --algorithm 256'

function ide() {
  zed $@
}
