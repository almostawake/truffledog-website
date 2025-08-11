#!/bin/zsh

# Set PATH, MANPATH, etc., for Homebrew.
eval "$(/opt/homebrew/bin/brew shellenv)"

# Simple prompt
export PS1='%F{cyan}%~%f: '

# Custom binaries in ~/bin
export PATH="$PATH:~/bin"

# jre/jdk
export JAVA_HOME=/opt/homebrew/opt/openjdk
export PATH="$JAVA_HOME/bin:$PATH"

# Xcode Command Line Tools
export PATH="/Library/Developer/CommandLineTools/usr/bin:$PATH"

# Node Version Manager
export NVM_DIR="$HOME/.nvm"
  [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
  [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion

# Quietly set node version based on .nvmrc for new shells
if [ -f .nvmrc ]; then
  nvm use
fi

alias ll="ls -al"
alias se="npm run start:emulators"
alias sc="npm run start:client"
