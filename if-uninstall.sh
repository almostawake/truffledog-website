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

echo ""

if [ ! -d "$APPSVELTE_HOME" ] && { [ ! -f "$ZPROFILE" ] || ! grep -q "$MARKER_START" "$ZPROFILE" 2>/dev/null; }; then
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
