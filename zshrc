#!/bin/zsh

# Update Claude Code
brew upgrade --cask claude-code 2>&1 | grep -v "Warning:"

# Simple prompt
export PS1='%F{cyan}%~%f > '

# Aliases
alias ll="ls -al"
alias se="npm run start:emulators"
alias sc="npm run start:client"
alias python="/opt/homebrew/bin/python3.11"