#!/bin/zsh

# Set PATH, MANPATH, etc., for Homebrew.
eval "$(/opt/homebrew/bin/brew shellenv)"

# Custom binaries in ~/bin
export PATH="$PATH:~/bin"

# Set JAVA_HOME using macOS java_home utility
if [[ -x /usr/libexec/java_home ]]; then
  export JAVA_HOME=$(/usr/libexec/java_home)
fi
export PATH="$JAVA_HOME/bin:$PATH"

# Xcode Command Line Tools
export PATH="/Library/Developer/CommandLineTools/usr/bin:$PATH"

# Node Version Manager - Non-interactive safe version
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh" >/dev/null 2>&1

if [ -f .nvmrc ]; then
  NVMRC_CONTENT=$(cat .nvmrc)
  
  # Clean the version (remove 'v' prefix and 'lts/' prefix if present)
  CLEAN_VERSION=$(echo "$NVMRC_CONTENT" | sed 's/^v//' | sed 's/^lts\///')
  
  # Find matching versions
  if [ "$NVMRC_CONTENT" = "lts/*" ]; then
    # For lts/*, find the latest LTS version (even-numbered major versions)
    MATCHED_VERSION=$(ls "$NVM_DIR/versions/node" 2>/dev/null | grep -E '^v[0-9]+\.' | sed 's/^v//' | awk -F. '{if ($1 % 2 == 0) print}' | sort -V | tail -1)
  elif echo "$NVMRC_CONTENT" | grep -q "^lts/"; then
    # For specific LTS aliases
    case "$CLEAN_VERSION" in
      "jod") MAJOR="22" ;;
      "iron") MAJOR="20" ;;
      "hydrogen") MAJOR="18" ;;
      *) MAJOR="" ;;
    esac
    if [ -n "$MAJOR" ]; then
      MATCHED_VERSION=$(ls "$NVM_DIR/versions/node" 2>/dev/null | grep -E "^v${MAJOR}\." | sed 's/^v//' | sort -V | tail -1)
    fi
  else
    # Count dots to determine specificity
    DOT_COUNT=$(echo "$CLEAN_VERSION" | tr -cd '.' | wc -c)
    
    if [ "$DOT_COUNT" -eq 0 ]; then
      # Major only (e.g., "22") - match exactly major.anything
      MATCHED_VERSION=$(ls "$NVM_DIR/versions/node" 2>/dev/null | grep -E "^v${CLEAN_VERSION}\." | sed 's/^v//' | sort -V | tail -1)
    elif [ "$DOT_COUNT" -eq 1 ]; then
      # Major.minor (e.g., "22.1") - match exactly major.minor.anything
      MATCHED_VERSION=$(ls "$NVM_DIR/versions/node" 2>/dev/null | grep -E "^v${CLEAN_VERSION}\." | sed 's/^v//' | sort -V | tail -1)
    else
      # Full version (e.g., "22.1.0") - match exactly
      MATCHED_VERSION=$(ls "$NVM_DIR/versions/node" 2>/dev/null | grep -E "^v${CLEAN_VERSION}$" | sed 's/^v//')
    fi
  fi
  
  if [ -n "$MATCHED_VERSION" ] && [ -d "$NVM_DIR/versions/node/v$MATCHED_VERSION" ]; then
    export PATH="$NVM_DIR/versions/node/v$MATCHED_VERSION/bin:$PATH"
  fi
fi