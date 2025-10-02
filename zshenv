#!/bin/zsh

# Set PATH, MANPATH, etc., for Homebrew.
eval "$(/opt/homebrew/bin/brew shellenv)"

# Custom binaries in ~/bin
export PATH="$PATH:~/bin"

# Set JAVA_HOME using macOS java_home utility
if [[ -x /usr/libexec/java_home ]]; then
  export JAVA_HOME=$(/usr/libexec/java_home)
fi
export PATH="$JAVA_HOME/bin:$PATH"

# Xcode Command Line Tools
export PATH="/Library/Developer/CommandLineTools/usr/bin:$PATH"

# Node Version Manager
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  
if [ -f .nvmrc ] && [ -d "$NVM_DIR/versions/node" ]; then
  cp -f .nvmrc .nvm-found-here
  NODE_VERSION=$(cat .nvmrc)
  if [ -d "$NVM_DIR/versions/node/v$NODE_VERSION" ]; then
    export PATH="$NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH"
  fi
fi