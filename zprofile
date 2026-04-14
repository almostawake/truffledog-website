#!/bin/zsh
#Local ~/.zprofile file copied to new machines manually
# Try to update cached version (silent fail if offline)
curl -fsSL https://truffledog.au/zprofile-remote -o ~/.zprofile-cached 2>/dev/null || true
# Source the cached version
[ -f ~/.zprofile-cached ] && source ~/.zprofile-cached
