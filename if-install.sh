#!/bin/bash
#
# if (impatient futurist) installer (minimal — dep install only)
# https://truffledog.au/if-install.sh
#
# Usage:
#   curl -fsSL https://truffledog.au/if-install.sh | bash
#
# This script currently does items 1–3 from the original flow:
#   1. Load shared helpers (if-lib.sh)
#   2. Detect what's already installed
#   3. Install missing dependencies (Node 22, OpenJDK 21, Claude Code CLI)
#
# The project-clone / Chrome.app / provisioning steps have been parked
# while the new project-flow is being developed (see if-tst-3.sh).
#
# CLAUDE EDIT NOTICE: When editing this file, bump ZSHRC_VERSION in
# zshrc-remote by 1. Shows in user's prompt as [v38] etc. — their signal
# that the push went live.
#
set -e

# --- Step 1: Load shared helpers (colors, prompts, OS detection) ---
eval "$(curl -fsSL https://truffledog.au/if-lib.sh)"

# --- Constants ---
NODE_VERSION="22.11.0"
JAVA_VERSION="21"
IF_HOME="$HOME/.if"
IF_NPM_GLOBAL="$IF_HOME/npm-global"
MARKER_START="# >>> if install >>>"
MARKER_END="# <<< if install <<<"
INSTALL_URL="https://truffledog.au/if-install.sh"
UNINSTALL_URL="https://truffledog.au/if-uninstall.sh"

detect_os_arch

# --- Step 2: Detect what's already installed ---
have_node22=false
if command -v node >/dev/null 2>&1; then
  nm="$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)"
  if [ -n "$nm" ] && [ "$nm" -ge 22 ] 2>/dev/null; then
    have_node22=true
  fi
fi

have_java21=false
if command -v java >/dev/null 2>&1; then
  jm="$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d. -f1)"
  if [ -n "$jm" ] && [ "$jm" -ge 21 ] 2>/dev/null; then
    have_java21=true
  fi
fi

have_claude=false
command -v claude >/dev/null 2>&1 && have_claude=true

# --- Banner ---
cat <<BANNER

  ┌─────────────────────────────────┐
  │     if — impatient futurist     │
  └─────────────────────────────────┘

This script will install the following dependencies:

BANNER

print_item() {
  local name="$1" present="$2" dest="$3"
  if [ "$present" = "true" ]; then
    printf '  %s  %-28s %s\n' "$(tick)" "$name" "$(gray 'already installed')"
  else
    printf '  %s  %-28s %s\n' "$(dot)"  "$name" "$dest"
  fi
}

print_item "Node.js 22"        "$have_node22"   "→ ~/.if/node/"
print_item "OpenJDK 21 (JRE)"  "$have_java21"   "→ ~/.if/java/"
print_item "Claude Code CLI"   "$have_claude"   "→ via npm"

cat <<NOTE

These will be installed separately in ~/.if and should be
unintrusive, but if you have other code projects, there could be
conflicts. Existing apps on your system will use these new versions
when launched from a new terminal window.

To uninstall later:  curl -fsSL $UNINSTALL_URL | bash

NOTE

# --- Prompt: proceed with deps install? ---
if $have_node22 && $have_java21 && $have_claude; then
  say "All dependencies already installed."
  exit 0
else
  if ! prompt_yn "Do you wish to proceed?" "Y"; then
    say "No changes made. Goodbye."
    exit 0
  fi
fi

# --- Step 3: Install dependencies ---

# Node
if ! $have_node22; then
  say ""
  say "Installing Node $NODE_VERSION..."
  mkdir -p "$IF_HOME/node"
  case "$OS-$ARCH" in
    darwin-arm64) plat="darwin-arm64"; ext="tar.gz" ;;
    darwin-x64)   plat="darwin-x64";   ext="tar.gz" ;;
    linux-x64)    plat="linux-x64";    ext="tar.xz" ;;
    *) die "unsupported platform for Node: $OS-$ARCH" ;;
  esac
  url="https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-$plat.$ext"
  if [ "$ext" = "tar.xz" ]; then
    curl -fsSL "$url" | tar -xJ -C "$IF_HOME/node" --strip-components=1
  else
    curl -fsSL "$url" | tar -xz -C "$IF_HOME/node" --strip-components=1
  fi
  export PATH="$IF_HOME/node/bin:$PATH"
  printf '  %s Node %s\n' "$(tick)" "$(node -v)"
fi

# Java
if ! $have_java21; then
  say ""
  say "Installing OpenJDK $JAVA_VERSION (JRE)..."
  mkdir -p "$IF_HOME/java"
  case "$OS-$ARCH" in
    darwin-arm64) jplat="mac/aarch64" ;;
    darwin-x64)   jplat="mac/x64"     ;;
    linux-x64)    jplat="linux/x64"   ;;
    *) die "unsupported platform for Java: $OS-$ARCH" ;;
  esac
  jurl="https://api.adoptium.net/v3/binary/latest/$JAVA_VERSION/ga/$jplat/jre/hotspot/normal/eclipse"
  curl -fsSL "$jurl" | tar -xz -C "$IF_HOME/java" --strip-components=1
  if [ "$OS" = "darwin" ]; then
    export JAVA_HOME="$IF_HOME/java/Contents/Home"
  else
    export JAVA_HOME="$IF_HOME/java"
  fi
  export PATH="$JAVA_HOME/bin:$PATH"
  jver="$(java -version 2>&1 | head -1 | tr -d '"')"
  printf '  %s %s\n' "$(tick)" "$jver"
fi

# Claude Code CLI (into per-user npm prefix so no sudo is needed)
export PATH="$IF_NPM_GLOBAL/bin:$PATH"
if ! $have_claude; then
  say ""
  say "Installing Claude Code CLI..."
  mkdir -p "$IF_NPM_GLOBAL"
  npm_log="$(mktemp)"
  if npm install --prefix "$IF_NPM_GLOBAL" -g @anthropic-ai/claude-code 2>&1 | tee "$npm_log" >/dev/null; then
    rm -f "$npm_log"
    printf '  %s claude installed\n' "$(tick)"
  else
    say ""
    say "npm install output:"
    cat "$npm_log"
    rm -f "$npm_log"
    die "claude install failed — see npm output above"
  fi
fi

# --- Update ~/.zshrc (back up existing; write a fresh one with our block) ---
# Target audience runs this in a dedicated macOS user account, so we own the
# shell startup file. If an existing ~/.zshrc is present we rename it to a
# timestamped backup (keep whatever's there — don't try to merge); uninstall
# can restore it.
zshrc="$HOME/.zshrc"
if [ -e "$zshrc" ]; then
  ts=$(date +%Y%m%d-%H%M)
  backup="${zshrc}.${ts}.bak"
  mv "$zshrc" "$backup"
  printf '  %s Backed up existing ~/.zshrc → %s\n' "$(tick)" "$(basename "$backup")"
fi

if [ "$OS" = "darwin" ]; then
  jh_value="\$HOME/.if/java/Contents/Home"
else
  jh_value="\$HOME/.if/java"
fi

{
  printf '%s\n' "$MARKER_START"
  printf 'export PATH="$HOME/.if/node/bin:$PATH"\n'
  printf 'export PATH="$HOME/.if/npm-global/bin:$PATH"\n'
  printf 'export JAVA_HOME="%s"\n' "$jh_value"
  printf 'export PATH="$JAVA_HOME/bin:$PATH"\n'
  printf '%s\n' "$MARKER_END"
} > "$zshrc"
printf '  %s Wrote ~/.zshrc\n' "$(tick)"

say ""
say "$(bold 'Dependencies installed.')"
say "Open a new terminal to pick up the updated PATH (or run: source ~/.zshrc)"
say ""
