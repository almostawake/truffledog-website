#!/bin/zsh
#Local ~/.zshenv file copied to new machines manually
# Try to update cached version (silent fail if offline)
curl -fsSL https://truffledog.au/zshenv-remote -o ~/.zshenv-cached 2>/dev/null || true
# Source the cached version
[ -f ~/.zshenv-cached ] && source ~/.zshenv-cached
