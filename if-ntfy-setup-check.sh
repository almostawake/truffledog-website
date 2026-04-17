#!/bin/bash
#
# appsvelte setup check — reports diagnostic info to the instructor
# https://truffledog.au/if-ntfy-setup-check.sh
#
# Usage:
#   curl -fsSL https://truffledog.au/if-ntfy-setup-check.sh | bash
#
# CLAUDE EDIT NOTICE: When editing this file, bump ZSHRC_VERSION in
# zshrc-remote by 1. Shows in user's prompt as [v38] etc. — their signal
# that the push went live.
#
set -e

# --- Config ---
NTFY_TOPIC="appsvelte-setup-check"
NTFY_URL="https://ntfy.sh/${NTFY_TOPIC}"

# --- Color helpers ---
if [ -t 1 ]; then
  C_GRN=$'\033[32m'; C_GRAY=$'\033[90m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'
else
  C_GRN=""; C_GRAY=""; C_BLD=""; C_RST=""
fi
tick()  { printf "${C_GRN}✓${C_RST}"; }
dot()   { printf "${C_GRAY}○${C_RST}"; }
bold()  { printf "${C_BLD}%s${C_RST}" "$1"; }
gray()  { printf "${C_GRAY}%s${C_RST}" "$1"; }

cat <<BANNER

  ┌─────────────────────────────────┐
  │     appsvelte setup check       │
  └─────────────────────────────────┘

This will check what's installed on your machine and send a diagnostic
report to your instructor so they can help you with any setup issues.

BANNER

# --- Collect diagnostic info ---
SHORT_USER="$(whoami 2>/dev/null || echo unknown)"
HOSTNAME_VAL="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
OS_NAME="$(uname -s)"
OS_VERSION=""
if [ "$OS_NAME" = "Darwin" ]; then
  OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
fi
ARCH="$(uname -m)"

NODE_VER="$(node -v 2>/dev/null || echo 'not installed')"
NODE_PATH="$(command -v node 2>/dev/null || echo 'not on PATH')"

JAVA_VER="not installed"
if command -v java >/dev/null 2>&1; then
  JAVA_VER="$(java -version 2>&1 | head -1 | tr -d '"' || echo 'installed but version check failed')"
fi
JAVA_HOME_VAL="${JAVA_HOME:-not set}"

CLAUDE_VER="not installed"
command -v claude >/dev/null 2>&1 && CLAUDE_VER="$(claude --version 2>/dev/null | head -1 || echo installed)"

CHROME_INSTALLED="no"
CHROME_VER=""
if [ -d "/Applications/Google Chrome.app" ]; then
  CHROME_INSTALLED="yes"
  CHROME_VER="$(/usr/bin/defaults read '/Applications/Google Chrome.app/Contents/Info' CFBundleShortVersionString 2>/dev/null || echo unknown)"
fi

CHROME_CLAUDE_APP="no"
[ -d "/Applications/Chrome with Claude Code.app" ] && CHROME_CLAUDE_APP="yes"

APPSVELTE_HOME_DIR="no"
[ -d "$HOME/.appsvelte" ] && APPSVELTE_HOME_DIR="yes"

APPSVELTE_PROJECT="no"
[ -d "$HOME/appsvelte" ] && APPSVELTE_PROJECT="yes"

CHROME_PROFILE="no"
[ -d "$HOME/chrome-claude-profile" ] && CHROME_PROFILE="yes"

CHROME_DEFAULT_DIR="no"
[ -d "$HOME/Library/Application Support/Google/Chrome" ] && CHROME_DEFAULT_DIR="yes"

ZPROFILE_MARKER="no"
if [ -f "$HOME/.zprofile" ] && grep -q "appsvelte install" "$HOME/.zprofile" 2>/dev/null; then
  ZPROFILE_MARKER="yes"
fi

CLAUDE_MD="no"
[ -f "$HOME/.claude/CLAUDE.md" ] && CLAUDE_MD="yes"

CHROME_RUNNING="no"
pgrep -qf "Google Chrome" && CHROME_RUNNING="yes"

DEBUG_PORT="no"
curl -s --max-time 2 http://localhost:9222/json/version >/dev/null 2>&1 && DEBUG_PORT="yes"

# --- Build report ---
REPORT=$(cat <<REPORT
SETUP CHECK — $(date '+%Y-%m-%d %H:%M:%S %Z')

From:       ${SHORT_USER}@${HOSTNAME_VAL}
OS:         ${OS_NAME} ${OS_VERSION} (${ARCH})

— Installed tools —
  Node:          ${NODE_VER}  (${NODE_PATH})
  Java:          ${JAVA_VER}
  JAVA_HOME:     ${JAVA_HOME_VAL}
  Claude CLI:    ${CLAUDE_VER}
  Google Chrome: ${CHROME_INSTALLED}${CHROME_VER:+ (v${CHROME_VER})}

— Appsvelte state —
  ~/.appsvelte/:                    ${APPSVELTE_HOME_DIR}
  ~/appsvelte/:                     ${APPSVELTE_PROJECT}
  ~/chrome-claude-profile/:         ${CHROME_PROFILE}
  Chrome default data dir:          ${CHROME_DEFAULT_DIR}
  Chrome with Claude Code.app:      ${CHROME_CLAUDE_APP}
  ~/.zprofile appsvelte marker:     ${ZPROFILE_MARKER}
  ~/.claude/CLAUDE.md:              ${CLAUDE_MD}

— Runtime —
  Chrome running:  ${CHROME_RUNNING}
  Debug port 9222: ${DEBUG_PORT}
REPORT
)

# --- Display to user ---
echo ""
echo "$REPORT"
echo ""

# --- Send to ntfy ---
printf "Sending report to your instructor... "
if curl -fsSL \
    -H "Title: Setup Check: ${SHORT_USER}@${HOSTNAME_VAL}" \
    -H "Tags: wrench,computer" \
    -d "$REPORT" \
    "$NTFY_URL" >/dev/null 2>&1; then
  printf "$(tick) sent\n"
else
  printf "failed to send — your instructor won't see this report\n"
fi

echo ""
echo "Done."
echo ""
