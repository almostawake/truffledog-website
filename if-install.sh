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
MARKER_START="# >>> if install >>>"
MARKER_END="# <<< if install <<<"
INSTALL_URL="https://truffledog.au/if-install.sh"
UNINSTALL_URL="https://truffledog.au/if-uninstall.sh"

# Keep user's ~/ clean: route npm cache and Claude state under ~/.if
# Exported early so our own npm install uses the new cache location,
# and re-exported via the zshrc block below for future sessions.
mkdir -p "$IF_HOME/npm-cache" "$IF_HOME/claude-config"
export NPM_CONFIG_CACHE="$IF_HOME/npm-cache"
export CLAUDE_CONFIG_DIR="$IF_HOME/claude-config"

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

have_git=false
git_path="$(command -v git 2>/dev/null || true)"
if [ -n "$git_path" ]; then
  case "$git_path" in
    /usr/bin/git)
      # macOS ships /usr/bin/git as a stub that triggers the CLT install
      # dialog when invoked. It only resolves to a real git once Xcode
      # Command Line Tools (or Xcode.app) is installed.
      if xcode-select -p >/dev/null 2>&1; then
        have_git=true
      fi
      ;;
    *)
      # git is from somewhere else (Homebrew, our ~/.if/git, asdf, etc.) —
      # trust it.
      have_git=true
      ;;
  esac
fi

have_gh=false
command -v gh >/dev/null 2>&1 && have_gh=true

# Detect macOS codename for Homebrew bottle tag (arm64 only — Intel users
# fall back to xcode-select regardless).
MACOS_CODENAME=""
if [ "$OS" = "darwin" ]; then
  case "$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)" in
    14) MACOS_CODENAME="sonoma"  ;;
    15) MACOS_CODENAME="sequoia" ;;
    26) MACOS_CODENAME="tahoe"   ;;
    *)  MACOS_CODENAME=""        ;;
  esac
fi

# --- Banner ---
cat <<BANNER

  ┌─────────────────────────────────┐
  │     if — impatient futurist     │
  └─────────────────────────────────┘

This script will install the following if they're not already present:

BANNER

print_item() {
  local name="$1" present="$2"
  if [ "$present" = "true" ]; then
    printf '  %s  %-16s %s\n' "$(tick)" "$name" "$(gray 'already installed')"
  else
    printf '  %s  %s\n' "$(dot)" "$name"
  fi
}

print_item "Node 22"     "$have_node22"
print_item "Java 21"     "$have_java21"
print_item "Claude Code" "$have_claude"
print_item "git"         "$have_git"
print_item "gh"          "$have_gh"
say ""

# --- Prompt: proceed with deps install? ---
if $have_node22 && $have_java21 && $have_claude && $have_git && $have_gh; then
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
  say "Installing Node 22..."
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
  say "Installing Java 21..."
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

# Claude Code CLI (into ~/.if/claude/ so it parallels node/ and java/)
export PATH="$IF_HOME/claude/bin:$PATH"
if ! $have_claude; then
  say ""
  say "Installing Claude Code..."
  mkdir -p "$IF_HOME/claude"
  npm_log="$(mktemp)"
  if npm install --prefix "$IF_HOME/claude" -g @anthropic-ai/claude-code 2>&1 | tee "$npm_log" >/dev/null; then
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

# --- git ---
# ARM: fetch Homebrew bottles from ghcr.io, patch dylib paths, re-sign. ~64MB
#      under ~/.if/git/. No admin, no Xcode CLT.
# Intel: fall back to `xcode-select --install` GUI dialog (~2GB, no admin but
#        requires one click + ~10min wait).
#
# The ARM path only works when we know the bottle tag for the current macOS
# (MACOS_CODENAME is set). Unknown macOS → CLT fallback.

# Fetch a single Homebrew bottle by name + tag + target staging dir.
# Extracts the tarball (which contains <name>/<version>/...).
fetch_bottle() {
  local pkg="$1" tag="$2" stage="$3"
  local json url token
  json=$(curl -fsSL "https://formulae.brew.sh/api/formula/${pkg}.json") || return 1
  url=$(printf '%s' "$json" | perl -MJSON::PP -e "
    my \$j = decode_json(join('', <STDIN>));
    my \$f = \$j->{bottle}{stable}{files}{'${tag}'};
    print \$f->{url} if \$f;") || return 1
  [ -z "$url" ] && return 1
  token=$(curl -fsSL "https://ghcr.io/token?service=ghcr.io&scope=repository:homebrew/core/${pkg}:pull" \
    | perl -MJSON::PP -e 'my $j = decode_json(join("",<STDIN>)); print $j->{token}') || return 1
  curl -fsSL -H "Authorization: Bearer $token" "$url" | tar -xz -C "$stage" || return 1
}

install_git_bottle() {
  # Assembles a usable git from three Homebrew bottles without rewriting
  # any binaries. Bottles reference their deps as "@@HOMEBREW_PREFIX@@/..."
  # which dyld can't resolve — we set DYLD_FALLBACK_LIBRARY_PATH in the
  # zshrc block to point at ~/.if/git/lib so dyld finds the libs by
  # basename as a fallback. This avoids needing install_name_tool +
  # codesign (both of which depend on Xcode CLT being installed).
  local tag="$1"
  local stage; stage=$(mktemp -d)
  fetch_bottle git     "$tag" "$stage" || { rm -rf "$stage"; return 1; }
  fetch_bottle pcre2   "$tag" "$stage" || { rm -rf "$stage"; return 1; }
  fetch_bottle gettext "$tag" "$stage" || { rm -rf "$stage"; return 1; }

  local git_ver pcre2_ver gettext_ver
  git_ver=$(ls "$stage/git" | head -1)
  pcre2_ver=$(ls "$stage/pcre2" | head -1)
  gettext_ver=$(ls "$stage/gettext" | head -1)

  rm -rf "$IF_HOME/git"
  mkdir -p "$IF_HOME/git/lib"
  cp -R "$stage/git/$git_ver/." "$IF_HOME/git/"
  cp "$stage/pcre2/$pcre2_ver/lib/libpcre2-8.0.dylib" "$IF_HOME/git/lib/"
  cp "$stage/gettext/$gettext_ver/lib/libintl.8.dylib" "$IF_HOME/git/lib/"

  rm -rf "$stage"
  local ver
  ver=$(DYLD_FALLBACK_LIBRARY_PATH="$IF_HOME/git/lib" "$IF_HOME/git/bin/git" --version 2>/dev/null | awk '{print $3}')
  printf '  %s git %s\n' "$(tick)" "$ver"
}

install_git_xcode() {
  if xcode-select -p >/dev/null 2>&1; then
    printf '  %s git (via existing Command Line Tools)\n' "$(tick)"
    return 0
  fi
  say "  Triggering macOS Command Line Tools install (needed for git)..."
  say "  A dialog will appear — click Install and wait (~10 min, ~2GB)."
  xcode-select --install 2>/dev/null || true
  local waited=0
  while ! xcode-select -p >/dev/null 2>&1; do
    sleep 10
    waited=$((waited+10))
    [ $((waited % 60)) -eq 0 ] && say "  Still waiting for Command Line Tools... (${waited}s)"
  done
  printf '  %s git (via Command Line Tools)\n' "$(tick)"
}

if ! $have_git; then
  say ""
  say "Installing git..."
  if [ "$OS" = "darwin" ] && [ "$ARCH" = "arm64" ] && [ -n "$MACOS_CODENAME" ]; then
    if ! install_git_bottle "arm64_${MACOS_CODENAME}"; then
      say "  Bottle install failed — falling back to Command Line Tools"
      install_git_xcode
    fi
  else
    install_git_xcode
  fi
fi
# Put our bottle-git on PATH for this session if it's there.
[ -x "$IF_HOME/git/bin/git" ] && export PATH="$IF_HOME/git/bin:$PATH"

# --- GitHub CLI (gh) ---
# Official release tarball (actually .zip on macOS) under ~/.if/gh/.
install_gh() {
  local arch_gh
  case "$ARCH" in
    arm64) arch_gh="arm64" ;;
    x64)   arch_gh="amd64" ;;
    *) die "gh: unsupported arch $ARCH" ;;
  esac
  local url
  url=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest \
    | perl -MJSON::PP -e "
        my \$j = decode_json(join('', <STDIN>));
        for my \$a (@{\$j->{assets}}) {
          next unless ref(\$a) eq 'HASH';
          if ((\$a->{name} // '') =~ /^gh_.*_macOS_${arch_gh}\\.zip\$/) {
            print \$a->{browser_download_url};
            last;
          }
        }")
  [ -z "$url" ] && die "gh: couldn't find release asset"
  local tmp_zip tmp_dir
  tmp_zip=$(mktemp -u).zip
  tmp_dir=$(mktemp -d)
  curl -fsSL "$url" -o "$tmp_zip"
  unzip -q "$tmp_zip" -d "$tmp_dir"
  rm -rf "$IF_HOME/gh"
  mv "$(ls -d "$tmp_dir"/*/)" "$IF_HOME/gh"
  rm -rf "$tmp_zip" "$tmp_dir"
  printf '  %s gh %s\n' "$(tick)" "$("$IF_HOME/gh/bin/gh" --version 2>/dev/null | head -1 | awk '{print $3}')"
}

if ! $have_gh; then
  say ""
  say "Installing gh..."
  install_gh
fi
[ -x "$IF_HOME/gh/bin/gh" ] && export PATH="$IF_HOME/gh/bin:$PATH"

# --- Update ~/.zshrc ---
# 1. If ~/.zshrc doesn't exist, create it (empty).
# 2. If it has content, back it up to a timestamped .bak (even on re-runs).
# 3. If our marker-fenced block is present, strip it — we'll re-append fresh
#    (so new versions of this installer can change paths cleanly).
# 4. Append the current block.
zshrc="$HOME/.zshrc"

if [ ! -e "$zshrc" ]; then
  touch "$zshrc"
fi

if [ -s "$zshrc" ]; then
  ts=$(date +%Y%m%d-%H%M)
  backup="${zshrc}.${ts}.bak"
  cp "$zshrc" "$backup"
  printf '  %s Backed up ~/.zshrc → %s\n' "$(tick)" "$(basename "$backup")"
fi

if grep -qF "$MARKER_START" "$zshrc"; then
  tmpf=$(mktemp)
  awk -v s="$MARKER_START" -v e="$MARKER_END" '
    $0 == s { skip=1; next }
    $0 == e { skip=0; next }
    !skip  { print }
  ' "$zshrc" > "$tmpf"
  mv "$tmpf" "$zshrc"
fi

if [ "$OS" = "darwin" ]; then
  jh_value="\$HOME/.if/java/Contents/Home"
else
  jh_value="\$HOME/.if/java"
fi

{
  [ -s "$zshrc" ] && printf '\n'
  printf '%s\n' "$MARKER_START"
  printf 'export PATH="$HOME/.if/node/bin:$PATH"\n'
  printf 'export PATH="$HOME/.if/claude/bin:$PATH"\n'
  printf 'export PATH="$HOME/.if/gh/bin:$PATH"\n'
  printf '[ -x "$HOME/.if/git/bin/git" ] && export PATH="$HOME/.if/git/bin:$PATH"\n'
  printf '[ -d "$HOME/.if/git/libexec/git-core" ] && export GIT_EXEC_PATH="$HOME/.if/git/libexec/git-core"\n'
  # dyld falls back here when the bottle's baked-in @@HOMEBREW_PREFIX@@ paths
  # fail to resolve. Preserves dyld's default fallbacks ($HOME/lib:/usr/local/lib:/usr/lib).
  printf '[ -d "$HOME/.if/git/lib" ] && export DYLD_FALLBACK_LIBRARY_PATH="$HOME/.if/git/lib:$HOME/lib:/usr/local/lib:/usr/lib"\n'
  printf 'export JAVA_HOME="%s"\n' "$jh_value"
  printf 'export PATH="$JAVA_HOME/bin:$PATH"\n'
  printf 'export NPM_CONFIG_CACHE="$HOME/.if/npm-cache"\n'
  printf 'export CLAUDE_CONFIG_DIR="$HOME/.if/claude-config"\n'
  printf '%s\n' "$MARKER_END"
} >> "$zshrc"

say ""
say "Updated your login script to use these."
say ""
say "$(bold 'Dependencies installed.')"
say ""

# Drop the user into a fresh login zsh so PATH / JAVA_HOME are live without
# needing a new terminal window. 'exit' (or ctrl-D) returns to the original
# shell. </dev/tty reconnects stdin to the terminal in case we're running
# via `curl ... | bash` where stdin is a pipe.
if [ -t 1 ] && [ -r /dev/tty ]; then
  exec zsh -l </dev/tty
fi
