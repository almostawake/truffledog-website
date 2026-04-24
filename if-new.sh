#!/bin/bash
#
# Combined OAuth + project-create browser flow.
#
# Architecture:
#   - SECTION 1: HTTP server  — Perl-backed loopback server on 127.0.0.1.
#     Bash drives it via FIFOs + a synchronous request/response protocol.
#     Each piece is independent: server has no idea about OAuth or pages;
#     pages are just strings; dispatcher is a single while-loop.
#     (When this stabilises, move SECTION 1 to if-lib.sh.)
#   - SECTION 2: Small helpers (url coding, json, GCP create)
#   - SECTION 3: HTML templates
#   - SECTION 4: Dispatcher — the only place that cares about flow.
#
# Usage: bash ~/_code/truffledog-website/if-new.sh
#
set -e

eval "$(curl -fsSL https://truffledog.au/if-lib.sh)"

# =====================================================================
# SECTION 1 — HTTP server (Perl-backed)
# =====================================================================
#
# Protocol between bash and the Perl child:
#   Perl → bash (one line per request):   METHOD\tPATH_AND_QUERY\n
#   bash → Perl (for each request):       LENGTH\n<LENGTH bytes of body>
#
# Public API (call these from SECTION 4):
#   http_start       — picks a free port, launches server, sets HTTP_PORT
#   http_recv        — blocks until next request; sets REQ_METHOD, REQ_PATH, REQ_QUERY
#                      returns non-zero if server has closed
#   http_send <body> — sends body as the response
#   http_stop        — shuts down
#   http_log <msg>   — append to /tmp/if-new.log
#
# Everything written to the server's stderr (bind errors, request traces)
# also lands in /tmp/if-new.log.

HTTP_LOG="${HTTP_LOG:-/tmp/if-new.log}"

http_log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> "$HTTP_LOG"
}

http_pick_port() {
  local p
  HTTP_PORT=0
  for p in 50421 51284 52103 53117 54209 55327 56419 57531 58647 59761; do
    if ! lsof -i :$p >/dev/null 2>&1; then
      HTTP_PORT=$p; return
    fi
  done
  die "no free port"
}

# Perl source — inline so there's zero install footprint. Perl ships with
# every macOS. The server is synchronous (one request at a time), which
# matches our bash handler's single-threaded nature.
HTTP_PERL_SERVER='
use IO::Socket::INET;
$| = 1;
my $port = $ENV{PERL_PORT} or die "PERL_PORT not set";
my $sock = IO::Socket::INET->new(
    LocalAddr => "127.0.0.1", LocalPort => $port, Proto => "tcp",
    Listen => 5, ReuseAddr => 1,
) or die "bind failed on $port: $!";
print STDERR "listening on 127.0.0.1:$port\n";
while (my $client = $sock->accept) {
    $client->autoflush(1);
    my $req = "";
    while (sysread($client, my $buf, 4096)) {
        $req .= $buf;
        last if $req =~ /\r?\n\r?\n/;
    }
    next unless $req;
    my ($first) = split /\r?\n/, $req;
    my ($method, $path) = split / /, $first;
    $method //= "GET"; $path //= "/";
    print "$method\t$path\n";
    my $len_line = <STDIN>;
    last unless defined $len_line;
    chomp $len_line;
    my $body = "";
    if ($len_line =~ /^(\d+)$/) {
        my $n = $1; my $got = 0;
        while ($got < $n) {
            my $r = read(STDIN, my $buf, $n - $got);
            last unless $r;
            $body .= $buf; $got += $r;
        }
    }
    my $blen = length($body);
    print $client "HTTP/1.1 200 OK\r\n";
    print $client "Content-Type: text/html; charset=utf-8\r\n";
    print $client "Content-Length: $blen\r\n";
    print $client "Connection: close\r\n\r\n";
    print $client $body;
    close $client;
    print STDERR "served $method $path ($blen bytes)\n";
}
'

http_start() {
  : > "$HTTP_LOG"
  http_pick_port
  HTTP_IN=$(mktemp -u);  mkfifo "$HTTP_IN"
  HTTP_OUT=$(mktemp -u); mkfifo "$HTTP_OUT"
  # Open r/w on both FIFOs so neither end blocks at open time.
  exec 8<>"$HTTP_IN"
  exec 7<>"$HTTP_OUT"
  PERL_PORT="$HTTP_PORT" perl -e "$HTTP_PERL_SERVER" < "$HTTP_IN" > "$HTTP_OUT" 2>> "$HTTP_LOG" &
  HTTP_PID=$!
  http_log "server pid=$HTTP_PID port=$HTTP_PORT"
  sleep 0.3
}

http_recv() {
  IFS=$'\t' read -r REQ_METHOD REQ_PATH_QUERY <&7 || return 1
  REQ_PATH="${REQ_PATH_QUERY%%\?*}"
  if [[ "$REQ_PATH_QUERY" == *\?* ]]; then
    REQ_QUERY="${REQ_PATH_QUERY#*\?}"
  else
    REQ_QUERY=""
  fi
  http_log "recv $REQ_METHOD $REQ_PATH_QUERY"
}

http_send() {
  local body="$1"
  local bytes
  bytes=$(printf '%s' "$body" | wc -c | tr -d ' ')
  printf '%d\n' "$bytes" >&8
  printf '%s' "$body" >&8
  http_log "send $bytes bytes"
}

http_stop() {
  exec 7<&- 2>/dev/null || true
  exec 8>&- 2>/dev/null || true
  kill "$HTTP_PID" 2>/dev/null || true
  wait "$HTTP_PID" 2>/dev/null || true
  rm -f "$HTTP_IN" "$HTTP_OUT"
  http_log "server stopped"
}

# =====================================================================
# SECTION 2 — small helpers
# =====================================================================

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
  grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" | head -1 \
    | sed -E "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\1/"
}

query_param() {
  # $1 = query string, $2 = param name → prints raw (url-encoded) value
  printf '%s' "$1" | grep -oE "(^|&)$2=[^&]*" | head -1 | sed -E "s/^&?$2=//"
}

# Create a GCP project and wait for the long-running op. Prints one of:
#   ok | taken | timeout | err<code>
create_project() {
  local pid="$1"
  local tmp; tmp=$(mktemp)
  local code
  code=$(curl -s -o "$tmp" -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"projectId\":\"$pid\",\"displayName\":\"$pid\"}" \
    "https://cloudresourcemanager.googleapis.com/v3/projects")
  local body; body=$(cat "$tmp"); rm -f "$tmp"
  http_log "create_project $pid → HTTP $code"

  if [ "$code" = "409" ] || printf '%s' "$body" | grep -qi 'already.*exists\|ALREADY_EXISTS'; then
    printf '%s' "taken"; return
  fi
  if [ "$code" != "200" ] && [ "$code" != "201" ]; then
    printf 'err%s' "$code"; return
  fi

  local op_name
  op_name=$(printf '%s' "$body" | grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]+' | head -1 | sed 's/.*"\([^"]*\)$/\1/')
  [ -z "$op_name" ] && { printf '%s' "err-noop"; return; }

  local i resp
  for i in $(seq 1 60); do
    sleep 1
    resp=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
      "https://cloudresourcemanager.googleapis.com/v3/$op_name")
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

# =====================================================================
# SECTION 3 — HTML templates
# =====================================================================

build_explainer_html() {
  local auth_url="$1"
  cat <<HTML
<!doctype html><html><head><meta charset="utf-8"><title>Sign in to Google</title>
<style>
 body{font-family:system-ui,sans-serif;max-width:560px;margin:3em auto;padding:0 1.5em;color:#333;line-height:1.55}
 h1{font-size:1.4em;margin-bottom:.4em}
 h2{font-size:.82em;margin-top:1.8em;margin-bottom:.3em;color:#555;letter-spacing:.04em;text-transform:uppercase}
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
You can revoke access any time at <a href="https://myaccount.google.com/permissions">myaccount.google.com/permissions</a>.
</p>
<div class="actions" id="actions">
  <a class="btn primary" href="$auth_url">Continue</a>
  <a class="btn secondary" href="#" id="cancel">Cancel</a>
</div>
<div id="cancelled" style="display:none">
  <h1>No worries, we hope to see you back soon!</h1>
  <p class="small">Feel free to close this browser tab now.</p>
</div>
<script>
document.getElementById('cancel').addEventListener('click', function(e){
  e.preventDefault();
  fetch('/?cancelled=1').catch(function(){});
  document.querySelector('body').innerHTML = document.getElementById('cancelled').innerHTML;
});
</script>
</body></html>
HTML
}

build_continue_html() {
  local email="$1"
  cat <<HTML
<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="refresh" content="3;url=/">
<title>Signed in</title>
<style>
 body{font-family:system-ui,sans-serif;max-width:560px;margin:3em auto;padding:0 1.5em;color:#333;line-height:1.55}
 h1{font-size:1.4em;margin-bottom:.4em;color:#0a7}
 p.small{color:#888;font-size:.9em;margin-top:1.8em}
</style></head><body>
<h1>✓ Signed in</h1>
<p>Signed in as <b>$email</b>. Continuing to project creation…</p>
<p class="small">This page will advance automatically.</p>
</body></html>
HTML
}

build_form_html() {
  # $1 = just_failed_msg (HTML, e.g. "<b>werner</b> is taken") or empty
  # $2 = just_failed_name (plain text, for moving into tried list)
  # $3..  = tried names (earlier failures, not including just_failed)
  local jf_msg="$1" jf_name="$2"
  shift 2 || true
  local tried=("$@")

  local jf_html=""
  if [ -n "$jf_msg" ]; then
    # data-name lets JS pick it up and move to tried list when user types
    jf_html="<div id=\"just-failed\" class=\"err\" data-name=\"$jf_name\">✗ $jf_msg</div>"
  fi

  local tried_joined="" t
  for t in "${tried[@]}"; do
    if [ -z "$tried_joined" ]; then tried_joined="$t"; else tried_joined="$tried_joined, $t"; fi
  done
  local tried_html=""
  if [ -n "$tried_joined" ]; then
    tried_html="<div id=\"tried\" class=\"gray\" style=\"margin-top:.8em;font-size:.9em\">Names tried so far: $tried_joined</div>"
  fi

  cat <<HTML
<!doctype html><html><head><meta charset="utf-8"><title>Name your project</title>
<style>
 body{font-family:system-ui,sans-serif;max-width:560px;margin:3em auto;padding:0 1.5em;color:#333;line-height:1.55}
 h1{font-size:1.4em;margin-bottom:.4em}
 input[type=text]{width:100%;box-sizing:border-box;padding:.7em 1em;font-size:1em;font-family:ui-monospace,monospace;border:1px solid #ccc;border-radius:6px;margin-top:.3em}
 input[type=text]:focus{outline:2px solid #1a73e8;outline-offset:-1px;border-color:transparent}
 #status, #just-failed { margin:.35em 0; font-size:.95em }
 #status > div, #just-failed { line-height:1.4 }
 .ok{color:#0a7}.err{color:#b33}.gray{color:#888}
 button{padding:.65em 1.4em;font-size:1em;border:0;border-radius:6px;background:#1a73e8;color:#fff;cursor:pointer;font-weight:500;margin-top:.8em}
 button:disabled{background:#bbb;cursor:not-allowed}
 p.hint{color:#888;font-size:.9em}
</style></head><body>
<h1>Name your project</h1>
<p class="hint">6–30 chars, lowercase letters/digits/dashes, starts with a letter.</p>
<p class="hint">The name has to be unique across every Google Cloud project in the world, so it may take a few attempts to find one that’s free — that’s normal.</p>
<form method="GET" action="/">
  <input type="text" name="project_id" id="id" autocomplete="off" autofocus spellcheck="false" maxlength="30" required>
  <div id="status"></div>
  ${jf_html}
  <div id="tried-container">${tried_html}</div>
  <button type="submit" id="submit" disabled>Create project</button>
</form>
<script>
 const input=document.getElementById('id');
 const stat=document.getElementById('status');
 const submit=document.getElementById('submit');
 const jf=document.getElementById('just-failed');
 const triedContainer=document.getElementById('tried-container');

 function moveJustFailedToTried(){
   if(!jf) return;
   const name=jf.dataset.name||'';
   jf.remove();
   if(!name) return;
   let tried=document.getElementById('tried');
   if(tried){
     tried.textContent = tried.textContent + ', ' + name;
   } else {
     tried=document.createElement('div');
     tried.id='tried';
     tried.className='gray';
     tried.style.cssText='margin-top:.8em;font-size:.9em';
     tried.textContent='Names tried so far: '+name;
     triedContainer.appendChild(tried);
   }
 }

 function check(){
   const v=input.value;
   const errs=[];
   if(v && v.length<6) errs.push('6 char min');
   if(v.length>30) errs.push('30 char max');
   if(v && !/^[a-z]/.test(v)) errs.push('must start with a letter');
   if(/--/.test(v)) errs.push('no double dashes');
   if(/-\$/.test(v)) errs.push('cannot end with a dash');
   if(v && !/^[a-z0-9-]+\$/.test(v)) errs.push('lowercase letters, digits, dashes only');

   const ok = v.length>=6 && errs.length===0;
   if(!v){
     stat.innerHTML='';
   } else if(ok){
     stat.innerHTML='<div class=gray>ready to create</div>';
   } else {
     stat.innerHTML=errs.map(e=>'<div class=err>✗ '+e+'</div>').join('');
   }
   submit.disabled=!ok;
 }

 input.addEventListener('input',()=>{ moveJustFailedToTried(); check(); });
 check();
 document.querySelector('form').addEventListener('submit',()=>{
   stat.innerHTML='<div class=gray>⋯ creating project (this can take a few seconds)…</div>';
   submit.disabled=true;
 });
</script>
</body></html>
HTML
}

build_success_html() {
  local pid="$1"
  cat <<HTML
<!doctype html><html><head><meta charset="utf-8"><title>Created</title>
<style>body{font-family:system-ui;padding:3em;max-width:32em;margin:auto;color:#333;line-height:1.55}.pid{font-family:ui-monospace,monospace;background:#f4f4f4;padding:.2em .5em;border-radius:4px}</style>
</head><body>
<h2 style="color:#0a7">✓ Project created</h2>
<p>Your new GCP project <span class="pid">$pid</span> is ready.</p>
<p style="color:#888">You can close this tab and return to the terminal.</p>
</body></html>
HTML
}

build_fatal_html() {
  local msg="$1"
  cat <<HTML
<!doctype html><html><head><meta charset="utf-8"><title>Error</title>
<style>body{font-family:system-ui;padding:3em;max-width:36em;margin:auto;color:#333;line-height:1.55}pre{background:#f4f4f4;padding:1em;border-radius:6px;overflow:auto}</style>
</head><body>
<h2 style="color:#b33">✗ $msg</h2>
<p>Check /tmp/if-new.log for details. You can close this tab.</p>
</body></html>
HTML
}

# =====================================================================
# SECTION 4 — Main dispatcher
# =====================================================================

CLIENT_ID="32555940559.apps.googleusercontent.com"
CLIENT_SECRET="ZmssLNjJy2998hD4CTg2ejr2"
SCOPE="openid email https://www.googleapis.com/auth/cloud-platform"

echo "Opening browser..."

http_start
trap http_stop EXIT

REDIRECT_URI="http://127.0.0.1:$HTTP_PORT"
SCOPE_ENC=$(urlencode "$SCOPE")
REDIRECT_ENC=$(urlencode "$REDIRECT_URI")
AUTH_URL="https://accounts.google.com/o/oauth2/auth?client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_ENC}&response_type=code&scope=${SCOPE_ENC}&access_type=offline&prompt=consent"

EXPLAINER_HTML=$(build_explainer_html "$AUTH_URL")

open "http://127.0.0.1:$HTTP_PORT/"

state="waiting_auth"
# Form state: the most recent failed attempt (shown as inline red, like
# a validation error) + a list of earlier failures (shown gray).
form_jf_msg=""      # HTML fragment like "<b>werner</b> is taken"
form_jf_name=""     # plain name, for JS to move to tried list on typing
tried_list=()
ACCESS_TOKEN=""
EMAIL=""

# Helper: after a failed create, shift the previous just-failed name into
# the tried list, then set the new just-failed. Caller sets form_jf_msg.
promote_last_failure_to_tried() {
  if [ -n "$form_jf_name" ]; then
    tried_list+=("$form_jf_name")
  fi
}

while http_recv; do
  # Ignore anything not on /
  if [ "$REQ_PATH" != "/" ]; then
    http_send ""
    continue
  fi

  case "$state" in

    waiting_auth)
      if [[ "$REQ_QUERY" == *cancelled=1* ]]; then
        http_send ""
        echo "Cancelled."
        break
      elif [[ "$REQ_QUERY" == *error=* ]]; then
        err=$(query_param "$REQ_QUERY" error)
        http_send "$(build_fatal_html "OAuth error: $err")"
        http_log "OAuth error: $err"
        break
      elif [[ "$REQ_QUERY" == *code=* ]]; then
        CODE_RAW=$(query_param "$REQ_QUERY" code)
        CODE=$(urldecode "$CODE_RAW")

        # Token exchange
        if ! TOKENS=$(curl -fsSL -X POST https://oauth2.googleapis.com/token \
            --data-urlencode "client_id=$CLIENT_ID" \
            --data-urlencode "client_secret=$CLIENT_SECRET" \
            --data-urlencode "code=$CODE" \
            --data-urlencode "redirect_uri=$REDIRECT_URI" \
            --data-urlencode "grant_type=authorization_code" 2>&1); then
          http_send "$(build_fatal_html "Token exchange failed")"
          http_log "token exchange failed: $TOKENS"
          break
        fi
        ACCESS_TOKEN=$(printf '%s' "$TOKENS" | json_extract access_token)
        if [ -z "$ACCESS_TOKEN" ]; then
          http_send "$(build_fatal_html "No access token in response")"
          break
        fi

        # Userinfo
        USERINFO=$(curl -fsSL -H "Authorization: Bearer $ACCESS_TOKEN" \
          https://www.googleapis.com/oauth2/v3/userinfo 2>&1) || true
        EMAIL=$(printf '%s' "$USERINFO" | json_extract email)
        [ -z "$EMAIL" ] && EMAIL="unknown"

        # Save creds under ~/.if/creds/ (dedicated subdir keeps the
        # top-level ~/.if clean for installed tooling; one creds file
        # per Google account, named by email).
        mkdir -p ~/.if/creds
        chmod 700 ~/.if ~/.if/creds
        CRED_PATH="$HOME/.if/creds/${EMAIL}.json"
        cat > "$CRED_PATH" <<JSON
{
  "email": "$EMAIL",
  "client_id": "$CLIENT_ID",
  "client_secret": "$CLIENT_SECRET",
  "tokens": $TOKENS
}
JSON
        chmod 600 "$CRED_PATH"
        echo "  ✓ Signed in as $EMAIL"

        http_send "$(build_continue_html "$EMAIL")"
        state="waiting_form"
      else
        # First hit of /
        http_send "$EXPLAINER_HTML"
      fi
      ;;

    waiting_form)
      if [[ "$REQ_QUERY" == *project_id=* ]]; then
        PID_RAW=$(query_param "$REQ_QUERY" project_id)
        PID=$(urldecode "$PID_RAW")
        echo "  → Attempting create: $PID"
        result=$(create_project "$PID")
        case "$result" in
          ok)
            http_send "$(build_success_html "$PID")"
            echo "  ✓ Created: $PID"
            break
            ;;
          taken)
            promote_last_failure_to_tried
            form_jf_name="$PID"
            form_jf_msg="<b>$PID</b> is taken"
            http_send "$(build_form_html "$form_jf_msg" "$form_jf_name" "${tried_list[@]}")"
            ;;
          timeout)
            promote_last_failure_to_tried
            form_jf_name="$PID"
            form_jf_msg="create timed out for <b>$PID</b>"
            http_send "$(build_form_html "$form_jf_msg" "$form_jf_name" "${tried_list[@]}")"
            ;;
          err*)
            promote_last_failure_to_tried
            form_jf_name="$PID"
            form_jf_msg="error creating <b>$PID</b> (code ${result#err})"
            http_send "$(build_form_html "$form_jf_msg" "$form_jf_name" "${tried_list[@]}")"
            ;;
          *)
            promote_last_failure_to_tried
            form_jf_name="$PID"
            form_jf_msg="unexpected result for <b>$PID</b>: $result"
            http_send "$(build_form_html "$form_jf_msg" "$form_jf_name" "${tried_list[@]}")"
            ;;
        esac
      else
        # Initial form GET or post-signin refresh
        http_send "$(build_form_html "$form_jf_msg" "$form_jf_name" "${tried_list[@]}")"
      fi
      ;;

  esac
done

echo ""
echo "Done."
echo ""
