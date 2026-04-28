#!/bin/zsh
#Local ~/.zshrc file copied to new machines manually
# Try to update cached version (silent fail if offline)
curl -fsSL https://truffledog.au/zshrc-remote -o ~/.zshrc-cached 2>/dev/null || true
# Source the cached version
[ -f ~/.zshrc-cached ] && source ~/.zshrc-cached
