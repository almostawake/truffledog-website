#!/bin/bash
#
# appsvelte uninstaller
# https://truffledog.au/if-uninstall.sh
#
# Usage:
#   curl -fsSL https://truffledog.au/if-uninstall.sh | bash
#
set -e

APPSVELTE_HOME="$HOME/.appsvelte"
PROJECT_DIR="$HOME/appsvelte"
CHROME_APP="/Applications/Chrome with Claude Code.app"
CHROME_PROFILE="$HOME/chrome-claude-profile"
CHROME_DEFAULT="$HOME/Library/Application Support/Google/Chrome"
MARKER_START="# >>> appsvelte install >>>"
MARKER_END="# <<< appsvelte install <<<"
ZPROFILE="$HOME/.zprofile"

if [ -t 1 ]; then
  C_GRN=$'\033[32m'; C_GRAY=$'\033[90m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'
else
  C_GRN=""; C_GRAY=""; C_BLD=""; C_RST=""
fi
tick() { printf "${C_GRN}✓${C_RST}"; }

prompt_yn() {
  local q="$1" def="$2" hint answer
  if [ "$def" = "Y" ]; then hint="[Y/n]"; else hint="[y/N]"; fi
  printf '%s %s ' "$q" "$hint"
  read -r answer </dev/tty || answer=""
  [ -z "$answer" ] && answer="$def"
  case "$answer" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

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

# --- Restore Chrome default data dir (if we symlinked it) ---
if [ -L "$CHROME_DEFAULT" ]; then
  rm "$CHROME_DEFAULT"
  if [ -d "$CHROME_PROFILE" ]; then
    mv "$CHROME_PROFILE" "$CHROME_DEFAULT"
    printf '  %s Restored Chrome data to default location\n' "$(tick)"
  fi
fi

# --- Ask about project dir separately (default NO) ---
if [ -d "$PROJECT_DIR" ]; then
  echo ""
  echo "The project directory $PROJECT_DIR still exists."
  echo "This contains the template and any customisations you have made."
  if prompt_yn "Remove $PROJECT_DIR as well?" "N"; then
    rm -rf "$PROJECT_DIR"
    printf '  %s Removed %s\n' "$(tick)" "$PROJECT_DIR"
  else
    echo "  Kept $PROJECT_DIR"
  fi
fi

cat <<DONE

${C_BLD}Done.${C_RST}

Restart your terminal for PATH changes to take effect.

DONE
