#!/bin/zsh

# Simple prompt
export PS1='%F{blue}%~%f > '

# NVM bash completion (interactive only)
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion

# Aliases
alias ll="ls -al"
alias se="npm run start:emulators"
alias sc="npm run start:client"
alias python="/opt/homebrew/bin/python3.11"