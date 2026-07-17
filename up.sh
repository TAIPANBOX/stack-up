#!/usr/bin/env bash
#
# stack-up: run the open TAIPANBOX agent-governance stack locally, natively,
# with no Docker, and open its money-plane dashboard in your browser.
#
# One command builds (or reuses) the service binaries from source, starts them
# on a fixed loopback port map, waits for each to report healthy, prints a
# one-click dashboard link, and holds until you press Ctrl-C, at which point it
# stops cleanly with no orphaned processes.
#
# What it starts by default (everything binds 127.0.0.1 only):
#
#   tokenfuse-gateway   :4100   budget-enforcement proxy (OpenAI-compatible)
#   tokenfuse-cloud     :8080   money-plane control API (dev credential)
#   dashboard           :3000   the money-plane dashboard (static, in a browser)
#   wardryx             :8090   policy decision point (seeded demo policy)
#   idryx               :8081   identity/access graph (its own :8080 collides)
#
# Flags:
#   --only money        just the money plane (gateway + cloud + dashboard)
#   --no-dashboard      skip building/serving the dashboard
#   --no-demo           do not seed the short demo dataset into cloud
#   --workspace <dir>   look here for sibling checkouts before cloning
#                       (default: the directory this repo sits in)
#   -h, --help          show this and exit
#
# This is a local sandbox and a dev quickstart, not a production deployment.
# See README.md for the security notes and how to send it real traffic.
#
# Apache-2.0. Part of https://github.com/TAIPANBOX

set -uo pipefail

# --------------------------------------------------------------------------
# Constants and layout
# --------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GH="https://github.com/TAIPANBOX"

STACK_UP_HOME="${STACK_UP_HOME:-$HOME/.stack-up}"
BIN_DIR="$STACK_UP_HOME/bin"
EVENTS_DIR="$STACK_UP_HOME/events"
LOGS_DIR="$STACK_UP_HOME/logs"
PIDS_DIR="$STACK_UP_HOME/pids"
REPOS_DIR="$STACK_UP_HOME/repos"
POLICY_FILE="$STACK_UP_HOME/wardryx-policy.yaml"
EVENTS_FILE="$EVENTS_DIR/tokenfuse.ndjson"

GATEWAY_PORT=4100
CLOUD_PORT=8080
DASH_PORT=3000
WARDRYX_PORT=8090
IDRYX_PORT=8081

# --------------------------------------------------------------------------
# Options
# --------------------------------------------------------------------------

ONLY_MONEY=0
NO_DASHBOARD=0
NO_DEMO=0
WORKSPACE="${STACK_UP_WORKSPACE:-$(dirname "$SCRIPT_DIR")}"

usage() { sed -n '3,33p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --only)
      shift
      [ "${1:-}" = "money" ] || { echo "stack-up: --only takes 'money'" >&2; exit 2; }
      ONLY_MONEY=1 ;;
    --only=money) ONLY_MONEY=1 ;;
    --no-dashboard) NO_DASHBOARD=1 ;;
    --no-demo) NO_DEMO=1 ;;
    --workspace) shift; WORKSPACE="${1:-}"; [ -n "$WORKSPACE" ] || { echo "stack-up: --workspace needs a directory" >&2; exit 2; } ;;
    -h|--help) usage; exit 0 ;;
    *) echo "stack-up: unknown option '$1' (try --help)" >&2; exit 2 ;;
  esac
  shift
done

# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------

log()  { printf '\033[1;36m[stack-up]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[stack-up]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[stack-up] error:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# port_busy <port> -> 0 (true) if something is already listening
port_busy() {
  if have lsof; then
    lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  elif have nc; then
    nc -z 127.0.0.1 "$1" >/dev/null 2>&1
  else
    curl -fsS -o /dev/null "http://127.0.0.1:$1/" 2>/dev/null
  fi
}

# stale_paths <marker> <path...> -> 0 (true=rebuild) if marker missing or any
# path is newer than it. Roots are given explicitly so we never walk target/
# or node_modules.
stale_paths() {
  local marker="$1"; shift
  [ -f "$marker" ] || return 0
  local hit
  hit="$(find "$@" -newer "$marker" 2>/dev/null | head -1)"
  [ -n "$hit" ]
}

# rand_hex <bytes> -> hex string of 2*bytes chars
rand_hex() {
  if have openssl; then
    openssl rand -hex "$1" 2>/dev/null && return 0
  fi
  # Fallback: /dev/urandom. Own subshell so the SIGPIPE from head does not
  # trip the caller's pipefail.
  ( set +o pipefail; LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c $(( $1 * 2 )) )
}

# locate_repo <canonical-lowercase-name> [alt-casing...] -> prints repo path.
# Reuses a sibling checkout under $WORKSPACE if present (never modifies it,
# only reads and runs its own build tool); otherwise shallow-clones it.
locate_repo() {
  local name="$1"; shift
  local cand alt
  cand="$WORKSPACE/$name"
  if [ -d "$cand" ]; then echo "$cand"; return 0; fi
  for alt in "$@"; do
    cand="$WORKSPACE/$alt"
    if [ -d "$cand" ]; then echo "$cand"; return 0; fi
  done
  cand="$REPOS_DIR/$name"
  if [ ! -d "$cand/.git" ]; then
    log "cloning $name from $GH/$name ..." >&2
    git clone --depth 1 "$GH/$name.git" "$cand" >&2 || return 1
  fi
  echo "$cand"
}

# --------------------------------------------------------------------------
# Process tracking + clean teardown
# --------------------------------------------------------------------------
# Each service is a single process. We record its PID (and the signal it wants
# for a graceful stop) and only ever signal those recorded PIDs, never a PID
# discovered by scanning ps/lsof.

STARTED=()   # entries: "name:pid:SIGNAL"

register() {  # register <name> <pid> <signal>
  STARTED+=("$1:$2:$3")
  echo "$2 $3" > "$PIDS_DIR/$1.pid"
}

cleanup() {
  trap - INT TERM EXIT
  [ "${#STARTED[@]}" -eq 0 ] && exit 0
  echo
  log "stopping ..."
  local i entry name pid sig
  for (( i=${#STARTED[@]}-1 ; i>=0 ; i-- )); do
    entry="${STARTED[$i]}"
    name="${entry%%:*}"; pid="${entry#*:}"; sig="${pid##*:}"; pid="${pid%%:*}"
    if kill -0 "$pid" 2>/dev/null; then
      kill "-$sig" "$pid" 2>/dev/null
    fi
  done
  # Give them a moment, then escalate anything still alive to SIGKILL.
  local waited=0
  while [ "$waited" -lt 10 ]; do
    local alive=0
    for entry in "${STARTED[@]}"; do
      pid="${entry#*:}"; pid="${pid%%:*}"
      kill -0 "$pid" 2>/dev/null && alive=1
    done
    [ "$alive" -eq 0 ] && break
    sleep 1; waited=$((waited+1))
  done
  for entry in "${STARTED[@]}"; do
    name="${entry%%:*}"; pid="${entry#*:}"; pid="${pid%%:*}"
    if kill -0 "$pid" 2>/dev/null; then
      warn "$name (pid $pid) ignored the stop signal; sending SIGKILL"
      kill -KILL "$pid" 2>/dev/null
    fi
    rm -f "$PIDS_DIR/$name.pid"
  done
  log "stopped."
  exit 0
}

# wait_health <name> <port> <pid> [path] [timeout]
wait_health() {
  local name="$1" port="$2" pid="$3" path="${4:-/healthz}" timeout="${5:-90}"
  local i=0
  while [ "$i" -lt "$timeout" ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      warn "$name exited before becoming healthy; see $LOGS_DIR/$name.log"
      return 1
    fi
    if curl -fsS -o /dev/null "http://127.0.0.1:$port$path" 2>/dev/null; then
      return 0
    fi
    sleep 1; i=$((i+1))
  done
  warn "$name did not answer $path on :$port within ${timeout}s; see $LOGS_DIR/$name.log"
  return 1
}

# seed_demo: POST a short, clearly-labeled demo dataset to cloud's ungated
# /v1/ingest so the dashboard has something live to show on first open. Cloud
# runs in-memory here (no TOKENFUSE_CLOUD_DATA), so this is fresh every run and
# nothing is written to disk. Two synthetic runs under agent://demo.local/*.
seed_demo() {
  local now recs i off dec
  now=$(( $(date +%s) * 1000 ))
  recs=""
  for i in 1 2 3 4 5 6; do
    off=$(( (7 - i) * 60000 ))
    recs="$recs{\"ts_millis\":$(( now - off )),\"run_id\":\"demo-support-bot\",\"model\":\"gpt-4o-mini\",\"decision\":\"allow\",\"input_tokens\":$(( 800 + i * 50 )),\"output_tokens\":$(( 200 + i * 20 )),\"cost_microusd\":$(( 1500 + i * 300 )),\"step\":$i,\"agent_id\":\"agent://demo.local/support/tier1\"},"
  done
  for i in 1 2 3 4; do
    off=$(( (5 - i) * 45000 ))
    dec="allow"; [ "$i" -eq 4 ] && dec="blocked"
    recs="$recs{\"ts_millis\":$(( now - off )),\"run_id\":\"demo-runaway\",\"model\":\"gpt-4o\",\"decision\":\"$dec\",\"input_tokens\":$(( 3000 + i * 400 )),\"output_tokens\":$(( 900 + i * 100 )),\"cost_microusd\":$(( 24000 + i * 6000 )),\"step\":$i,\"agent_id\":\"agent://demo.local/batch/crawler\"},"
  done
  recs="${recs%,}"
  if curl -fsS -o /dev/null -X POST "http://127.0.0.1:$CLOUD_PORT/v1/ingest" \
       -H "Authorization: Bearer devkey" -H "Content-Type: application/json" \
       -d "{\"records\":[$recs]}" 2>/dev/null; then
    log "seeded a short demo dataset into cloud (two runs) so the dashboard is not empty; pass --no-demo to skip"
  else
    warn "demo seed failed; the dashboard will just start empty."
  fi
}

# --------------------------------------------------------------------------
# Preflight
# --------------------------------------------------------------------------

log "workspace: $WORKSPACE   state: $STACK_UP_HOME"

have git   || die "git is required (to fetch the service repos)."
have cargo || die "cargo (Rust, stable) is required to build tokenfuse. Install from https://rustup.rs"
have curl  || die "curl is required for health checks."

WANT_DASHBOARD=1
[ "$NO_DASHBOARD" -eq 1 ] && WANT_DASHBOARD=0
if [ "$WANT_DASHBOARD" -eq 1 ]; then
  if ! have npm || ! have node; then
    warn "node/npm not found: skipping the dashboard (the API on :$CLOUD_PORT still comes up)."
    WANT_DASHBOARD=0
  elif ! have python3; then
    warn "python3 not found: skipping the dashboard server (build tools present, but nothing to serve it)."
    WANT_DASHBOARD=0
  fi
fi

WANT_POLICY=1
WANT_IDENTITY=1
if [ "$ONLY_MONEY" -eq 1 ]; then
  WANT_POLICY=0; WANT_IDENTITY=0
elif ! have go; then
  warn "go not found: skipping wardryx + idryx (they are written in Go). Money plane still comes up."
  WANT_POLICY=0; WANT_IDENTITY=0
fi

# Mandatory ports must be free; optional ones are dropped if occupied.
port_busy "$GATEWAY_PORT" && die "port $GATEWAY_PORT (gateway) is already in use."
port_busy "$CLOUD_PORT"   && die "port $CLOUD_PORT (cloud) is already in use."
if [ "$WANT_DASHBOARD" -eq 1 ] && port_busy "$DASH_PORT"; then
  warn "port $DASH_PORT is busy: skipping the dashboard."
  WANT_DASHBOARD=0
fi
if [ "$WANT_POLICY" -eq 1 ] && port_busy "$WARDRYX_PORT"; then
  warn "port $WARDRYX_PORT is busy: skipping wardryx."
  WANT_POLICY=0
fi
if [ "$WANT_IDENTITY" -eq 1 ] && port_busy "$IDRYX_PORT"; then
  warn "port $IDRYX_PORT is busy: skipping idryx."
  WANT_IDENTITY=0
fi

mkdir -p "$BIN_DIR" "$EVENTS_DIR" "$LOGS_DIR" "$PIDS_DIR" "$REPOS_DIR"
: > "$EVENTS_FILE"

trap cleanup INT TERM EXIT

# --------------------------------------------------------------------------
# Build + start: tokenfuse gateway + cloud (mandatory)
# --------------------------------------------------------------------------

TF_REPO="$(locate_repo tokenfuse)" || die "could not fetch tokenfuse."

GATEWAY_BIN="$BIN_DIR/tokenfuse-gateway"
CLOUD_BIN="$BIN_DIR/tokenfuse-cloud"
if [ -x "$GATEWAY_BIN" ] && [ -x "$CLOUD_BIN" ] \
   && ! stale_paths "$BIN_DIR/.marker-tokenfuse" "$TF_REPO/crates" "$TF_REPO/Cargo.toml" "$TF_REPO/Cargo.lock"; then
  log "tokenfuse: gateway + cloud up to date, skipping build"
else
  log "tokenfuse: building gateway + cloud (Rust release; the first build can take several minutes)"
  ( cd "$TF_REPO" && cargo build --release -p tokenfuse-gateway -p tokenfuse-cloud ) \
    || die "tokenfuse build failed."
  cp "$TF_REPO/target/release/tokenfuse" "$GATEWAY_BIN" || die "could not copy the gateway binary."
  cp "$TF_REPO/target/release/tokenfuse-cloud" "$CLOUD_BIN" || die "could not copy the cloud binary."
  : > "$BIN_DIR/.marker-tokenfuse"
fi

# Prepare wardryx wiring before the gateway starts, so the gateway can consult
# it from the moment it comes up (matches the taipan ordering). If wardryx then
# fails to start, the gateway fails open (its default), so this is safe.
WARDRYX_URL=""
if [ "$WANT_POLICY" -eq 1 ]; then
  WARDRYX_URL="http://127.0.0.1:$WARDRYX_PORT"
  cat > "$POLICY_FILE" <<'YAML'
# Seeded by stack-up. Scoped to the mockryx fire-drill rehearsal identities
# only (agent://mockryx.local/*) so it never governs your own agents. Replace
# this file, or point wardryx at your own, for anything beyond a demo.
- name: stack-up-demo-require-human-approval
  target: "agent://mockryx.local/*"
  require_human_above_usd: 1.0
- name: stack-up-demo-deny-shell-exec
  target: "agent://mockryx.local/*"
  deny_tool:
    - shell_exec
YAML
  WARDRYX_APPROVAL_SECRET="$(rand_hex 32)"
fi

# gateway: enforce mode, agent-event export on, wardryx wired if enabled.
# SIGINT specifically on stop so its buffered Parquet trace flushes.
log "starting gateway on :$GATEWAY_PORT (enforce)"
if [ -n "$WARDRYX_URL" ]; then
  TOKENFUSE_ADDR="127.0.0.1:$GATEWAY_PORT" \
  TOKENFUSE_MODE="enforce" \
  TOKENFUSE_EVENTS_PATH="$EVENTS_FILE" \
  TOKENFUSE_DATA_DIR="$STACK_UP_HOME/traces/gateway" \
  TOKENFUSE_WARDRYX_MODE="enforce" \
  TOKENFUSE_WARDRYX_URL="$WARDRYX_URL" \
  TOKENFUSE_WARDRYX_KEY="devkey" \
  TOKENFUSE_WARDRYX_TIMEOUT_MS="2000" \
    "$GATEWAY_BIN" > "$LOGS_DIR/gateway.log" 2>&1 &
else
  TOKENFUSE_ADDR="127.0.0.1:$GATEWAY_PORT" \
  TOKENFUSE_MODE="enforce" \
  TOKENFUSE_EVENTS_PATH="$EVENTS_FILE" \
  TOKENFUSE_DATA_DIR="$STACK_UP_HOME/traces/gateway" \
    "$GATEWAY_BIN" > "$LOGS_DIR/gateway.log" 2>&1 &
fi
register gateway "$!" INT
wait_health gateway "$GATEWAY_PORT" "$!" || die "gateway did not come up."

# cloud: devkey mode. Empty TOKENFUSE_CLOUD_KEYS + ALLOW_DEVKEY=1 makes the
# literal bearer "devkey" valid, so the dashboard connects with one click.
log "starting cloud on :$CLOUD_PORT (dev credential)"
PORT="$CLOUD_PORT" \
TOKENFUSE_CLOUD_KEYS="" \
TOKENFUSE_CLOUD_ALLOW_DEVKEY="1" \
  "$CLOUD_BIN" > "$LOGS_DIR/cloud.log" 2>&1 &
register cloud "$!" TERM
wait_health cloud "$CLOUD_PORT" "$!" || die "cloud did not come up."

[ "$NO_DEMO" -eq 0 ] && seed_demo

# --------------------------------------------------------------------------
# Dashboard (optional): build the static export once, serve it with python3.
# --------------------------------------------------------------------------

DASH_URL=""
if [ "$WANT_DASHBOARD" -eq 1 ]; then
  DASH_DIR="$TF_REPO/cloud/dashboard"
  DASH_OUT="$DASH_DIR/out"
  if [ -f "$DASH_OUT/index.html" ] \
     && ! stale_paths "$BIN_DIR/.marker-dashboard" "$DASH_DIR/app" "$DASH_DIR/next.config.mjs" "$DASH_DIR/package.json"; then
    log "dashboard: static build up to date, skipping"
  else
    log "dashboard: building the static export (npm; the first build downloads dependencies)"
    if ( cd "$DASH_DIR" && npm ci >/dev/null 2>&1 && npm run build >/dev/null 2>&1 ); then
      : > "$BIN_DIR/.marker-dashboard"
    else
      warn "dashboard build failed; continuing without it (API on :$CLOUD_PORT is up). See the note in README.md."
      WANT_DASHBOARD=0
    fi
  fi
fi
if [ "$WANT_DASHBOARD" -eq 1 ] && [ -f "$DASH_OUT/index.html" ]; then
  log "serving dashboard on :$DASH_PORT"
  python3 -m http.server "$DASH_PORT" --bind 127.0.0.1 --directory "$DASH_OUT" > "$LOGS_DIR/dashboard.log" 2>&1 &
  register dashboard "$!" TERM
  if wait_health dashboard "$DASH_PORT" "$!" / 20; then
    DASH_URL="http://127.0.0.1:$DASH_PORT/?base=http://127.0.0.1:$CLOUD_PORT&key=devkey"
  fi
fi

# --------------------------------------------------------------------------
# Wardryx (optional): policy decision point with the seeded demo policy.
# --------------------------------------------------------------------------

if [ "$WANT_POLICY" -eq 1 ]; then
  WARDRYX_REPO="$(locate_repo wardryx Wardryx)" || { warn "could not fetch wardryx; skipping."; WANT_POLICY=0; }
fi
if [ "$WANT_POLICY" -eq 1 ]; then
  WARDRYX_BIN="$BIN_DIR/wardryx"
  if [ -x "$WARDRYX_BIN" ] && ! stale_paths "$BIN_DIR/.marker-wardryx" "$WARDRYX_REPO/cmd" "$WARDRYX_REPO/internal" "$WARDRYX_REPO/go.mod"; then
    log "wardryx: up to date, skipping build"
  else
    log "wardryx: building (Go)"
    if ! ( cd "$WARDRYX_REPO" && go build -o "$WARDRYX_BIN" ./cmd/wardryx ); then
      warn "wardryx build failed; skipping."; WANT_POLICY=0
    else
      : > "$BIN_DIR/.marker-wardryx"
    fi
  fi
fi
if [ "$WANT_POLICY" -eq 1 ]; then
  log "starting wardryx on :$WARDRYX_PORT (demo policy)"
  WARDRYX_KEYS="" \
  WARDRYX_APPROVAL_SECRET="$WARDRYX_APPROVAL_SECRET" \
    "$WARDRYX_BIN" serve -addr "127.0.0.1:$WARDRYX_PORT" -events "$EVENTS_DIR/wardryx.ndjson" -policy "$POLICY_FILE" \
    > "$LOGS_DIR/wardryx.log" 2>&1 &
  register wardryx "$!" TERM
  wait_health wardryx "$WARDRYX_PORT" "$!" || warn "wardryx did not come up; the gateway will fail open. Continuing."
fi

# --------------------------------------------------------------------------
# Idryx (optional): identity/access graph, loaded from the event stream.
# --------------------------------------------------------------------------

if [ "$WANT_IDENTITY" -eq 1 ]; then
  IDRYX_REPO="$(locate_repo idryx Idryx)" || { warn "could not fetch idryx; skipping."; WANT_IDENTITY=0; }
fi
if [ "$WANT_IDENTITY" -eq 1 ]; then
  IDRYX_BIN="$BIN_DIR/idryx"
  if [ -x "$IDRYX_BIN" ] && ! stale_paths "$BIN_DIR/.marker-idryx" "$IDRYX_REPO/cmd" "$IDRYX_REPO/internal" "$IDRYX_REPO/go.mod"; then
    log "idryx: up to date, skipping build"
  else
    log "idryx: building (Go)"
    if ! ( cd "$IDRYX_REPO" && go build -o "$IDRYX_BIN" ./cmd/idryx ); then
      warn "idryx build failed; skipping."; WANT_IDENTITY=0
    else
      : > "$BIN_DIR/.marker-idryx"
    fi
  fi
fi
if [ "$WANT_IDENTITY" -eq 1 ]; then
  log "starting idryx on :$IDRYX_PORT"
  "$IDRYX_BIN" serve --addr "127.0.0.1:$IDRYX_PORT" --load "tokenfuse:$EVENTS_FILE" \
    > "$LOGS_DIR/idryx.log" 2>&1 &
  register idryx "$!" TERM
  wait_health idryx "$IDRYX_PORT" "$!" || warn "idryx did not come up. Continuing."
fi

# --------------------------------------------------------------------------
# Summary + hold
# --------------------------------------------------------------------------

echo
log "the stack is up:"
printf '  %-12s http://127.0.0.1:%s   %s\n' "gateway" "$GATEWAY_PORT" "OpenAI-compatible, enforcing budgets"
printf '  %-12s http://127.0.0.1:%s   %s\n' "cloud"   "$CLOUD_PORT"   "money-plane API (bearer: devkey)"
[ -n "$DASH_URL" ]                 && printf '  %-12s http://127.0.0.1:%s\n' "dashboard" "$DASH_PORT"
[ "$WANT_POLICY" -eq 1 ]           && printf '  %-12s http://127.0.0.1:%s   %s\n' "wardryx" "$WARDRYX_PORT" "policy decision point"
[ "$WANT_IDENTITY" -eq 1 ]         && printf '  %-12s http://127.0.0.1:%s   %s\n' "idryx"   "$IDRYX_PORT"   "identity graph (/api/identities)"
echo
if [ -n "$DASH_URL" ]; then
  log "open the dashboard (one click, it remembers the connection):"
  printf '\033[1;32m  %s\033[0m\n' "$DASH_URL"
else
  log "no dashboard this run. Point a tool at the money-plane API:"
  printf '  curl -H "Authorization: Bearer devkey" http://127.0.0.1:%s/v1/summary\n' "$CLOUD_PORT"
fi
echo
log "events:  $EVENTS_DIR"
log "logs:    $LOGS_DIR"
log "send it traffic by pointing an agent's OpenAI base URL at the gateway (see README.md)."
echo
log "running. Press Ctrl-C to stop everything cleanly."

# Block until a signal, and notice if a service dies underneath us.
while :; do
  for entry in "${STARTED[@]}"; do
    name="${entry%%:*}"; pid="${entry#*:}"; pid="${pid%%:*}"
    if ! kill -0 "$pid" 2>/dev/null; then
      warn "$name (pid $pid) exited unexpectedly; see $LOGS_DIR/$name.log. Shutting down."
      cleanup
    fi
  done
  sleep 2
done
