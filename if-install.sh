#!/bin/bash
#
# if (impatient futurist) installer (minimal — dep install only)
# https://truffledog.au/if-install.sh
#
# Usage:
#   curl -fsSL https://truffledog.au/if-install.sh | bash
#
# CLAUDE EDIT NOTICE: Don't bump ZSHRC_VERSION in zshrc-remote for
# changes to THIS file — that counter is for user-shell changes only
# (it shows in their prompt, so bumping it without a zshrc change is
# misleading).
#
set -e

# --- Load shared helpers (colors, prompts, OS detection) ---
eval "$(curl -fsSL https://truffledog.au/if-lib.sh)"

# --- Constants ---
NODE_VERSION="22.11.0"
JAVA_VERSION="21"
IF_HOME="$HOME/.if"
MARKER_START="# >>> if install >>>"
MARKER_END="# <<< if install <<<"
INSTALL_URL="https://truffledog.au/if-install.sh"
UNINSTALL_URL="https://truffledog.au/if-uninstall.sh"
INSTALL_LOG="/tmp/if-install.log"
: > "$INSTALL_LOG"

# If the script exits abnormally (non-zero, Ctrl-C, etc.), surface the tail
# of the install log so the user doesn't have to hunt for it.
trap '_rc=$?; if [ $_rc -ne 0 ]; then
  printf "\n\n--- last 40 lines of %s ---\n" "$INSTALL_LOG" >&2
  tail -n 40 "$INSTALL_LOG" >&2
  printf "\n(full log: %s)\n" "$INSTALL_LOG" >&2
fi' EXIT

# Keep ~/ clean: route npm cache and Claude state under ~/.if
mkdir -p "$IF_HOME/npm-cache" "$IF_HOME/claude-config"
export NPM_CONFIG_CACHE="$IF_HOME/npm-cache"
export CLAUDE_CONFIG_DIR="$IF_HOME/claude-config"

detect_os_arch

# --- Detect macOS codename for Homebrew bottle tag ---
MACOS_CODENAME=""
if [ "$OS" = "darwin" ]; then
  case "$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)" in
    14) MACOS_CODENAME="sonoma"  ;;
    15) MACOS_CODENAME="sequoia" ;;
    26) MACOS_CODENAME="tahoe"   ;;
  esac
fi

# ==========================================================================
# Detection — what's already installed
# ==========================================================================

have_node22=false
if command -v node >/dev/null 2>&1; then
  nm="$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)"
  [ -n "$nm" ] && [ "$nm" -ge 22 ] 2>/dev/null && have_node22=true
fi

have_java21=false
if command -v java >/dev/null 2>&1; then
  jm="$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d. -f1)"
  [ -n "$jm" ] && [ "$jm" -ge 21 ] 2>/dev/null && have_java21=true
fi

have_claude=false
command -v claude >/dev/null 2>&1 && have_claude=true

have_git=false
git_path="$(command -v git 2>/dev/null || true)"
if [ -n "$git_path" ]; then
  case "$git_path" in
    /usr/bin/git)
      # macOS ships /usr/bin/git as a stub that triggers the CLT install
      # dialog when invoked. Real only once Xcode CLT/app is installed.
      xcode-select -p >/dev/null 2>&1 && have_git=true
      ;;
    *) have_git=true ;;
  esac
fi

have_gh=false
command -v gh >/dev/null 2>&1 && have_gh=true

# Chrome row represents Chrome.app + Claude-connected launcher together —
# only "installed" when both exist.
have_chrome=false
if [ "$OS" = "darwin" ]; then
  if [ -d "$HOME/Applications/Chrome with Claude Code.app" ] && \
     { [ -d "$HOME/Applications/Google Chrome.app" ] || \
       [ -d "/Applications/Google Chrome.app" ]; }; then
    have_chrome=true
  fi
fi

# ==========================================================================
# Install helpers — each writes only to $INSTALL_LOG (via stdout redirect)
# and returns 0 on success. No direct terminal output.
# ==========================================================================

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

_install_node() {
  mkdir -p "$IF_HOME/node"
  local plat ext url
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
}

_install_java() {
  mkdir -p "$IF_HOME/java"
  local jplat jurl
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
}

# git — ARM uses Homebrew bottle extraction (no CLT), Intel falls back to
# xcode-select --install (GUI dialog).
_install_git() {
  if [ "$OS" = "darwin" ] && [ "$ARCH" = "arm64" ] && [ -n "$MACOS_CODENAME" ]; then
    _install_git_bottle "arm64_${MACOS_CODENAME}" && return 0
    # Fall through to CLT on bottle failure.
  fi
  _install_git_xcode
}

_install_git_bottle() {
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
  # Verify by running it once; set DYLD_FALLBACK_LIBRARY_PATH so the
  # baked-in @@HOMEBREW_PREFIX@@ paths resolve.
  DYLD_FALLBACK_LIBRARY_PATH="$IF_HOME/git/lib" "$IF_HOME/git/bin/git" --version >/dev/null
}

_install_git_xcode() {
  if xcode-select -p >/dev/null 2>&1; then return 0; fi
  # GUI dialog triggers here. User must click, wait ~10min.
  # We go silent after triggering and poll until CLT appears.
  xcode-select --install 2>/dev/null || true
  while ! xcode-select -p >/dev/null 2>&1; do sleep 10; done
}

_install_gh() {
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
}

# Claude Code binary + YOLO config files drop (CLAUDE.md, .claude.json,
# .claude/settings.json under $CLAUDE_CONFIG_DIR).
_install_claude() {
  mkdir -p "$IF_HOME/claude"
  export PATH="$IF_HOME/claude/bin:$PATH"
  npm install --prefix "$IF_HOME/claude" -g @anthropic-ai/claude-code

  # Seed config files (only if not already present — re-runs preserve state)
  mkdir -p "$IF_HOME/claude-config/.claude"
  [ -f "$IF_HOME/claude-config/.claude/CLAUDE.md" ] || \
    curl -fsSL https://truffledog.au/if-a-claude.md -o "$IF_HOME/claude-config/.claude/CLAUDE.md"
  [ -f "$IF_HOME/claude-config/.claude/settings.json" ] || \
    curl -fsSL https://truffledog.au/if-a-claude-settings.json -o "$IF_HOME/claude-config/.claude/settings.json"

  # .claude.json needs a theme injected based on current system appearance —
  # dark theme for dark-mode users, light for light. Only runs on first
  # install (guard below) so re-runs don't overwrite a theme the user
  # later changed via Claude's /theme command.
  local claude_json="$IF_HOME/claude-config/.claude.json"
  if [ ! -f "$claude_json" ]; then
    curl -fsSL https://truffledog.au/if-a-claude.json -o "$claude_json"
    if [ "$OS" = "darwin" ]; then
      local theme="light"
      defaults read -g AppleInterfaceStyle 2>/dev/null | grep -q Dark && theme="dark"
      local tmp; tmp=$(mktemp)
      THEME="$theme" perl -MJSON::PP -e '
        local $/;
        my $j = decode_json(<STDIN>);
        $j->{theme} = $ENV{THEME};
        print JSON::PP->new->pretty->canonical->encode($j);
      ' < "$claude_json" > "$tmp" && mv "$tmp" "$claude_json"
    fi
  fi
}

# Chrome Stable + Chrome with Claude Code.app launcher.
_install_chrome() {
  _log() { echo "[$(date +%H:%M:%S)] chrome: $*"; }
  _log "start"
  [ "$OS" = "darwin" ] || { _log "not darwin, skipping"; return 0; }

  # 1. Install Chrome.app (skip if already present anywhere)
  local chrome_app=""
  [ -d "/Applications/Google Chrome.app" ]      && chrome_app="/Applications/Google Chrome.app"
  [ -d "$HOME/Applications/Google Chrome.app" ] && chrome_app="$HOME/Applications/Google Chrome.app"
  _log "existing chrome_app = [$chrome_app]"

  if [ -z "$chrome_app" ]; then
    local dmg; dmg=$(mktemp -u).dmg
    local mountpoint
    _log "downloading Chrome DMG to $dmg (~200MB)…"
    # -f: fail on HTTP errors, -S: show errors even when silent, -L: follow
    # redirects, --progress-bar: show one-line progress (goes to stderr →
    # into our log, so each run grows the log by a few hundred lines — fine
    # while we're debugging).
    if ! curl -fSL --progress-bar \
         "https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg" \
         -o "$dmg"; then
      _log "curl failed: exit=$?"
      rm -f "$dmg"
      return 1
    fi
    _log "DMG size: $(ls -la "$dmg" | awk '{print $5}') bytes"

    _log "hdiutil attach…"
    local attach_out
    attach_out=$(hdiutil attach "$dmg" -nobrowse -noverify -noautoopen 2>&1)
    _log "hdiutil output:"
    printf '%s\n' "$attach_out" | sed 's/^/    /'
    mountpoint=$(printf '%s' "$attach_out" \
      | awk '/\/Volumes\// { for (i=3; i<=NF; i++) printf "%s ", $i; print "" }' \
      | sed 's/ *$//' | head -1)
    _log "parsed mountpoint = [$mountpoint]"

    if [ -z "$mountpoint" ] || [ ! -d "$mountpoint/Google Chrome.app" ]; then
      _log "mount FAILED — mountpoint empty or Google Chrome.app missing at [$mountpoint]"
      # Try best-effort detach in case we partially attached
      [ -n "$mountpoint" ] && hdiutil detach "$mountpoint" -force -quiet 2>/dev/null || true
      rm -f "$dmg"
      return 1
    fi

    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/Google Chrome.app"
    _log "cp Chrome.app from $mountpoint to ~/Applications/"
    cp -R "$mountpoint/Google Chrome.app" "$HOME/Applications/"
    xattr -dr com.apple.quarantine "$HOME/Applications/Google Chrome.app" 2>/dev/null || true
    _log "detaching DMG"
    hdiutil detach "$mountpoint" -quiet 2>/dev/null \
      || hdiutil detach "$mountpoint" -force -quiet 2>/dev/null \
      || true
    rm -f "$dmg"
    chrome_app="$HOME/Applications/Google Chrome.app"
    _log "chrome_app now = $chrome_app"
  fi

  # 2. Build/rebuild the "Chrome with Claude Code.app" launcher (always, so
  #    flag changes take effect on re-runs).
  local launcher_app="$HOME/Applications/Chrome with Claude Code.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$launcher_app"
  mkdir -p "$launcher_app/Contents/MacOS"
  mkdir -p "$launcher_app/Contents/Resources"
  cp "$chrome_app/Contents/Resources/app.icns" "$launcher_app/Contents/Resources/app.icns" 2>/dev/null || true

  cat > "$launcher_app/Contents/Info.plist" <<'CHROMEPLIST'
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

  cat > "$launcher_app/Contents/MacOS/Chrome with Claude Code" <<CHROMELAUNCH
#!/bin/bash
# No kill-Chrome dance needed: Chrome with a different --user-data-dir
# coexists fine with the user's regular Chrome. If Chrome-Claude is
# already running, Chrome's process-singleton sends activation to the
# existing instance; the new process exits immediately. Debug port
# stays alive either way.

PROFILE="\$HOME/Library/Application Support/Google/Chrome-Claude"

"$chrome_app/Contents/MacOS/Google Chrome" \\
  --remote-debugging-port=9222 \\
  --silent-debugger-extension-api \\
  --user-data-dir="\$PROFILE" &>/dev/null &

# Wait up to 10s for the debug port to accept connections. When Chrome-Claude
# is already running, this returns near-instantly. Cold start takes ~2-4s.
for i in \$(seq 1 20); do
  sleep 0.5
  curl -s http://localhost:9222/json/version >/dev/null 2>&1 && break
done

# Drop a DevToolsActivePort file where the chrome-devtools MCP server
# looks for it (mirrors Chrome's own default behavior for its default
# profile so MCP discovery "just works").
mkdir -p "\$HOME/Library/Application Support/Google/Chrome"
wspath=\$(curl -s http://localhost:9222/json/version | \\
  perl -MJSON::PP -e 'my \$j=decode_json(join("",<STDIN>)); my \$u=\$j->{webSocketDebuggerUrl} // ""; my (\$p) = \$u =~ m{:9222(.*)}; print \$p // ""')
printf '9222\n'"\${wspath}" > "\$HOME/Library/Application Support/Google/Chrome/DevToolsActivePort"
CHROMELAUNCH
  chmod +x "$launcher_app/Contents/MacOS/Chrome with Claude Code"
  touch "$launcher_app"
}

# Dock helper: delete any :persistent-apps entry whose _CFURLString == $1.
_dock_apps_remove_url() {
  local target="$1"
  local plist="$HOME/Library/Preferences/com.apple.dock.plist"
  [ -f "$plist" ] || return 0
  local i=0
  while /usr/libexec/PlistBuddy -c "Print :persistent-apps:$i" "$plist" >/dev/null 2>&1; do
    i=$((i+1))
  done
  i=$((i-1))
  while [ $i -ge 0 ]; do
    local u
    u=$(/usr/libexec/PlistBuddy -c "Print :persistent-apps:$i:tile-data:file-data:_CFURLString" "$plist" 2>/dev/null || true)
    if [ "$u" = "$target" ]; then
      /usr/libexec/PlistBuddy -c "Delete :persistent-apps:$i" "$plist" 2>/dev/null || true
    fi
    i=$((i-1))
  done
  return 0
}

# Dock helper: prepend a new :persistent-apps entry at slot 0 for URL $1.
# Used in reverse order so final slot assignment lines up left-to-right.
# PlistBuddy prints to stderr on failure; we keep stderr visible so the
# install log captures why an insert didn't land.
_dock_apps_insert_at_zero() {
  local url="$1"
  local plist="$HOME/Library/Preferences/com.apple.dock.plist"
  echo "_dock_apps_insert_at_zero: $url"
  /usr/libexec/PlistBuddy -c "Add :persistent-apps:0 dict" "$plist" || true
  /usr/libexec/PlistBuddy -c "Add :persistent-apps:0:tile-data dict" "$plist" || true
  /usr/libexec/PlistBuddy -c "Add :persistent-apps:0:tile-data:file-data dict" "$plist" || true
  /usr/libexec/PlistBuddy -c "Add :persistent-apps:0:tile-data:file-data:_CFURLString string ${url}" "$plist" || true
  /usr/libexec/PlistBuddy -c "Add :persistent-apps:0:tile-data:file-data:_CFURLStringType integer 15" "$plist" || true
  /usr/libexec/PlistBuddy -c "Add :persistent-apps:0:tile-type string file-tile" "$plist" || true
  return 0
}

# Silent end-step: create ~/if workspace, point Finder there, pin to Dock,
# enable "New Terminal at Folder" in Finder right-click.
#
# Why ~/if and not ~/: running claude in ~ makes it enumerate Documents,
# Downloads, Photos Library, Reminders group-container, etc., which fires
# macOS TCC prompts ("Terminal wants to access…"). An empty work dir avoids
# all of that.
_configure_workspace() {
  [ "$OS" = "darwin" ] || return 0
  mkdir -p "$HOME/if"

  # Build IF Terminal.app — a Dock-pinnable launcher that opens a new
  # Terminal window cd'd to ~/if. Why a real .app bundle and not Terminal.app
  # itself: clicking Terminal.app's Dock icon when Terminal is already
  # running just focuses it (no new window). Why not a .command file: the
  # Dock shows the generic script icon and uses the filename as label —
  # unrecognizable. With our own .app we control both.
  local if_term="$HOME/Applications/IF Terminal.app"
  mkdir -p "$if_term/Contents/MacOS"
  mkdir -p "$if_term/Contents/Resources"

  # Copy Terminal.app's icon. Moved to /System/Applications in Catalina+;
  # fall back to the pre-Catalina location, then to mdfind if neither is
  # where we expect (e.g. future macOS layout changes).
  local term_icns=""
  for candidate in \
      "/System/Applications/Utilities/Terminal.app/Contents/Resources/Terminal.icns" \
      "/Applications/Utilities/Terminal.app/Contents/Resources/Terminal.icns" ; do
    if [ -f "$candidate" ]; then term_icns="$candidate"; break; fi
  done
  if [ -z "$term_icns" ]; then
    local term_app
    term_app=$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.Terminal'" 2>/dev/null | head -1)
    [ -n "$term_app" ] && [ -f "$term_app/Contents/Resources/Terminal.icns" ] \
      && term_icns="$term_app/Contents/Resources/Terminal.icns"
  fi
  [ -n "$term_icns" ] && cp "$term_icns" "$if_term/Contents/Resources/app.icns"

  cat > "$if_term/Contents/Info.plist" <<'IFTERMPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>IF Terminal</string>
  <key>CFBundleDisplayName</key>
  <string>IF Terminal</string>
  <key>CFBundleExecutable</key>
  <string>IF Terminal</string>
  <key>CFBundleIconFile</key>
  <string>app</string>
  <key>CFBundleIdentifier</key>
  <string>au.truffledog.if-terminal</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>10.15</string>
</dict>
</plist>
IFTERMPLIST

  # The "executable" just asks LaunchServices to open ~/if in Terminal.
  # Terminal always creates a new window when asked to open a folder, and
  # its shell starts cd'd to that folder. No AppleScript (no TCC prompts).
  cat > "$if_term/Contents/MacOS/IF Terminal" <<'IFTERMEXEC'
#!/bin/bash
open -a Terminal.app "$HOME/if"
IFTERMEXEC
  chmod +x "$if_term/Contents/MacOS/IF Terminal"
  # Bumping mtime forces LaunchServices/Dock to re-register the icon if we
  # rebuilt the bundle after a prior install.
  touch "$if_term"

  # Install "Claude Code at Folder" Finder right-click Quick Action.
  # The .workflow bundle was built once in Automator.app and zipped; we
  # unzip it into ~/Library/Services/ and the `pbs -update` below makes
  # it show up in the Finder right-click menu. rm -rf first so re-runs
  # pick up any content changes in the workflow.
  mkdir -p "$HOME/Library/Services"
  rm -rf "$HOME/Library/Services/Claude Code at Folder.workflow"
  local qa_zip; qa_zip=$(mktemp -u).zip
  if curl -fsSL https://truffledog.au/if-a-quick-action.zip -o "$qa_zip"; then
    unzip -q -o "$qa_zip" -d "$HOME/Library/Services/" || true
    rm -rf "$HOME/Library/Services/__MACOSX"
  fi
  rm -f "$qa_zip"

  # === Pass 1: all `defaults write` calls ===
  # These go to cfprefsd's in-memory cache, not directly to disk.

  # (A) New Finder windows default to ~/if — covers right-click New Folder
  #     + right-click New Terminal at Folder workflow.
  defaults write com.apple.finder NewWindowTarget -string "PfLo" 2>/dev/null || true
  defaults write com.apple.finder NewWindowTargetPath -string "file://$HOME/if/" 2>/dev/null || true

  # (B) Enable Finder right-click items:
  #       - system "New Terminal at Folder" (Terminal.app service)
  #       - our "Claude Code at Folder" quick action (runs via Automator)
  #     Automator-sourced services use "(null)" as their bundle slot in the
  #     pbs.plist key; NSMessage is the workflow's runner method.
  defaults write pbs NSServicesStatus -dict-add \
    "com.apple.Terminal - Open Terminal at Folder - openTerminal" \
    '{ "enabled_context_menu" = 1; "enabled_services_menu" = 1;
       "presentation_modes" = { "ContextMenu" = 1; "ServicesMenu" = 1; }; }' \
    2>/dev/null || true
  defaults write pbs NSServicesStatus -dict-add \
    "(null) - Claude Code at Folder - runWorkflowAsService" \
    '{ "enabled_context_menu" = 1; "enabled_services_menu" = 1;
       "presentation_modes" = { "ContextMenu" = 1; "ServicesMenu" = 1; }; }' \
    2>/dev/null || true

  # === cfprefsd flush ===
  # Force cfprefsd to flush its cache to disk before we touch the dock plist
  # with PlistBuddy. Without this, PlistBuddy's Save overwrites the file
  # with its stale on-disk view, losing everything we just wrote with
  # `defaults`. killall sends SIGTERM → cfprefsd flushes then exits →
  # launchd respawns it; the brief sleep gives the file write time to land.
  killall cfprefsd 2>/dev/null || true
  sleep 0.3

  # === Pass 2: PlistBuddy edits on disk ===

  # (C) Dock left side, immediately right of Finder:
  #       slot 0 — Chrome with Claude Code (the debug-port-enabled launcher)
  #       slot 1 — IF Terminal (opens a new Terminal in ~/if)
  #     Pattern: remove any existing matches, then prepend at slot 0 in
  #     reverse order so final left-to-right ends up [chrome, term, ...rest].
  #     Also remove the legacy shell.command URL so upgrading installs
  #     don't leave a stale entry in the Dock.
  local url_chrome="file://$HOME/Applications/Chrome%20with%20Claude%20Code.app/"
  local url_term="file://$HOME/Applications/IF%20Terminal.app/"
  local url_shell_legacy="file://$HOME/.if/bin/shell.command"
  _dock_apps_remove_url "$url_chrome"
  _dock_apps_remove_url "$url_term"
  _dock_apps_remove_url "$url_shell_legacy"
  _dock_apps_insert_at_zero "$url_term"
  _dock_apps_insert_at_zero "$url_chrome"

  # Apply changes.
  # Don't killall Finder — relaunch steals focus from Terminal (Claude's
  # first-run "Trust this folder" prompt becomes unreachable). The new
  # prefs apply to the next Cmd-N / next Finder launch, which is fine.
  killall Dock 2>/dev/null || true
  /System/Library/CoreServices/pbs -update 2>/dev/null || true
}

# Silent end-step: pre-configure Terminal.app so Option-Enter inserts a
# newline (what "shift-enter" in Claude Code actually needs). Writes to the
# user's active Terminal profile.
_configure_terminal() {
  [ "$OS" = "darwin" ] || return 0
  local plist="$HOME/Library/Preferences/com.apple.Terminal.plist"
  [ -f "$plist" ] || return 0
  [ -f "${plist}.bak" ] || cp "$plist" "${plist}.bak"
  local profile
  profile=$(defaults read com.apple.Terminal "Default Window Settings" 2>/dev/null || echo "Basic")
  plutil -insert  "Window Settings.${profile}.useOptionAsMetaKey" -bool YES "$plist" 2>/dev/null \
    || plutil -replace "Window Settings.${profile}.useOptionAsMetaKey" -bool YES "$plist" 2>/dev/null \
    || true
}

# Silent end-step: write our marker-fenced block to ~/.zshrc.
_write_zshrc() {
  local zshrc="$HOME/.zshrc"
  [ -e "$zshrc" ] || touch "$zshrc"
  if [ -s "$zshrc" ]; then
    local ts; ts=$(date +%Y%m%d-%H%M)
    cp "$zshrc" "${zshrc}.${ts}.bak"
  fi
  if grep -qF "$MARKER_START" "$zshrc"; then
    local tmpf; tmpf=$(mktemp)
    awk -v s="$MARKER_START" -v e="$MARKER_END" '
      $0 == s { skip=1; next }
      $0 == e { skip=0; next }
      !skip  { print }
    ' "$zshrc" > "$tmpf"
    mv "$tmpf" "$zshrc"
  fi
  local jh_value
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
    printf '[ -d "$HOME/.if/git/lib" ] && export DYLD_FALLBACK_LIBRARY_PATH="$HOME/.if/git/lib:$HOME/lib:/usr/local/lib:/usr/lib"\n'
    printf 'export JAVA_HOME="%s"\n' "$jh_value"
    printf 'export PATH="$JAVA_HOME/bin:$PATH"\n'
    printf 'export NPM_CONFIG_CACHE="$HOME/.if/npm-cache"\n'
    printf 'export CLAUDE_CONFIG_DIR="$HOME/.if/claude-config"\n'
    printf "alias cc='claude --dangerously-skip-permissions'\n"
    printf "alias ccc='claude --dangerously-skip-permissions --continue'\n"
    printf "alias ccr='claude --dangerously-skip-permissions --resume'\n"
    printf '%s\n' "$MARKER_END"
  } >> "$zshrc"
}

# ==========================================================================
# UI — draw the reusable list, prompt, and update rows in place
# ==========================================================================

ITEMS=(
  "node 22"
  "java 21"
  "git"
  "gh"
  "claude code [in YOLO mode]"
  "chrome [connected to Claude]"
)
HAVE=(
  "$have_node22"
  "$have_java21"
  "$have_git"
  "$have_gh"
  "$have_claude"
  "$have_chrome"
)
N=${#ITEMS[@]}

# draw_row "$i" "$state"  — state: installed | installing | pending
draw_row() {
  local i="$1" state="$2"
  local icon text color
  case "$state" in
    installed)  icon="${C_GRN}✓${C_RST}";  text="installed";    color="$C_GRN"  ;;
    installing) icon="${C_GRAY}⋯${C_RST}"; text="installing..."; color="$C_GRAY" ;;
    pending)    icon="${C_GRAY}○${C_RST}"; text="will install"; color="$C_GRAY" ;;
  esac
  printf '  %b  %-34s %b%s%b\n' "$icon" "${ITEMS[$i]}" "$color" "$text" "$C_RST"
}

# update_row "$i" "$state" — move cursor up to row i, re-draw, move back.
# Assumes cursor is at "line after the last row" before each call, and
# leaves it there afterwards.
update_row() {
  local i="$1" state="$2"
  local up=$((N - i))
  printf '\033[%dA\r\033[K' "$up"
  draw_row "$i" "$state"
  local down=$((N - i - 1))
  # Using `if ... fi` rather than `[ ... ] && ...` — the latter's compound
  # exit is non-zero when the test fails, which under `set -e` would cause
  # the caller to exit. Nasty for the LAST row (down=0).
  if [ "$down" -gt 0 ]; then
    printf '\033[%dB\r' "$down"
  fi
}

# run_install "$i" "_install_fn" — only runs if the item isn't already
# marked have=true. Shows "installing..." then "installed".
run_install() {
  local i="$1" fn="$2"
  [ "${HAVE[$i]}" = "true" ] && return 0
  update_row "$i" "installing"
  echo "[$(date +%H:%M:%S)] run_install: about to exec '$fn'" >> "$INSTALL_LOG"
  local rc=0
  "$fn" >> "$INSTALL_LOG" 2>&1 || rc=$?
  echo "[$(date +%H:%M:%S)] run_install: '$fn' returned rc=$rc" >> "$INSTALL_LOG"
  if [ "$rc" -eq 0 ]; then
    update_row "$i" "installed"
  else
    update_row "$i" "pending"
    echo ""
    echo "install of ${ITEMS[$i]} failed (rc=$rc) — see $INSTALL_LOG" >&2
    exit 1
  fi
}

# --- Banner ---
cat <<BANNER

  ┌─────────────────────────────────┐
  │     if — impatient futurist     │
  └─────────────────────────────────┘

We're about to install whatever's missing from:

BANNER

# --- Initial list (cursor ends on the line just below the last row) ---
for i in $(seq 0 $((N - 1))); do
  if [ "${HAVE[$i]}" = "true" ]; then
    draw_row "$i" "installed"
  else
    draw_row "$i" "pending"
  fi
done

# --- Short-circuit if everything already installed ---
all_installed=true
for h in "${HAVE[@]}"; do
  [ "$h" = "true" ] || { all_installed=false; break; }
done
if $all_installed; then
  say ""
  say "All dependencies already installed."
  exit 0
fi

# --- Prompt ---
echo ""
if ! prompt_yn "Proceed?" "Y"; then
  say "No changes made. Goodbye."
  exit 0
fi

# Wipe the prompt + blank line so cursor returns to "after list" position.
# Prompt added 2 lines (blank + prompt with Enter).
printf '\033[2A\033[J'

# --- Run installs (UI rows update in place) ---
run_install 0 _install_node
run_install 1 _install_java
run_install 2 _install_git
run_install 3 _install_gh
run_install 4 _install_claude
run_install 5 _install_chrome

# --- Silent end steps (no row, just do the work) ---
_configure_terminal  >> "$INSTALL_LOG" 2>&1
_configure_workspace >> "$INSTALL_LOG" 2>&1
_write_zshrc         >> "$INSTALL_LOG" 2>&1

echo ""
echo "Next steps:"
echo ""
# Step 1 — wait for return, then launch Chrome. Its welcome popup has a
# "Make Chrome the default browser" checkbox the user can action.
# </dev/tty so `read` sees the real terminal, not the curl|bash pipe.
printf '  • Set Chrome with Claude Code as default    %spress return%s\n' \
  "$C_GRAY" "$C_RST"
read -r _ </dev/tty 2>/dev/null || true

if [ "$OS" = "darwin" ] && [ -d "$HOME/Applications/Chrome with Claude Code.app" ]; then
  open "$HOME/Applications/Chrome with Claude Code.app" 2>/dev/null || true
fi

# Step 2 — tell the user to quit Terminal and relaunch via the Dock. We
# don't open a new window ourselves (the old exec-zsh trick broke pgrp;
# the newer 'open -a Terminal.app' trick left two windows on screen and
# confused people). IF Terminal on the Dock is now the one entry point.
echo ""
printf '  • Quit Terminal (Cmd-Q), then click %s on the left of the Dock\n' "$(bold 'IF Terminal')"
echo ""
