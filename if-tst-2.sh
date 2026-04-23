#!/bin/bash
#
# GCP project ID availability checker — live as you type.
# Uses the creds saved by if-tst.sh (~/.if/*.json).
#
# Usage (local, not yet pushed):
#   bash ~/_code/truffledog-website/if-tst-2.sh
#
set -e

eval "$(curl -fsSL https://truffledog.au/if-lib.sh)"

# --- JSON field extractor (handles pretty-printed JSON) ---
json_extract() {
  grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" | head -1 \
    | sed -E "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\1/"
}

# --- Locate the newest credentials file ---
CRED_FILE=$(ls -t ~/.if/*.json 2>/dev/null | head -1)
[ -z "$CRED_FILE" ] && die "No credentials in ~/.if/. Run if-tst.sh first."

CLIENT_ID=$(json_extract client_id < "$CRED_FILE")
CLIENT_SECRET=$(json_extract client_secret < "$CRED_FILE")
REFRESH_TOKEN=$(json_extract refresh_token < "$CRED_FILE")
EMAIL=$(json_extract email < "$CRED_FILE")

[ -z "$REFRESH_TOKEN" ] && die "No refresh_token in $CRED_FILE"

# --- Mint a fresh access token (refresh flow, silent) ---
REFRESH_RESP=$(curl -fsSL -X POST https://oauth2.googleapis.com/token \
  --data-urlencode "client_id=$CLIENT_ID" \
  --data-urlencode "client_secret=$CLIENT_SECRET" \
  --data-urlencode "refresh_token=$REFRESH_TOKEN" \
  --data-urlencode "grant_type=refresh_token" 2>&1) \
  || die "Token refresh failed: $REFRESH_RESP"

ACCESS_TOKEN=$(printf '%s' "$REFRESH_RESP" | json_extract access_token)
[ -z "$ACCESS_TOKEN" ] && die "No access_token after refresh — response: $REFRESH_RESP"

# --- Check a project ID's status via Cloud Resource Manager ---
# 200 → you can see it (you own or have access)
# 403 → it exists but you can't see it (someone else owns it)
# 404 → doesn't exist from your perspective (likely available, but might be
#       owned by someone else with hidden visibility; the only 100% sure check
#       is attempting to create)
create_project() {
  # Attempt projects.create. Returns:
  #   ok      — created successfully
  #   taken   — ALREADY_EXISTS (globally unique constraint hit)
  #   err<code> — other HTTP error
  local pid="$1"
  local tmp; tmp=$(mktemp)
  local code
  code=$(curl -s -o "$tmp" -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"projectId\":\"$pid\",\"displayName\":\"$pid\"}" \
    "https://cloudresourcemanager.googleapis.com/v3/projects")
  local body; body=$(cat "$tmp")
  rm -f "$tmp"

  printf '[%s] CREATE %s → %s\n%s\n---\n' "$(date +%H:%M:%S)" "$pid" "$code" "$body" >> /tmp/if-tst-2-check.log

  # Some errors come back synchronously; others come via a long-running operation.
  if [ "$code" = "409" ] || printf '%s' "$body" | grep -qi 'already.*exists\|ALREADY_EXISTS'; then
    printf '%s' "taken"; return
  fi
  if [ "$code" != "200" ] && [ "$code" != "201" ]; then
    printf 'err%s' "$code"; return
  fi

  # 200 → operation returned. Poll until done.
  local op_name
  op_name=$(printf '%s' "$body" | grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]+' | head -1 | sed 's/.*"\([^"]*\)$/\1/')
  if [ -z "$op_name" ]; then
    printf '%s' "err-noop"; return
  fi

  local i
  for i in $(seq 1 60); do
    sleep 1
    local resp
    resp=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
      "https://cloudresourcemanager.googleapis.com/v3/$op_name")
    printf '[%s] POLL %s\n%s\n---\n' "$(date +%H:%M:%S)" "$op_name" "$resp" >> /tmp/if-tst-2-check.log

    if printf '%s' "$resp" | grep -q '"done"[[:space:]]*:[[:space:]]*true'; then
      if printf '%s' "$resp" | grep -q '"error"'; then
        if printf '%s' "$resp" | grep -qi 'already.*exists\|ALREADY_EXISTS'; then
          printf '%s' "taken"; return
        fi
        printf '%s' "err-op-failed"; return
      fi
      printf '%s' "ok"; return
    fi
  done
  printf '%s' "timeout"
}

# --- Banner ---
cat <<BANNER

Choose a unique name for your project.

BANNER

# --- Reserve a line below the input for status display ---
printf "%s" "$PROMPT"
printf "\n"        # move to next line
tput el            # clear
printf "\n"        # leave the blank line, move down one more
tput cuu 2         # move back up to input line
tput hpa ${#PROMPT} # position at end of prompt

# --- Status line helpers ---
# Status aligns its icon with the first char of the project ID input
# (so ✗/✓ sits directly under the 'g' in 'gerbal...' etc).
PROMPT=""

show_status() {
  local msg="$1"
  tput sc
  tput cud 1
  tput hpa 0
  tput el
  tput hpa ${#PROMPT}
  printf "%b" "$msg"
  tput rc
}

status_red()   { show_status "${C_RED}✗ $1${C_RST}"; }
status_green() { show_status "${C_GRN}✓ $1${C_RST}"; }
status_gray()  { show_status "${C_GRAY}⋯ $1${C_RST}"; }
clear_status() { show_status ""; }

# --- Compute status reason from current input (syntax only) ---
# Returns: "ok" if valid, otherwise a short red-flag reason
syntax_reason() {
  local s="$1"
  if [ -z "$s" ]; then
    echo "empty"
  elif [ ${#s} -lt 6 ]; then
    echo "6 char min"
  elif [[ ! "$s" =~ ^[a-z] ]]; then
    echo "must start with letter"
  elif [[ "$s" =~ --+ ]]; then
    echo "no double dashes"
  elif [[ "$s" =~ -$ ]]; then
    echo "can't end with dash"
  elif [[ ! "$s" =~ ^[a-z0-9-]+$ ]]; then
    echo "lowercase letters, digits, dashes only"
  else
    echo "ok"
  fi
}

# --- Repaint status based on syntax of current input ---
# Only syntax-level feedback is shown while typing. Availability is only
# determined at Enter via create_project (the only 100% honest check).
repaint_status() {
  local s="$id"
  local reason
  reason=$(syntax_reason "$s")

  case "$reason" in
    empty) clear_status ;;
    ok)    clear_status ;;   # syntax-valid — no status until Enter
    *)     status_red "$reason" ;;
  esac
}

# --- Main input loop ---
id=""

cleanup_and_exit() {
  tput cud 2
  tput hpa 0
  echo
  echo "Final ID: $id"
  echo
  exit 0
}
trap cleanup_and_exit INT

# Debug log — each char read, and id state at each step
DBG=/tmp/if-tst-2-input.log
: > "$DBG"

while true; do
  char=""
  IFS= read -rsn1 char
  printf '[%s] read char=%q id_before=%q\n' "$(date +%H:%M:%S.%N)" "$char" "$id" >> "$DBG"

  if [ -z "$char" ]; then
    # Enter pressed — validate syntax, then attempt create
    reason=$(syntax_reason "$id")
    printf '[%s] ENTER id=%q reason=%s\n' "$(date +%H:%M:%S.%N)" "$id" "$reason" >> "$DBG"
    if [ "$reason" != "ok" ]; then
      continue
    fi

    status_gray "creating project..."
    printf '[%s] CREATE id=%q\n' "$(date +%H:%M:%S.%N)" "$id" >> "$DBG"
    result=$(create_project "$id")
    case "$result" in
      ok)      status_green "created"; break ;;
      taken)   status_red "taken" ;;
      timeout) status_red "timed out (still creating?)" ;;
      err*)    status_red "error (${result#err})" ;;
      *)       status_red "$result" ;;
    esac
    continue
  fi

  case "$char" in
    $'\x08'|$'\x7f')   # Backspace / Delete
      if [ ${#id} -gt 0 ]; then
        id="${id:0:${#id}-1}"
        printf "\b \b"
        repaint_status
        printf '[%s]   backspaced, id=%q\n' "$(date +%H:%M:%S.%N)" "$id" >> "$DBG"
      fi
      ;;
    *)
      if [[ "$char" =~ ^[a-z0-9-]$ ]] && [ ${#id} -lt 30 ]; then
        id+="$char"
        printf "%s" "$char"
        repaint_status
        printf '[%s]   appended %q, id=%q\n' "$(date +%H:%M:%S.%N)" "$char" "$id" >> "$DBG"
      else
        printf '[%s]   REJECTED char=%q (regex or length)\n' "$(date +%H:%M:%S.%N)" "$char" >> "$DBG"
      fi
      ;;
  esac
done

# Position cursor below status line
tput cud 2
tput hpa 0
echo
echo "Final ID: $id"
echo
