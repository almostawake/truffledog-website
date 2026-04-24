#!/bin/bash
#
# TESTING ONLY — wipe 'if' state so the installer can be re-run from scratch.
# Designed for use inside a VM. Not a production uninstaller (see if-uninstall.sh
# for that one when it's written).
#
# Removes:
#   ~/.if/                                           — everything we install
#                                                      (node, java, claude, git, gh,
#                                                      npm-cache, claude-config, creds, ...)
#   ~/.zshrc                                         — plus any .zshrc.*.bak we've produced
#   ~/.npm/                                          — npm cache (created before
#                                                      NPM_CONFIG_CACHE takes effect)
#   ~/.claude/                                       — Claude Code data dir (created
#                                                      before CLAUDE_CONFIG_DIR takes effect)
#   ~/.claude.json                                   — Claude Code top-level config
#   ~/Applications/Google Chrome.app                 — our user-level Chrome install
#   ~/Applications/Chrome with Claude Code.app       — our launcher bundle
#   ~/Library/Application Support/Google/Chrome-Claude/  — our debug-port profile
#   ~/Library/Application Support/Google/Chrome/     — default profile (just the
#                                                      DevToolsActivePort crumb we drop)
#   /tmp/if-install.log                              — per-run install trace
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

# --- Kill Chrome first so we can delete its profile/app without fighting locks ---
if pgrep -qf "Google Chrome"; then
  say "Quitting Chrome..."
  osascript -e 'tell application "Google Chrome" to quit' 2>/dev/null || true
  for i in $(seq 1 10); do
    pgrep -qf "Google Chrome" || break
    sleep 0.5
  done
  if pgrep -qf "Google Chrome"; then
    killall -9 "Google Chrome" 2>/dev/null || true
    while pgrep -qf "Google Chrome"; do sleep 0.5; done
  fi
fi

paths=(
  "$HOME/.if"
  "$HOME/if"
  "$HOME/.npm"
  "$HOME/.claude"
  "$HOME/.claude.json"
  "$HOME/.zshrc"
  "$HOME/.local/state/gh"
  "$HOME/.config/gh"
  "$HOME/.cache/gh"
  "$HOME/Applications/Google Chrome.app"
  "$HOME/Applications/Chrome with Claude Code.app"
  "$HOME/Library/Application Support/Google/Chrome-Claude"
  "$HOME/Library/Application Support/Google/Chrome"
  "/tmp/if-install.log"
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

# Restore Terminal.app plist if the installer backed it up
TBAK="$HOME/Library/Preferences/com.apple.Terminal.plist.bak"
if [ -f "$TBAK" ]; then
  mv "$TBAK" "$HOME/Library/Preferences/com.apple.Terminal.plist"
  say "  restored com.apple.Terminal.plist from .bak"
fi

# Undo Finder "new window opens in ~/if"
defaults delete com.apple.finder NewWindowTarget 2>/dev/null && \
  say "  cleared Finder NewWindowTarget" || true
defaults delete com.apple.finder NewWindowTargetPath 2>/dev/null && \
  say "  cleared Finder NewWindowTargetPath" || true
killall Finder 2>/dev/null || true

# Remove the ~/if entry we added to Dock persistent-others (leaves other
# dock entries alone). PlistBuddy iterates last→first so deletes don't
# shift indices underneath us.
DOCK_PLIST="$HOME/Library/Preferences/com.apple.dock.plist"
if [ -f "$DOCK_PLIST" ]; then
  TARGET_URL="file://$HOME/if/"
  i=0
  while /usr/libexec/PlistBuddy -c "Print :persistent-others:$i" "$DOCK_PLIST" >/dev/null 2>&1; do
    i=$((i+1))
  done
  i=$((i-1))
  removed=0
  while [ $i -ge 0 ]; do
    url=$(/usr/libexec/PlistBuddy -c "Print :persistent-others:$i:tile-data:file-data:_CFURLString" "$DOCK_PLIST" 2>/dev/null || true)
    if [ "$url" = "$TARGET_URL" ]; then
      /usr/libexec/PlistBuddy -c "Delete :persistent-others:$i" "$DOCK_PLIST" 2>/dev/null || true
      removed=$((removed+1))
    fi
    i=$((i-1))
  done
  [ $removed -gt 0 ] && say "  removed $removed Dock entry/entries for ~/if"
fi
killall Dock 2>/dev/null || true

# Undo "New Terminal at Folder" Services toggle. Fresh accounts have no
# custom services state, so nuking the whole NSServicesStatus dict is safe.
defaults delete pbs NSServicesStatus 2>/dev/null && \
  say "  cleared pbs NSServicesStatus" || true
/System/Library/CoreServices/pbs -update 2>/dev/null || true

# Mop up now-empty parent dirs so the home folder matches a fresh account.
# rmdir is safe — it only removes dirs that are actually empty (so if the
# user has other stuff in ~/Applications or ~/.local/state, we leave it).
for d in \
    "$HOME/.local/state" \
    "$HOME/.local" \
    "$HOME/.config" \
    "$HOME/.cache" \
    "$HOME/Applications" \
    "$HOME/Library/Application Support/Google" ; do
  rmdir "$d" 2>/dev/null && say "  removed empty $d" || true
done

say ""
say "Clean. Exit this shell (or open a new terminal) before re-running install,"
say "so no stale PATH/env carries over."
