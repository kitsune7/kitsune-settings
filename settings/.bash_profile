if [ -f ~/.bashrc ]; then
   source ~/.bashrc
fi

export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/tools
export PATH=$PATH:$ANDROID_HOME/tools/bin
export PATH=$PATH:$ANDROID_HOME/platform-tools
export PATH=$PATH:$ANDROID_HOME/emulator
export BASH_SILENCE_DEPRECATION_WARNING=1

if [ -f ~/.git-completion.bash ]; then
  . ~/.git-completion.bash
fi

