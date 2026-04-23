#!/bin/bash
#
# TESTING ONLY — wipe 'if' state so the installer can be re-run from scratch.
# Designed for use inside a VM. Not a production uninstaller (see if-uninstall.sh
# for that one when it's written).
#
# Removes:
#   ~/.if/               — everything we install (node, java, claude, git, gh,
#                          npm-cache, claude-config, creds, ...)
#   ~/.zshrc             — along with any .zshrc.*.bak we've produced
#   ~/.npm/              — npm cache (created on fresh installs before
#                          NPM_CONFIG_CACHE takes effect)
#   ~/.claude/           — Claude Code data dir (created on fresh installs
#                          before CLAUDE_CONFIG_DIR takes effect)
#   ~/.claude.json       — Claude Code top-level config
#
# Leaves alone:
#   Xcode Command Line Tools (/Library/Developer/CommandLineTools) — removing
#   it needs sudo and a reboot is flaky. If you want to reset that too,
#   manually: sudo rm -rf /Library/Developer/CommandLineTools
#
# Usage:
#   bash ~/_code/truffledog-website/if-u.sh
#
set -e

say() { printf '%s\n' "$*"; }

paths=(
  "$HOME/.if"
  "$HOME/.npm"
  "$HOME/.claude"
  "$HOME/.claude.json"
  "$HOME/.zshrc"
)

say "Wiping 'if' state..."
for p in "${paths[@]}"; do
  if [ -e "$p" ] || [ -L "$p" ]; then
    rm -rf "$p"
    say "  removed $p"
  fi
done

# Catch any timestamped .zshrc backups the installer left behind
for bak in "$HOME"/.zshrc.*.bak; do
  [ -e "$bak" ] || continue
  rm -f "$bak"
  say "  removed $bak"
done

say ""
say "Clean. Exit this shell (or open a new terminal) before re-running install,"
say "so no stale PATH/env carries over."
