#!/bin/bash
#
# appsvelte installer
# https://truffledog.au/if-install.sh
#
# Usage:
#   curl -fsSL https://truffledog.au/if-install.sh | bash
#
# CLAUDE EDIT NOTICE: When editing this file, bump ZSHRC_VERSION in
# zshrc-remote by 1. Shows in user's prompt as [v38] etc. — their signal
# that the push went live.
#
set -e

# --- Constants ---
NODE_VERSION="22.11.0"
JAVA_VERSION="21"
APPSVELTE_HOME="$HOME/.appsvelte"
PROJECT_DIR="$HOME/appsvelte"
MARKER_START="# >>> appsvelte install >>>"
MARKER_END="# <<< appsvelte install <<<"
TEMPLATE_TARBALL="https://github.com/almostawake/appsvelte/archive/refs/heads/main.tar.gz"
INSTALL_URL="https://truffledog.au/if-install.sh"
UNINSTALL_URL="https://truffledog.au/if-uninstall.sh"

# --- Color helpers ---
if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_GRAY=$'\033[90m'
  C_BLD=$'\033[1m'; C_RST=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_GRAY=""; C_BLD=""; C_RST=""
fi

tick()  { printf "${C_GRN}✓${C_RST}"; }
dot()   { printf "${C_GRAY}○${C_RST}"; }
bold()  { printf "${C_BLD}%s${C_RST}" "$1"; }
gray()  { printf "${C_GRAY}%s${C_RST}" "$1"; }

say()   { printf '%s\n' "$*"; }
die()   { printf "${C_RED}error:${C_RST} %s\n" "$*" >&2; exit 1; }

prompt_yn() {
  # $1 = question, $2 = default (Y or N)
  local q="$1" def="$2" hint answer
  if [ "$def" = "Y" ]; then hint="[Y/n]"; else hint="[y/N]"; fi
  printf '%s %s ' "$q" "$hint"
  read -r answer </dev/tty || answer=""
  [ -z "$answer" ] && answer="$def"
  case "$answer" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# --- Detect OS / arch ---
case "$(uname -s)" in
  Darwin) OS="darwin" ;;
  Linux)  OS="linux"  ;;
  *) die "unsupported OS: $(uname -s) — this installer supports macOS and Linux only" ;;
esac
case "$(uname -m)" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64|amd64)  ARCH="x64"   ;;
  *) die "unsupported architecture: $(uname -m)" ;;
esac

# --- Detect what's already installed ---
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

have_project=false
[ -d "$PROJECT_DIR" ] && have_project=true

have_chrome_app=false
[ -d "/Applications/Chrome with Claude Code.app" ] && have_chrome_app=true

have_chrome=false
[ -d "/Applications/Google Chrome.app" ] && have_chrome=true

# --- Banner ---
cat <<BANNER

  ┌─────────────────────────────────┐
  │     appsvelte installer         │
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

print_item "Node.js 22"        "$have_node22"   "→ ~/.appsvelte/node/"
print_item "OpenJDK 21 (JRE)"  "$have_java21"     "→ ~/.appsvelte/java/"
print_item "Claude Code CLI"   "$have_claude"   "→ via npm"
if [ "$OS" = "darwin" ]; then
  if $have_chrome; then
    print_item "Chrome with Claude Code"  "$have_chrome_app"  "→ /Applications/"
  else
    printf '  %s  %-28s %s\n' "$(dot)" "Chrome with Claude Code" "$(gray 'skipped — Chrome not installed')"
  fi
fi

cat <<NOTE

These will be installed separately in ~/.appsvelte and should be
unintrusive, but if you have other code projects, there could be
conflicts. Existing apps on your system will use these new versions
when launched from a new terminal window.

To uninstall later:  curl -fsSL $UNINSTALL_URL | bash

NOTE

# --- Prompt 1: proceed with deps install? ---
if $have_node22 && $have_java21 && $have_claude; then
  say "All dependencies already installed."
else
  if ! prompt_yn "Do you wish to proceed?" "Y"; then
    say "No changes made. Goodbye."
    exit 0
  fi
fi

# --- Install Node ---
if ! $have_node22; then
  say ""
  say "Installing Node $NODE_VERSION..."
  mkdir -p "$APPSVELTE_HOME/node"
  case "$OS-$ARCH" in
    darwin-arm64) plat="darwin-arm64"; ext="tar.gz" ;;
    darwin-x64)   plat="darwin-x64";   ext="tar.gz" ;;
    linux-x64)    plat="linux-x64";    ext="tar.xz" ;;
    *) die "unsupported platform for Node: $OS-$ARCH" ;;
  esac
  url="https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-$plat.$ext"
  if [ "$ext" = "tar.xz" ]; then
    curl -fsSL "$url" | tar -xJ -C "$APPSVELTE_HOME/node" --strip-components=1
  else
    curl -fsSL "$url" | tar -xz -C "$APPSVELTE_HOME/node" --strip-components=1
  fi
  export PATH="$APPSVELTE_HOME/node/bin:$PATH"
  printf '  %s Node %s\n' "$(tick)" "$(node -v)"
fi

# --- Install Java ---
if ! $have_java21; then
  say ""
  say "Installing OpenJDK $JAVA_VERSION (JRE)..."
  mkdir -p "$APPSVELTE_HOME/java"
  case "$OS-$ARCH" in
    darwin-arm64) jplat="mac/aarch64" ;;
    darwin-x64)   jplat="mac/x64"     ;;
    linux-x64)    jplat="linux/x64"   ;;
    *) die "unsupported platform for Java: $OS-$ARCH" ;;
  esac
  jurl="https://api.adoptium.net/v3/binary/latest/$JAVA_VERSION/ga/$jplat/jre/hotspot/normal/eclipse"
  curl -fsSL "$jurl" | tar -xz -C "$APPSVELTE_HOME/java" --strip-components=1
  if [ "$OS" = "darwin" ]; then
    export JAVA_HOME="$APPSVELTE_HOME/java/Contents/Home"
  else
    export JAVA_HOME="$APPSVELTE_HOME/java"
  fi
  export PATH="$JAVA_HOME/bin:$PATH"
  jver="$(java -version 2>&1 | head -1 | tr -d '"')"
  printf '  %s %s\n' "$(tick)" "$jver"
fi

# --- Update .zprofile (idempotent via marker block) ---
if ! $have_node22 || ! $have_java21; then
  zprofile="$HOME/.zprofile"
  if [ ! -f "$zprofile" ] || ! grep -q "$MARKER_START" "$zprofile" 2>/dev/null; then
    if [ "$OS" = "darwin" ]; then
      jh_value="\$HOME/.appsvelte/java/Contents/Home"
    else
      jh_value="\$HOME/.appsvelte/java"
    fi
    {
      printf '\n%s\n' "$MARKER_START"
      printf 'export PATH="$HOME/.appsvelte/node/bin:$PATH"\n'
      printf 'export JAVA_HOME="%s"\n' "$jh_value"
      printf 'export PATH="$JAVA_HOME/bin:$PATH"\n'
      printf '%s\n' "$MARKER_END"
    } >> "$zprofile"
    printf '  %s Updated ~/.zprofile\n' "$(tick)"
  fi
fi

# --- Install Claude Code CLI ---
if ! $have_claude; then
  say ""
  say "Installing Claude Code CLI..."
  npm install -g @anthropic-ai/claude-code --silent >/dev/null 2>&1 || die "claude install failed"
  printf '  %s claude installed\n' "$(tick)"
fi

# --- Prompt 2: clone template? ---
say ""
if $have_project; then
  say "Project directory already exists at $PROJECT_DIR. Skipping clone."
else
  cat <<TEMPLATE_NOTE
This script will clone a template app and run it up locally for you to
complete the setup process. It will be installed into ~/appsvelte.

TEMPLATE_NOTE
  if ! prompt_yn "Do you wish to proceed?" "Y"; then
    say "Skipped template download."
    say ""
    say "You can install just the template later by re-running:"
    say "  curl -fsSL $INSTALL_URL | bash"
    exit 0
  fi

  mkdir -p "$PROJECT_DIR"
  curl -fsSL "$TEMPLATE_TARBALL" | tar -xz -C "$PROJECT_DIR" --strip-components=1
  printf '  %s Cloned to %s\n' "$(tick)" "$PROJECT_DIR"

  say ""
  say "Installing project dependencies..."
  ( cd "$PROJECT_DIR" && npm install --silent >/dev/null 2>&1 ) || die "npm install failed"
  printf '  %s Dependencies installed\n' "$(tick)"
fi

# ---------------------------------------------------------------------------
# --- Chrome with Claude Code .app (macOS only) ---
# ---------------------------------------------------------------------------
# DO NOT use osacompile to build this app — it creates an applet binary with
# an embedded resource-fork icon that can't be overridden, and macOS may run
# it under Rosetta on Apple Silicon which tanks performance system-wide.
# Instead we build the .app bundle manually: a shell script executable,
# a hand-written Info.plist with LSRequiresNativeExecution, and Chrome's
# own .icns copied into Resources.
# ---------------------------------------------------------------------------
if [ "$OS" = "darwin" ] && $have_chrome; then
  CHROME_APP="/Applications/Chrome with Claude Code.app"
  CHROME_PROFILE="$HOME/chrome-claude-profile"
  CHROME_DEFAULT="$HOME/Library/Application Support/Google/Chrome"

  # --- Move Chrome data dir on first run ---
  # If chrome-claude-profile already exists, the user has been through this
  # setup before (either by us or manually). Leave it alone.
  # If it does NOT exist, this is first time — move the default Chrome data
  # dir so the user keeps all their bookmarks, sessions, logins, extensions.
  #
  # DO NOT create a symlink at the default location. Chrome has known bugs
  # with symlinked profile dirs (Chromium issue 399856): settings fail to
  # save, "restore pages?" dialog every launch, 30-60s zombie processes on
  # exit. Just move the directory and let --user-data-dir handle the rest.
  if [ ! -d "$CHROME_PROFILE" ]; then
    say ""
    say "Setting up Chrome profile for Claude Code..."
    # Graceful quit — can't move data dir while Chrome has a lock
    osascript -e 'tell application "Google Chrome" to quit' 2>/dev/null
    for i in $(seq 1 10); do
      pgrep -qf "Google Chrome" || break
      sleep 0.5
    done
    if pgrep -qf "Google Chrome"; then
      killall -9 "Google Chrome" 2>/dev/null
      while pgrep -qf "Google Chrome"; do sleep 0.5; done
    fi
    if [ -d "$CHROME_DEFAULT" ]; then
      mv "$CHROME_DEFAULT" "$CHROME_PROFILE"
      printf '  %s Moved Chrome profile to %s\n' "$(tick)" "$CHROME_PROFILE"
    else
      # No existing Chrome data — create empty profile dir, Chrome will populate on first launch
      mkdir -p "$CHROME_PROFILE"
      printf '  %s Created new Chrome profile at %s\n' "$(tick)" "$CHROME_PROFILE"
    fi
  fi

  # --- Create/recreate the .app (always, so flag updates take effect on reinstall) ---
  say ""
  say "Installing Chrome with Claude Code app..."
  rm -rf "$CHROME_APP"

  mkdir -p "$CHROME_APP/Contents/MacOS"
  mkdir -p "$CHROME_APP/Contents/Resources"

  # Icon — use Chrome's own
  cp "/Applications/Google Chrome.app/Contents/Resources/app.icns" \
     "$CHROME_APP/Contents/Resources/app.icns" 2>/dev/null || true

  # Info.plist
  cat > "$CHROME_APP/Contents/Info.plist" << 'CHROMEPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Chrome with Claude Code</string>
  <key>CFBundleDisplayName</key>
  <string>Chrome with Claude Code</string>
  <key>CFBundleExecutable</key>
  <string>Chrome with Claude Code</string>
  <key>CFBundleIconFile</key>
  <string>app</string>
  <key>CFBundleIconName</key>
  <string>app</string>
  <key>CFBundleIdentifier</key>
  <string>au.truffledog.chrome-claude-code</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>10.15</string>
  <key>LSRequiresNativeExecution</key>
  <true/>
  <key>LSArchitecturePriority</key>
  <array>
    <string>arm64</string>
  </array>
</dict>
</plist>
CHROMEPLIST

  # Launcher script
  cat > "$CHROME_APP/Contents/MacOS/Chrome with Claude Code" << 'CHROMELAUNCH'
#!/bin/bash
# Graceful quit — let Chrome save session state and release locks
osascript -e 'tell application "Google Chrome" to quit' 2>/dev/null
for i in $(seq 1 10); do
  pgrep -qf 'Google Chrome' || break
  sleep 0.5
done
# Force kill only if Chrome refused to exit (e.g. hung tab)
if pgrep -qf 'Google Chrome'; then
  killall -9 'Google Chrome' 2>/dev/null
  while pgrep -qf 'Google Chrome'; do sleep 0.5; done
fi

# Launch Chrome with debug port and claude profile
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --remote-debugging-port=9222 \
  --silent-debugger-extension-api \
  --user-data-dir="$HOME/chrome-claude-profile" &>/dev/null &

# Wait for Chrome to be ready and write DevToolsActivePort
for i in $(seq 1 20); do
  sleep 0.5
  curl -s http://localhost:9222/json/version >/dev/null 2>&1 && break
done
mkdir -p "$HOME/Library/Application Support/Google/Chrome"
wspath=$(curl -s http://localhost:9222/json/version | \
  python3 -c "import sys,json; url=json.load(sys.stdin)['webSocketDebuggerUrl']; print(url.split('9222')[1])")
printf '9222\n'"${wspath}" > "$HOME/Library/Application Support/Google/Chrome/DevToolsActivePort"
CHROMELAUNCH

  chmod +x "$CHROME_APP/Contents/MacOS/Chrome with Claude Code"
  touch "$CHROME_APP"
  printf '  %s Installed %s\n' "$(tick)" "Chrome with Claude Code.app"
fi


# --- Install personal CLAUDE.md (only if none exists) ---
CLAUDE_DIR="$HOME/.claude"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
if [ ! -f "$CLAUDE_MD" ]; then
  mkdir -p "$CLAUDE_DIR"
  curl -fsSL https://truffledog.au/if-claude.md -o "$CLAUDE_MD" || true
  if [ -f "$CLAUDE_MD" ]; then
    printf '  %s Installed ~/.claude/CLAUDE.md\n' "$(tick)"
  fi
fi

# --- Final banner ---
cat <<DONE

$(bold 'All set!')

Next steps:
  1. Open a new terminal window
  2. Run:    cd ~/appsvelte && claude
  3. Tell Claude:  set up my project

Claude will guide you through the rest of setup using a browser tab.

To uninstall everything later:
  curl -fsSL $UNINSTALL_URL | bash

DONE
