if [ -f ~/.bashrc ]; then
   source ~/.bashrc
fi

export BASH_SILENCE_DEPRECATION_WARNING=1

if [ -f ~/.git-completion.bash ]; then
  . ~/.git-completion.bash
fi

