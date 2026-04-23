#!/bin/bash
#
# Google OAuth test — pure bash + nc, no Python/Xcode required.
# Works on a truly vanilla macOS install (nothing pre-installed beyond
# what Apple ships by default).
#
# Usage (local, not yet pushed):
#   bash ~/_code/truffledog-website/if-tst.sh
#
# Future public URL:
#   curl -fsSL https://truffledog.au/if-tst.sh | bash
#
# CLAUDE EDIT NOTICE: When editing this file, bump ZSHRC_VERSION in
# zshrc-remote by 1 (only when pushing — local-only edits don't need it).
#
set -e

# Load shared helpers (colors, die, say)
eval "$(curl -fsSL https://truffledog.au/if-lib.sh)"

# --- Config ---
# gcloud's public OAuth client — baked into every gcloud install, pre-verified.
CLIENT_ID="32555940559.apps.googleusercontent.com"
CLIENT_SECRET="ZmssLNjJy2998hD4CTg2ejr2"

# Minimal scopes approved for gcloud's public client.
# (Gmail/Calendar/Drive/Sheets are blocked for this client — handled in
# a separate user-data flow we design later.)
SCOPE="openid email https://www.googleapis.com/auth/cloud-platform"

# --- Helpers ---

urlencode() {
  local s="$1" out="" c i
  for ((i=0; i<${#s}; i++)); do
    c="${s:$i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out+="$c" ;;
      ' ') out+='%20' ;;
      *) out+=$(printf '%%%02X' "'$c") ;;
    esac
  done
  printf '%s' "$out"
}

urldecode() {
  local s="${1//+/ }"
  printf '%b' "${s//%/\\x}"
}

json_extract() {
  # poor-man's JSON field extractor: $1=field name, reads stdin
  # Handles both compact and pretty-printed JSON (whitespace after colon).
  grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" | head -1 \
    | sed -E "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\1/"
}

# --- Pick a free port in ephemeral range ---
PORT=0
for p in 50421 51284 52103 53117 54209 55327 56419 57531 58647 59761; do
  if ! lsof -i :$p >/dev/null 2>&1; then
    PORT=$p
    break
  fi
done
[ $PORT -eq 0 ] && die "Couldn't find a free port in the 50000s"

REDIRECT_URI="http://127.0.0.1:$PORT"

# --- Build consent URL ---
SCOPE_ENC=$(urlencode "$SCOPE")
REDIRECT_ENC=$(urlencode "$REDIRECT_URI")
AUTH_URL="https://accounts.google.com/o/oauth2/auth?client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_ENC}&response_type=code&scope=${SCOPE_ENC}&access_type=offline&prompt=consent"

echo "Opening browser..."

# --- Page 1 (pre-consent explainer served from our loopback) ---
# shown when the browser first hits http://127.0.0.1:$PORT/
EXPLAINER_HTML=$(cat <<HTML
<!doctype html><html><head><meta charset="utf-8"><title>Sign in to Google</title>
<style>
 body{font-family:system-ui,sans-serif;max-width:560px;margin:3em auto;padding:0 1.5em;color:#333;line-height:1.55}
 h1{font-size:1.4em;margin-bottom:.4em}
 h2{font-size:1em;margin-top:1.8em;margin-bottom:.3em;color:#555;letter-spacing:.02em;text-transform:uppercase}
 ul{list-style:none;padding:0;margin:.3em 0}
 li{padding:.3em 0}
 .ok{color:#0a7}.no{color:#b33}
 .actions{margin-top:2em;display:flex;gap:.75em;align-items:center}
 a.btn{padding:.55em 1.1em;border-radius:6px;text-decoration:none;font-weight:500;display:inline-block}
 a.primary{background:#1a73e8;color:#fff}
 a.secondary{color:#666}
 p.small{color:#888;font-size:.9em;margin-top:1.8em}
 a{color:#1a73e8}
</style></head><body>
<h1>Sign in to Google</h1>
<p>The next page will ask you to sign in and approve the following:</p>
<h2>Will be requested</h2>
<ul>
  <li class="ok">✓ See which Google account is yours (email + profile)</li>
  <li class="ok">✓ Manage Google Cloud resources on your behalf<br><small style="color:#777">(create projects, enable APIs, deploy services — everything the template needs to set up and run your app)</small></li>
</ul>
<h2>Will NOT be requested</h2>
<ul>
  <li class="no">✗ Gmail, Drive, Calendar, Sheets, or any personal data</li>
  <li class="no">✗ Access to other Google accounts</li>
  <li class="no">✗ Any third-party services</li>
</ul>
<p class="small">
The consent screen will be branded <b>Google Cloud SDK</b> — Google’s own pre-verified OAuth app used by gcloud and many other tools. You can revoke access any time at <a href="https://myaccount.google.com/permissions">myaccount.google.com/permissions</a>.
</p>
<div class="actions">
  <a class="btn primary" href="$AUTH_URL">Continue</a>
  <a class="btn secondary" href="http://127.0.0.1:$PORT/?cancelled=1">Cancel</a>
</div>
</body></html>
HTML
)

# --- Page 2 (post-consent, shown after Google redirects back here) ---
SUCCESS_HTML='<!doctype html><html><body style="font-family:system-ui;padding:3em;max-width:32em;margin:auto;color:#333"><h2>Signed in.</h2><p>You can close this tab and return to the terminal.</p></body></html>'

CANCEL_HTML='<!doctype html><html><body style="font-family:system-ui;padding:3em;max-width:32em;margin:auto;color:#333"><h2>Cancelled.</h2><p>No changes made. You can close this tab.</p></body></html>'

# --- serve_once: feed one HTTP response to one nc connection ---
# $1 = body, $2 = file to capture the request into
serve_once() {
  local body="$1" out="$2"
  local fifo; fifo=$(mktemp -u); mkfifo "$fifo"
  (
    sleep 0.5
    printf 'HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\nContent-Length: %d\r\n\r\n%s' "${#body}" "$body"
  ) > "$fifo" &
  nc -l 127.0.0.1 $PORT < "$fifo" > "$out"
  rm -f "$fifo"
}

REQ1=$(mktemp)
REQ2=$(mktemp)
cleanup() { rm -f "$REQ1" "$REQ2"; }
trap cleanup EXIT

# Open the browser to our local explainer page FIRST (not straight to Google)
open "http://127.0.0.1:$PORT/"

# Round 1: serve the explainer page
serve_once "$EXPLAINER_HTML" "$REQ1"

# User now reads, clicks Continue → browser navigates to Google.
# Or clicks Cancel → browser navigates to our /?cancelled=1 URL.
# Either way, Round 2 catches the next request.

# Round 2: wait for the callback. Some browsers might make a favicon request
# between rounds — we loop until we see either ?code= or ?cancelled=.
while :; do
  serve_once "$SUCCESS_HTML" "$REQ2"
  if grep -q 'cancelled=1' "$REQ2"; then
    # Re-serve the cancel page and exit
    serve_once "$CANCEL_HTML" "$REQ2" 2>/dev/null || true
    echo "Cancelled."
    exit 0
  fi
  if grep -qE 'code=|error=' "$REQ2"; then
    break
  fi
  # Non-auth request (favicon, etc.) — keep listening.
done

# --- Parse the incoming request for the auth code ---
if grep -q 'error=' "$REQ2"; then
  ERR=$(grep -oE 'error=[^& ]+' "$REQ2" | head -1 | cut -d= -f2)
  die "OAuth error from Google: $ERR"
fi

CODE_RAW=$(grep -oE 'code=[^& ]+' "$REQ2" | head -1 | cut -d= -f2)
[ -z "$CODE_RAW" ] && die "No auth code captured — maybe the browser didn't redirect?"

CODE=$(urldecode "$CODE_RAW")

# --- Exchange code for tokens ---
echo "Exchanging code for tokens..."
TOKENS=$(curl -fsSL -X POST https://oauth2.googleapis.com/token \
  --data-urlencode "client_id=${CLIENT_ID}" \
  --data-urlencode "client_secret=${CLIENT_SECRET}" \
  --data-urlencode "code=${CODE}" \
  --data-urlencode "redirect_uri=${REDIRECT_URI}" \
  --data-urlencode "grant_type=authorization_code" 2>&1) \
  || die "Token exchange failed: $TOKENS"

# Always save raw response for debugging
echo "$TOKENS" > /tmp/if-tst-tokens-raw.json

ACCESS_TOKEN=$(printf '%s' "$TOKENS" | json_extract access_token)
[ -z "$ACCESS_TOKEN" ] && die "No access_token in response — see /tmp/if-tst-tokens-raw.json"

# --- Get user email via userinfo endpoint ---
# More reliable than JWT decoding — works whenever the granted scopes
# include any of: openid, email, profile, or cloud-platform (which
# implicitly covers identity endpoints).
echo "Fetching user info..."
USERINFO=$(curl -fsSL -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  https://www.googleapis.com/oauth2/v3/userinfo 2>&1) \
  || die "userinfo request failed: $USERINFO"

EMAIL=$(printf '%s' "$USERINFO" | json_extract email)
[ -z "$EMAIL" ] && EMAIL="unknown"

# --- Save credentials ---
mkdir -p ~/.if
chmod 700 ~/.if
CRED_PATH="$HOME/.if/${EMAIL}.json"

# Wrap the tokens plus client creds and email in one self-contained JSON
cat > "$CRED_PATH" <<JSON
{
  "email": "${EMAIL}",
  "client_id": "${CLIENT_ID}",
  "client_secret": "${CLIENT_SECRET}",
  "tokens": ${TOKENS}
}
JSON
chmod 600 "$CRED_PATH"

# --- Report ---
SCOPES_GRANTED=$(printf '%s' "$TOKENS" | json_extract scope)
SCOPE_COUNT=$(printf '%s' "$SCOPES_GRANTED" | tr ' ' '\n' | wc -l | tr -d ' ')

echo ""
echo "  ✓ Email:     ${EMAIL}"
echo "  ✓ Saved to:  ${CRED_PATH}"
echo "  ✓ Scopes (${SCOPE_COUNT}):"
for s in $SCOPES_GRANTED; do
  echo "      - $s"
done
echo ""
echo "Done."
echo ""
