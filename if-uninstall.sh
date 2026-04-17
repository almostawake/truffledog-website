#!/bin/bash
#
# appsvelte uninstaller
# https://truffledog.au/if-uninstall.sh
#
# Usage:
#   curl -fsSL https://truffledog.au/if-uninstall.sh | bash
#
# CLAUDE EDIT NOTICE: When editing this file, bump ZSHRC_VERSION in
# zshrc-remote by 1. Shows in user's prompt as [v38] etc. — their signal
# that the push went live.
#
set -e

# --- Load shared helpers ---
eval "$(curl -fsSL https://truffledog.au/if-lib.sh)"

# --- Constants ---
APPSVELTE_HOME="$HOME/.appsvelte"
CHROME_APP="/Applications/Chrome with Claude Code.app"
CHROME_PROFILE="$HOME/chrome-claude-profile"
CHROME_DEFAULT="$HOME/Library/Application Support/Google/Chrome"
MARKER_START="# >>> appsvelte install >>>"
MARKER_END="# <<< appsvelte install <<<"
ZPROFILE="$HOME/.zprofile"

cat <<BANNER

  ┌─────────────────────────────────┐
  │     appsvelte uninstaller       │
  └─────────────────────────────────┘

This will remove:

BANNER

[ -d "$APPSVELTE_HOME" ] && printf '  • %s  (Node, Java, tools, secrets)\n' "$APPSVELTE_HOME"
[ -f "$ZPROFILE" ] && grep -q "$MARKER_START" "$ZPROFILE" 2>/dev/null && \
  printf '  • marker block in %s\n' "$ZPROFILE"
[ -d "$CHROME_APP" ] && printf '  • %s\n' "$CHROME_APP"

echo ""
say "Your project folders (e.g. ~/my-budget-tracker) will NOT be touched."
say "Delete them manually if you want to remove them."
echo ""

if [ ! -d "$APPSVELTE_HOME" ] && [ ! -d "$CHROME_APP" ] && { [ ! -f "$ZPROFILE" ] || ! grep -q "$MARKER_START" "$ZPROFILE" 2>/dev/null; }; then
  echo "Nothing to remove. appsvelte does not appear to be installed."
  exit 0
fi

if ! prompt_yn "Proceed?" "Y"; then
  echo "Cancelled. No changes made."
  exit 0
fi

# --- Remove ~/.appsvelte ---
if [ -d "$APPSVELTE_HOME" ]; then
  rm -rf "$APPSVELTE_HOME"
  printf '  %s Removed %s\n' "$(tick)" "$APPSVELTE_HOME"
fi

# --- Strip marker block from .zprofile ---
if [ -f "$ZPROFILE" ] && grep -q "$MARKER_START" "$ZPROFILE" 2>/dev/null; then
  tmp="$(mktemp)"
  awk -v s="$MARKER_START" -v e="$MARKER_END" '
    $0 ~ s {skip=1; next}
    $0 ~ e {skip=0; next}
    !skip {print}
  ' "$ZPROFILE" > "$tmp"
  mv "$tmp" "$ZPROFILE"
  printf '  %s Cleaned ~/.zprofile\n' "$(tick)"
fi

# --- Remove Chrome with Claude Code app ---
if [ -d "$CHROME_APP" ]; then
  rm -rf "$CHROME_APP"
  printf '  %s Removed %s\n' "$(tick)" "Chrome with Claude Code.app"
fi

# --- Restore Chrome default data dir (if we moved it) ---
# Only move back if the profile dir exists AND the default location doesn't
# (avoids clobbering a real default dir the user created since install)
if [ -d "$CHROME_PROFILE" ] && [ ! -d "$CHROME_DEFAULT" ]; then
  mv "$CHROME_PROFILE" "$CHROME_DEFAULT"
  printf '  %s Restored Chrome data to default location\n' "$(tick)"
elif [ -d "$CHROME_PROFILE" ]; then
  say "  Note: $CHROME_PROFILE still exists (default Chrome dir also present, not moving)"
fi

cat <<DONE

${C_BLD}Done.${C_RST}

Restart your terminal for PATH changes to take effect.

Project folders under your home directory (if any) were left intact.

DONE
