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
#   tokenfuse-gateway   :4100   budget-enforcement proxy (Anthropic Messages API)
#   tokenfuse-cloud     :8080   money-plane control API (dev credential)
#   dashboard           :3000   the money-plane dashboard (static, in a browser)
#   wardryx             :8090   policy decision point (seeded demo policy)
#   idryx               :8081   identity/access graph (its own :8080 collides)
#
# It also installs the four tools that are NOT servers, because "bring it up"
# cannot mean "start a daemon" for a thing that runs once and exits. For these,
# up means: the executable is where the rest of the stack looks for it, and its
# store exists. They are installed, not started:
#
#   qryx                crypto inventory (scans a path on demand)
#   mockryx             fire drills (fires at a gateway on demand)
#   engram-mcp          agent memory over ~/.taipan/engram.engram (stdio MCP)
#   verdryx             output quality over ~/.taipan/verdryx.db
#
# Flags:
#   --only money        just the money plane (gateway + cloud + dashboard)
#   --no-dashboard      skip building/serving the dashboard
#   --no-demo           do not seed any demo dataset into cloud (the short
#                       seed, or the fleet below if --with demo-fleet is set)
#   --with demo-fleet   seed a richer, labeled-as-demo fleet (a dozen-plus
#                       agents, cache/router savings, a budget breach, a caught
#                       runaway) into cloud instead of the short seed above
#   --no-tools          skip the four installed-not-started tools above
#                       Their stores are created EMPTY and never seeded: they
#                       are persistent files the rest of the stack reads as
#                       real, and an empty plane that says so beats demo rows
#                       that cannot be told apart from a customer's own.
#   --force-install     replace binaries another tool installed (default: leave
#                       them alone and use them as they are)
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

# The stack's PUBLISHED home. Not ours: the `taipan` deploy CLI writes it and
# every consumer of the stack reads it, so this is the one directory an
# installer must land in to be discoverable. `~/.stack-up` below stays what it
# always was - this script's own private state (logs, pids, clones, build
# stamps), none of which anyone else is meant to read.
#
# This is why binaries live here rather than under `~/.stack-up/bin`: the tools
# in wave 2 are not servers with a port to connect to, they are executables
# something else has to FIND, and the lookup is a fixed path. `qryx` in
# particular is looked up at exactly `~/.taipan/bin/qryx` with no environment
# override and no PATH search, so an install anywhere else is an install
# nobody can see.
#
# TAIPAN_HOME is honoured here so the whole layout can be pointed at a scratch
# directory in a test. Consumers hardcode `~/.taipan`, so overriding it is a
# testing affordance, not a supported deployment layout.
TAIPAN_HOME="${TAIPAN_HOME:-$HOME/.taipan}"
BIN_DIR="$TAIPAN_HOME/bin"
VENV_DIR="$TAIPAN_HOME/venv"
ENGRAM_DB="$TAIPAN_HOME/engram.engram"
VERDRYX_DB="$TAIPAN_HOME/verdryx.db"

EVENTS_DIR="$STACK_UP_HOME/events"
LOGS_DIR="$STACK_UP_HOME/logs"
PIDS_DIR="$STACK_UP_HOME/pids"
REPOS_DIR="$STACK_UP_HOME/repos"
# Build-freshness stamps and the checksum of every file we installed. These
# used to sit next to the binaries; they moved because `taipan` stamps its own
# builds with the SAME `.marker-<name>` filenames in that same directory, so
# sharing it would have each installer silently validating the other's build.
MARKERS_DIR="$STACK_UP_HOME/markers"
# Where a build lands before it is installed, so nothing is ever compiled
# directly onto a path something else may be reading or executing.
BUILD_DIR="$STACK_UP_HOME/build"
LEGACY_BIN_DIR="$STACK_UP_HOME/bin"
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
DEMO_FLEET=0
NO_TOOLS=0
FORCE_INSTALL=0
WORKSPACE="${STACK_UP_WORKSPACE:-$(dirname "$SCRIPT_DIR")}"

# Print the comment header above, from the first descriptive line to the last
# contiguous comment line. Derived rather than a fixed line range, so editing
# the header can never silently truncate --help halfway through the flags.
usage() { awk 'NR<3 {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --only)
      shift
      [ "${1:-}" = "money" ] || { echo "stack-up: --only takes 'money'" >&2; exit 2; }
      ONLY_MONEY=1 ;;
    --only=money) ONLY_MONEY=1 ;;
    --no-dashboard) NO_DASHBOARD=1 ;;
    --no-demo) NO_DEMO=1 ;;
    --with)
      shift
      [ "${1:-}" = "demo-fleet" ] || { echo "stack-up: --with takes 'demo-fleet'" >&2; exit 2; }
      DEMO_FLEET=1 ;;
    --with=demo-fleet) DEMO_FLEET=1 ;;
    --no-tools) NO_TOOLS=1 ;;
    --force-install) FORCE_INSTALL=1 ;;
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

# ---- installing into the shared home -------------------------------------
#
# `$BIN_DIR` is the published home (see the layout block), which means we are
# not its only writer: `taipan up` installs the same binaries there. So we
# decide by PROVENANCE, never by mtime - a rebuild of old sources is newer than
# a fresh release, and a `cp` mtime says nothing about which build won. Every
# file we install has its checksum recorded; on a later run a file whose
# checksum still matches that record is ours to refresh, and one that does not
# belongs to somebody else and is left exactly where it is.
#
# Leaving it is the right default rather than a cop-out: the deploy CLI
# outranks the quickstart, the binary is discoverable either way (which is the
# whole point), and a workspace checkout that happens to be behind cannot
# silently downgrade a deployed one.

# file_sha <path> -> sha256 hex, empty if it cannot be read
file_sha() {
  if have shasum; then shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  elif have sha256sum; then sha256sum "$1" 2>/dev/null | awk '{print $1}'
  fi
}

# installed_by_us <name> -> 0 (true) if $BIN_DIR/<name> is exactly the file we
# installed, i.e. it is there AND its checksum still matches what we recorded.
#
# Both halves matter. "The file exists and my build stamp is fresh" is not
# enough to conclude there is nothing to do: the file sitting there may have
# been replaced since, in which case the fresh stamp is describing a build that
# is no longer installed. Checking the bytes is what makes a replaced, edited
# or corrupted binary get repaired instead of trusted forever.
installed_by_us() {
  local target="$BIN_DIR/$1" recorded
  [ -f "$target" ] || return 1
  recorded="$(cat "$MARKERS_DIR/$1.sha" 2>/dev/null || true)"
  [ -n "$recorded" ] && [ "$(file_sha "$target")" = "$recorded" ]
}

# foreign_binary <name> -> 0 (true) if something is at $BIN_DIR/<name> that we
# did not put there. --force-install makes this always false, so the caller
# falls through and treats it as an install to (re)do.
foreign_binary() {
  [ "$FORCE_INSTALL" -eq 0 ] || return 1
  [ -e "$BIN_DIR/$1" ] || return 1
  ! installed_by_us "$1"
}

# install_binary <name> <built-file> -> 0 installed, 1 could not install.
# Always via a temp file in the same directory plus a rename, never a cp over
# the live path: the memory plane's `engram-mcp` may be running right now as
# somebody's child process, and overwriting a running executable in place kills
# it on the next page-in. A rename leaves the running process its old inode.
install_binary() {
  local name="$1" src="$2"
  local target="$BIN_DIR/$name" tmp="$BIN_DIR/.tmp.$name.$$"
  if ! cp "$src" "$tmp" 2>/dev/null; then
    warn "$name: could not stage into $BIN_DIR"; rm -f "$tmp"; return 1
  fi
  chmod +x "$tmp" 2>/dev/null
  if ! mv -f "$tmp" "$target" 2>/dev/null; then
    warn "$name: could not install into $BIN_DIR"; rm -f "$tmp"; return 1
  fi
  file_sha "$target" > "$MARKERS_DIR/$name.sha"
  return 0
}

# migrate_legacy <name> - earlier versions of this script built into
# ~/.stack-up/bin. Move a binary left there rather than rebuilding it, so
# upgrading costs nothing and no second copy is left behind to be run by
# accident.
migrate_legacy() {
  local name="$1"
  [ -f "$LEGACY_BIN_DIR/$name" ] || return 0
  [ ! -e "$BIN_DIR/$name" ] || { rm -f "$LEGACY_BIN_DIR/$name"; return 0; }
  log "$name: moving the build from $LEGACY_BIN_DIR into $BIN_DIR"
  if mv "$LEGACY_BIN_DIR/$name" "$BIN_DIR/$name" 2>/dev/null; then
    file_sha "$BIN_DIR/$name" > "$MARKERS_DIR/$name.sha"
    [ -f "$LEGACY_BIN_DIR/.marker-$name" ] \
      && mv "$LEGACY_BIN_DIR/.marker-$name" "$MARKERS_DIR/.marker-$name" 2>/dev/null
  fi
  return 0
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
    # "budget_exceeded" is one of the cloud store's recognized budget-protection
    # decisions, so this last step registers as a real budget breach in
    # /v1/savings and /v1/incidents, not just a run with a blocked-looking label.
    dec="allow"; [ "$i" -eq 4 ] && dec="budget_exceeded"
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

# seed_demo_fleet: like seed_demo above, but a richer, still clearly-labeled
# dataset for a prospect who wants to see a live, moving console without
# wiring up their own agents. Same mechanism as seed_demo (POST to cloud's
# ungated /v1/ingest, Bearer devkey, loopback CLOUD_PORT), just more of it: a
# believable single-org fleet of 16 agents across finance/sre/support/data,
# each with 3 runs, cache hits and model-router downgrades so "Governed
# savings" has real cache/router numbers, and two budget breaches (one small,
# one a runaway that racks up spend before getting caught) so an incident and
# prevented spend show. Cloud runs in-memory here, so this is fresh every run
# and nothing is written to disk - same as seed_demo.
#
# The dataset is generated by python3 (already required for the dashboard
# server and the engram/verdryx tools above, so this adds no new dependency)
# rather than built as one giant bash string like seed_demo's: escaping ~190
# JSON records safely in bash quoting would be its own source of bugs, and
# python3's json module does it for free. Deterministic: every timestamp
# offset, cost and decision below is a fixed literal or a fixed arithmetic
# step off `now` (the wall clock AT SEED TIME, exactly like seed_demo's own
# `now` anchor) - never random, never a second call to `date`.
#
# Every decision string used below (allow, cache_hit, budget_exceeded) is one
# of the 9 the cloud store actually recognises (Store::is_known_decision in
# tokenfuse's crates/cloud/src/store.rs); budget_exceeded is also a
# budget-protection reason (tokenfuse_core::savings::is_budget_protection), so
# three of them on one run_id both crosses the store's budget_exhausted
# incident threshold (>=3, IncidentConfig::budget_blocks) and adds to
# /v1/savings' blocked_spend_microusd - a real incident and real prevented
# spend, not just a run with a "blocked"-looking label.
seed_demo_fleet() {
  have python3 || {
    warn "python3 not found: cannot build the demo fleet dataset; falling back to the short demo seed."
    seed_demo
    return
  }

  local now gen rc line first_line n_agents n_runs n_calls batches sent

  now=$(( $(date +%s) * 1000 ))

  # stdout: first line is "AGENTS RUNS CALLS" for the summary log line below;
  # every following line is one compact-JSON ingest batch ({"records":[...]}).
  # Posting itself stays plain curl in the loop below, exactly like seed_demo.
  gen="$(python3 - "$now" <<'PY'
import json
import sys

now = int(sys.argv[1])
MICRO = 1_000_000
records = []


def rec(run_id, agent, unit, model, decision, ago_min, step, in_tok, out_tok, cost_usd, saved_usd=0.0):
    records.append({
        "ts_millis": now - int(round(ago_min * 60_000)),
        "run_id": run_id,
        "model": model,
        "decision": decision,
        "input_tokens": int(in_tok),
        "output_tokens": int(out_tok),
        "cost_microusd": int(round(cost_usd * MICRO)),
        "step": step,
        "agent_id": agent,
        "saved_microusd": int(round(saved_usd * MICRO)),
        "unit": unit,
    })


def agent_calls(team, role, model, base_cost, cost_step, in_base, out_base,
                 n_calls_per_run, cache_steps=(), router_steps=(), gap=3.0,
                 tail_block=None, in_step=30, out_step=10,
                 start_ago_per_run=None):
    """Emit the runs for one agent. `n_calls_per_run` has one entry per run (run 1
    oldest); `cache_steps`/`router_steps` are 1-based call indices, applied
    the same way in every run, that become a cache hit / router-downgraded
    allow instead of a plain allow. `tail_block`, if given, is
    (decision, count) and applies ONLY to the LAST (freshest) run: its final
    `count` calls become that blocked decision instead of allow - the
    "caught in the act" moment. Every offset is arithmetic on fixed indices
    and the passed-in `now`; nothing here reads the wall clock or a RNG."""
    agent = f"agent://demo.local/{team}/{role}"
    runs = len(n_calls_per_run)
    if start_ago_per_run is None:
        # Spread runs across the last ~45 minutes, oldest run first, newest
        # run freshest - so the fleet looks active right up to "now".
        step_back = 45 // runs if runs > 1 else 0
        start_ago_per_run = [45 - step_back * (r - 1) for r in range(1, runs + 1)]
    for r in range(1, runs + 1):
        n = n_calls_per_run[r - 1]
        start_ago = start_ago_per_run[r - 1]
        run_id = f"fleet-{team}-{role}-{r}"
        block = tail_block if (tail_block and r == runs) else None
        block_decision, block_count = block or (None, 0)
        # Mild run-over-run cost creep so run 3 is not a carbon copy of run 1.
        run_cost = base_cost * (1 + 0.06 * (r - 1))
        for i in range(1, n + 1):
            ago = max(start_ago - gap * (i - 1), 0.5)
            cost = run_cost + cost_step * (i - 1)
            in_tok = in_base + in_step * (i - 1)
            out_tok = out_base + out_step * (i - 1)
            if block_decision and i > n - block_count:
                # A budget-protection block: cost_microusd is the AVOIDED
                # spend estimate (never charged, never counted as real
                # spend), which is what makes it show up as prevented spend.
                rec(run_id, agent, team, model, block_decision, ago, i, in_tok, out_tok, cost)
            elif i in cache_steps:
                # Served free from the semantic cache: no real charge, and
                # the full avoided cost is credited as cache savings.
                rec(run_id, agent, team, model, "cache_hit", ago, i, in_tok, out_tok, 0.0, saved_usd=cost)
            elif i in router_steps:
                # Router-downgraded to a cheaper model: still a real (smaller)
                # charge, plus the difference credited as router savings.
                kept = round(cost * 0.4, 6)
                rec(run_id, agent, team, model, "allow", ago, i, in_tok, out_tok, kept, saved_usd=round(cost - kept, 6))
            else:
                rec(run_id, agent, team, model, "allow", ago, i, in_tok, out_tok, cost)


# ---- the fleet: 16 agents across 4 teams, 3 runs each -----------------

# finance
agent_calls("finance", "invoice-matcher", "gpt-4o-mini",
            base_cost=0.0009, cost_step=0.0002, in_base=420, out_base=110,
            n_calls_per_run=[4, 4, 5])
agent_calls("finance", "close-bot", "gpt-4o",
            base_cost=0.012, cost_step=0.004, in_base=1400, out_base=380,
            n_calls_per_run=[3, 3, 4], tail_block=("budget_exceeded", 3))
agent_calls("finance", "fx-reconciler", "claude-3-5-haiku-20241022",
            base_cost=0.0013, cost_step=0.0002, in_base=500, out_base=140,
            n_calls_per_run=[3, 4, 3])
agent_calls("finance", "expense-auditor", "gpt-4o-mini",
            base_cost=0.0011, cost_step=0.0002, in_base=460, out_base=120,
            n_calls_per_run=[4, 5, 4], cache_steps={2, 4})

# sre
agent_calls("sre", "incident-triage", "claude-3-5-sonnet-20241022",
            base_cost=0.014, cost_step=0.003, in_base=1800, out_base=520,
            n_calls_per_run=[3, 3, 3])
agent_calls("sre", "log-summarizer", "gpt-4o-mini",
            base_cost=0.0008, cost_step=0.0001, in_base=900, out_base=90,
            n_calls_per_run=[5, 6, 5], cache_steps={2, 4})
agent_calls("sre", "runbook-executor", "gpt-4o",
            base_cost=0.013, cost_step=0.003, in_base=1500, out_base=400,
            n_calls_per_run=[3, 4, 3], router_steps={2})
# The runaway: two ordinary runs, then a third that spirals - cost climbing
# call over call - until three straight budget_exceeded blocks catch it.
agent_calls("sre", "batch-crawler", "gpt-4o",
            base_cost=0.02, cost_step=0.032, in_base=2600, out_base=700,
            n_calls_per_run=[3, 3, 12], gap=0.7, in_step=220, out_step=60,
            start_ago_per_run=[42, 22, 9],
            tail_block=("budget_exceeded", 3))

# support
agent_calls("support", "tier1-bot", "gpt-4o-mini",
            base_cost=0.0007, cost_step=0.0001, in_base=380, out_base=100,
            n_calls_per_run=[5, 6, 5], cache_steps={2, 5})
agent_calls("support", "tier2-escalation", "gpt-4o",
            base_cost=0.011, cost_step=0.002, in_base=1300, out_base=350,
            n_calls_per_run=[3, 3, 3])
agent_calls("support", "refund-assistant", "claude-3-5-haiku-20241022",
            base_cost=0.0013, cost_step=0.0002, in_base=520, out_base=150,
            n_calls_per_run=[3, 4, 3], router_steps={2})
agent_calls("support", "kb-search", "gpt-4o-mini",
            base_cost=0.0008, cost_step=0.0001, in_base=350, out_base=90,
            n_calls_per_run=[4, 5, 4], cache_steps={1, 3})

# data
agent_calls("data", "etl-monitor", "gpt-4o-mini",
            base_cost=0.0010, cost_step=0.0001, in_base=600, out_base=160,
            n_calls_per_run=[3, 4, 3])
agent_calls("data", "anomaly-detector", "claude-3-5-sonnet-20241022",
            base_cost=0.016, cost_step=0.003, in_base=2000, out_base=560,
            n_calls_per_run=[3, 3, 3])
agent_calls("data", "report-generator", "gpt-4o",
            base_cost=0.015, cost_step=0.003, in_base=1900, out_base=520,
            n_calls_per_run=[3, 3, 3], router_steps={2})
agent_calls("data", "pipeline-guard", "gpt-4o-mini",
            base_cost=0.0009, cost_step=0.0001, in_base=480, out_base=130,
            n_calls_per_run=[4, 4, 4], cache_steps={2, 4})

records.sort(key=lambda r: r["ts_millis"])  # oldest first; cosmetic only

n_agents = len({r["agent_id"] for r in records})
n_runs = len({r["run_id"] for r in records})
n_calls = len(records)

BATCH = 50
print(f"{n_agents} {n_runs} {n_calls}")
for i in range(0, len(records), BATCH):
    batch = records[i:i + BATCH]
    print(json.dumps({"records": batch}, separators=(",", ":")))
PY
)"
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$gen" ]; then
    warn "demo fleet generation failed (python3 exited $rc); falling back to the short demo seed."
    seed_demo
    return
  fi

  first_line=1
  batches=0
  sent=0
  while IFS= read -r line; do
    if [ "$first_line" -eq 1 ]; then
      read -r n_agents n_runs n_calls <<< "$line"
      first_line=0
      continue
    fi
    batches=$((batches + 1))
    if curl -fsS -o /dev/null -X POST "http://127.0.0.1:$CLOUD_PORT/v1/ingest" \
         -H "Authorization: Bearer devkey" -H "Content-Type: application/json" \
         -d "$line" 2>/dev/null; then
      sent=$((sent + 1))
    fi
  done <<< "$gen"

  if [ "$batches" -gt 0 ] && [ "$sent" -eq "$batches" ]; then
    log "seeded demo fleet: ${n_agents:-0} agents, ${n_runs:-0} runs, ${n_calls:-0} calls (DEMO DATA); pass --no-demo to skip"
  elif [ "$sent" -gt 0 ]; then
    warn "demo fleet partially seeded ($sent/$batches batches); the dashboard will show a partial fleet."
  else
    warn "demo fleet seed failed; the dashboard will just start empty."
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

# The installed-not-started tools. Split by toolchain, because Go being absent
# says nothing about Python being absent - each half degrades on its own.
WANT_GO_TOOLS=1
WANT_PY_TOOLS=1
if [ "$ONLY_MONEY" -eq 1 ] || [ "$NO_TOOLS" -eq 1 ]; then
  WANT_GO_TOOLS=0; WANT_PY_TOOLS=0
else
  have go || { warn "go not found: skipping qryx + mockryx (they are written in Go)."; WANT_GO_TOOLS=0; }
  have python3 || { warn "python3 not found: skipping engram + verdryx (they are written in Python)."; WANT_PY_TOOLS=0; }
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

mkdir -p "$EVENTS_DIR" "$LOGS_DIR" "$PIDS_DIR" "$REPOS_DIR" "$MARKERS_DIR" "$BUILD_DIR"
# The shared home may not exist yet, and if we are the ones creating it we
# create it closed: it accumulates an event stream and, under `taipan`, dev
# bearer keys. An existing one is never re-chmod'ed - its permissions are its
# owner's business, not ours.
if [ ! -d "$TAIPAN_HOME" ]; then
  mkdir -p "$TAIPAN_HOME" && chmod 700 "$TAIPAN_HOME"
fi
mkdir -p "$BIN_DIR" || die "could not create $BIN_DIR"
: > "$EVENTS_FILE"

trap cleanup INT TERM EXIT

# --------------------------------------------------------------------------
# Build + start: tokenfuse gateway + cloud (mandatory)
# --------------------------------------------------------------------------

TF_REPO="$(locate_repo tokenfuse)" || die "could not fetch tokenfuse."

migrate_legacy tokenfuse-gateway
migrate_legacy tokenfuse-cloud
GATEWAY_BIN="$BIN_DIR/tokenfuse-gateway"
CLOUD_BIN="$BIN_DIR/tokenfuse-cloud"
if foreign_binary tokenfuse-gateway || foreign_binary tokenfuse-cloud; then
  [ -x "$GATEWAY_BIN" ] && [ -x "$CLOUD_BIN" ] \
    || die "tokenfuse: $BIN_DIR holds another tool's install but not both binaries; move it aside or pass --force-install."
  log "tokenfuse: gateway + cloud already installed by another tool; using those"
elif installed_by_us tokenfuse-gateway && installed_by_us tokenfuse-cloud \
   && ! stale_paths "$MARKERS_DIR/.marker-tokenfuse" "$TF_REPO/crates" "$TF_REPO/Cargo.toml" "$TF_REPO/Cargo.lock"; then
  log "tokenfuse: gateway + cloud up to date, skipping build"
else
  log "tokenfuse: building gateway + cloud (Rust release; the first build can take several minutes)"
  ( cd "$TF_REPO" && cargo build --release -p tokenfuse-gateway -p tokenfuse-cloud ) \
    || die "tokenfuse build failed."
  install_binary tokenfuse-gateway "$TF_REPO/target/release/tokenfuse" || die "could not install the gateway binary."
  install_binary tokenfuse-cloud "$TF_REPO/target/release/tokenfuse-cloud" || die "could not install the cloud binary."
  : > "$MARKERS_DIR/.marker-tokenfuse"
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

# gateway: enforce mode, agent-event export on, reporting to the local cloud,
# wardryx wired if enabled.
# SIGINT specifically on stop so its buffered Parquet trace flushes.
#
# TOKENFUSE_CLOUD_URL/KEY are what connect the gateway to the cloud we just
# started: the gateway's CloudSink POSTs every settled call to
# `{base}/v1/ingest`, and without them it silently ships nowhere. That was the
# state until 2026-07-21, and it is why this script used to seed a demo
# dataset "so the dashboard is not empty" - the dashboard COULD not fill up,
# because the pipe between the two processes it had just started was never
# connected. Real traffic (18 metered calls) left /v1/runs empty; with these
# two lines the same traffic shows up as real runs with real spend.
log "starting gateway on :$GATEWAY_PORT (enforce, reporting to the cloud)"
if [ -n "$WARDRYX_URL" ]; then
  TOKENFUSE_ADDR="127.0.0.1:$GATEWAY_PORT" \
  TOKENFUSE_MODE="enforce" \
  TOKENFUSE_EVENTS_PATH="$EVENTS_FILE" \
  TOKENFUSE_DATA_DIR="$STACK_UP_HOME/traces/gateway" \
  TOKENFUSE_CLOUD_URL="http://127.0.0.1:$CLOUD_PORT" \
  TOKENFUSE_CLOUD_KEY="devkey" \
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
  TOKENFUSE_CLOUD_URL="http://127.0.0.1:$CLOUD_PORT" \
  TOKENFUSE_CLOUD_KEY="devkey" \
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

if [ "$NO_DEMO" -eq 0 ]; then
  if [ "$DEMO_FLEET" -eq 1 ]; then
    seed_demo_fleet
  else
    seed_demo
  fi
fi

# --------------------------------------------------------------------------
# Dashboard (optional): build the static export once, serve it with python3.
# --------------------------------------------------------------------------

DASH_URL=""
if [ "$WANT_DASHBOARD" -eq 1 ]; then
  DASH_DIR="$TF_REPO/cloud/dashboard"
  DASH_OUT="$DASH_DIR/out"
  if [ -f "$DASH_OUT/index.html" ] \
     && ! stale_paths "$MARKERS_DIR/.marker-dashboard" "$DASH_DIR/app" "$DASH_DIR/next.config.mjs" "$DASH_DIR/package.json"; then
    log "dashboard: static build up to date, skipping"
  else
    log "dashboard: building the static export (npm; the first build downloads dependencies)"
    if ( cd "$DASH_DIR" && npm ci >/dev/null 2>&1 && npm run build >/dev/null 2>&1 ); then
      : > "$MARKERS_DIR/.marker-dashboard"
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
  migrate_legacy wardryx
  WARDRYX_BIN="$BIN_DIR/wardryx"
  if foreign_binary wardryx; then
    log "wardryx: already installed by another tool; using $WARDRYX_BIN"
  elif installed_by_us wardryx && ! stale_paths "$MARKERS_DIR/.marker-wardryx" "$WARDRYX_REPO/cmd" "$WARDRYX_REPO/internal" "$WARDRYX_REPO/go.mod"; then
    log "wardryx: up to date, skipping build"
  else
    log "wardryx: building (Go)"
    if ! ( cd "$WARDRYX_REPO" && go build -o "$BUILD_DIR/wardryx" ./cmd/wardryx ) \
       || ! install_binary wardryx "$BUILD_DIR/wardryx"; then
      warn "wardryx build failed; skipping."; WANT_POLICY=0
    else
      : > "$MARKERS_DIR/.marker-wardryx"
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
  migrate_legacy idryx
  IDRYX_BIN="$BIN_DIR/idryx"
  if foreign_binary idryx; then
    log "idryx: already installed by another tool; using $IDRYX_BIN"
  elif installed_by_us idryx && ! stale_paths "$MARKERS_DIR/.marker-idryx" "$IDRYX_REPO/cmd" "$IDRYX_REPO/internal" "$IDRYX_REPO/go.mod"; then
    log "idryx: up to date, skipping build"
  else
    log "idryx: building (Go)"
    if ! ( cd "$IDRYX_REPO" && go build -o "$BUILD_DIR/idryx" ./cmd/idryx ) \
       || ! install_binary idryx "$BUILD_DIR/idryx"; then
      warn "idryx build failed; skipping."; WANT_IDENTITY=0
    else
      : > "$MARKERS_DIR/.marker-idryx"
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
# Wave 2 (optional): the four tools that are installed, not started.
#
# None of these is a server. qryx scans a path and exits; mockryx fires at a
# gateway you name and exits; engram is a library plus a CLI plus a stdio-only
# MCP server over a local file; verdryx is a CLI over a local file. So there is
# no port to wait on and no process to register. "Up" for them means exactly
# two things: the executable is at the path the rest of the stack looks for,
# and its store exists.
#
# Each is independently optional and never fatal - a missing Go or Python
# toolchain, a failed build, or a binary another tool owns all end with a line
# saying so and the run continuing.
# --------------------------------------------------------------------------

TOOLS_INSTALLED=()

# install_go_tool <name> [alt-repo-casing...] - build ./cmd/<name> and install.
install_go_tool() {
  local name="$1"; shift
  local repo
  repo="$(locate_repo "$name" "$@")" || { warn "could not fetch $name; skipping it."; return 1; }
  migrate_legacy "$name"
  if foreign_binary "$name"; then
    log "$name: already installed by another tool; using $BIN_DIR/$name"
    TOOLS_INSTALLED+=("$name"); return 0
  fi
  if installed_by_us "$name" \
     && ! stale_paths "$MARKERS_DIR/.marker-$name" "$repo/cmd" "$repo/internal" "$repo/go.mod"; then
    log "$name: up to date, skipping build"
    TOOLS_INSTALLED+=("$name"); return 0
  fi
  log "$name: building (Go)"
  if ! ( cd "$repo" && go build -o "$BUILD_DIR/$name" "./cmd/$name" ) \
     || ! install_binary "$name" "$BUILD_DIR/$name"; then
    warn "$name build failed; skipping it. Its plane will be dark until it is installed."
    return 1
  fi
  : > "$MARKERS_DIR/.marker-$name"
  TOOLS_INSTALLED+=("$name")
  return 0
}

# install_py_tool <name> <console-script> <pip-extras> <import-check>
#                 [alt-repo-casing...]
# Install the package into its own virtualenv and put the console script where
# the stack looks for it.
#
# <pip-extras> is appended to the path pip is given, e.g. "[mcp]". It is not
# cosmetic: engram's MCP server is an OPTIONAL extra, so a plain install
# produces an `engram-mcp` that exists, is executable, parses `--help` fine,
# and dies on an ImportError the moment something actually speaks MCP to it.
#
# <import-check> is the module that must import afterwards, which is what turns
# the above from "found out in production" into "found out here". Checking the
# console script itself is not enough for exactly the reason above: argparse
# runs before the import that fails.
#
# The virtualenv lives under the SHARED home, not under ~/.stack-up, on
# purpose: a Python console script is a shebang line pointing at the exact
# interpreter it was installed with, so the venv is part of the delivered
# artifact, not this installer's scratch space. Putting it in our own state
# directory would mean deleting our cache silently breaks an executable
# somebody else is running.
install_py_tool() {
  local name="$1" script="$2" extras="$3" import_check="$4"; shift 4
  local repo venv="$VENV_DIR/$name"
  repo="$(locate_repo "$name" "$@")" || { warn "could not fetch $name; skipping it."; return 1; }
  migrate_legacy "$script"
  if foreign_binary "$script"; then
    log "$script: already installed by another tool; using $BIN_DIR/$script"
    TOOLS_INSTALLED+=("$script"); return 0
  fi
  # The import check is part of "up to date" on purpose, not just part of a
  # fresh install: a venv left behind by an older stack-up that installed
  # without the extras is present, executable and stale-free, and would be
  # skipped forever while its plane stays broken. Failing the check here drops
  # through to a reinstall instead.
  if [ -x "$venv/bin/$script" ] && installed_by_us "$script" \
     && "$venv/bin/python" -c "import $import_check" >/dev/null 2>&1 \
     && ! stale_paths "$MARKERS_DIR/.marker-$name" "$repo/pyproject.toml" "$repo/$name"; then
    log "$name: up to date, skipping install"
    TOOLS_INSTALLED+=("$script"); return 0
  fi
  log "$name: installing into $venv (Python)"
  if [ ! -x "$venv/bin/python" ] && ! python3 -m venv "$venv" >/dev/null 2>&1; then
    warn "$name: could not create a virtualenv at $venv; skipping it."; return 1
  fi
  "$venv/bin/python" -m pip install --quiet --upgrade pip >/dev/null 2>&1
  if ! "$venv/bin/python" -m pip install --quiet "${repo}${extras}" >/dev/null 2>&1; then
    warn "$name: pip install failed; skipping it. Its plane will be dark until it is installed."
    return 1
  fi
  if ! "$venv/bin/python" -c "import $import_check" >/dev/null 2>&1; then
    warn "$name: installed, but \`import $import_check\` fails, so $script would die the first time it is used; skipping it."
    return 1
  fi
  if ! install_binary "$script" "$venv/bin/$script"; then
    return 1
  fi
  : > "$MARKERS_DIR/.marker-$name"
  TOOLS_INSTALLED+=("$script")
  return 0
}

if [ "$WANT_GO_TOOLS" -eq 1 ]; then
  # qryx pins a newer Go toolchain than mockryx and downloads it on the first
  # build, which is slow but automatic (GOTOOLCHAIN=auto is the default).
  install_go_tool qryx Qryx
  install_go_tool mockryx Mockryx
fi

if [ "$WANT_PY_TOOLS" -eq 1 ]; then
  install_py_tool engram  engram-mcp "[mcp]" mcp     Engram
  install_py_tool verdryx verdryx   ""       verdryx Verdryx
fi

# Once everything that could have been migrated has been, retire the old bin
# directory - but only if it is empty, so anything we did not recognise is
# left for a human to look at rather than deleted on a guess.
rmdir "$LEGACY_BIN_DIR" 2>/dev/null

# ---- stores ---------------------------------------------------------------
#
# Created with each tool's OWN code, never with hand-written SQL: the schema is
# then whatever that version of the tool says it is, and stays right when the
# tool's schema moves. Created only if absent - an existing store may hold real
# work, and this script has no business deciding otherwise.
#
# Created EMPTY, and not seeded. Unlike the demo dataset the money plane gets
# (which lives in a cloud process that keeps it in memory and forgets it on
# exit), these are files on disk that the rest of the stack reads as ground
# truth. Demo rows in them are indistinguishable from a customer's own rows,
# permanently. An empty plane that says it is empty is the honest outcome; if
# that reads badly, the fix belongs in whatever renders the empty state.

# ensure_store <label> <venv-name> <path> <python-source-on-stdin>
ensure_store() {
  local label="$1" venv="$VENV_DIR/$2" path="$3"
  if [ -e "$path" ]; then
    log "$label: store already exists at $path (left untouched)"
    return 0
  fi
  [ -x "$venv/bin/python" ] || return 1
  if "$venv/bin/python" - "$path" >/dev/null 2>&1; then
    log "$label: created an empty store at $path"
  else
    warn "$label: could not create $path; that plane will stay dark."
    return 1
  fi
}

if [ "$WANT_PY_TOOLS" -eq 1 ] && [ -x "$VENV_DIR/engram/bin/python" ]; then
  ensure_store memory engram "$ENGRAM_DB" <<'PY'
import sys
from engram import Engram

Engram(sys.argv[1])
PY
fi

if [ "$WANT_PY_TOOLS" -eq 1 ] && [ -x "$VENV_DIR/verdryx/bin/python" ]; then
  ensure_store quality verdryx "$VERDRYX_DB" <<'PY'
import sys
from verdryx.store import Store

with Store.open(sys.argv[1]):
    pass
PY
fi

# --------------------------------------------------------------------------
# Summary + hold
# --------------------------------------------------------------------------

echo
log "the stack is up:"
printf '  %-12s http://127.0.0.1:%s   %s\n' "gateway" "$GATEWAY_PORT" "Anthropic Messages API, enforcing budgets"
printf '  %-12s http://127.0.0.1:%s   %s\n' "cloud"   "$CLOUD_PORT"   "money-plane API (bearer: devkey)"
[ -n "$DASH_URL" ]                 && printf '  %-12s http://127.0.0.1:%s\n' "dashboard" "$DASH_PORT"
[ "$WANT_POLICY" -eq 1 ]           && printf '  %-12s http://127.0.0.1:%s   %s\n' "wardryx" "$WARDRYX_PORT" "policy decision point"
[ "$WANT_IDENTITY" -eq 1 ]         && printf '  %-12s http://127.0.0.1:%s   %s\n' "idryx"   "$IDRYX_PORT"   "identity graph (/api/identities)"

if [ "${#TOOLS_INSTALLED[@]}" -gt 0 ]; then
  echo
  log "installed, not started (no port to connect to; run them when you need them):"
  for t in "${TOOLS_INSTALLED[@]}"; do
    printf '  %-12s %s\n' "$t" "$BIN_DIR/$t"
  done
  # Print the store paths even when empty. If a consumer is running with
  # ENGRAM_MCP_DB or VERDRYX_DB pointed somewhere else, it will read that other
  # file and these will sit unused - which is invisible unless the paths are
  # said out loud once.
  [ -e "$ENGRAM_DB" ]  && printf '  %-12s %s\n' "memory" "$ENGRAM_DB"
  [ -e "$VERDRYX_DB" ] && printf '  %-12s %s\n' "quality" "$VERDRYX_DB"
  echo
  log "those stores start empty and stay empty until you put something in them:"
  for t in "${TOOLS_INSTALLED[@]}"; do
    case "$t" in
      qryx)       printf '  %s scan <path>\n' "$BIN_DIR/qryx" ;;
      mockryx)    printf '  %s run --gateway http://127.0.0.1:%s\n' "$BIN_DIR/mockryx" "$GATEWAY_PORT" ;;
      engram-mcp) printf '  %s --db %s        # an agent speaks MCP to this over stdio\n' "$BIN_DIR/engram-mcp" "$ENGRAM_DB" ;;
      verdryx)    printf '  VERDRYX_DB=%s %s eval --help\n' "$VERDRYX_DB" "$BIN_DIR/verdryx" ;;
    esac
  done
fi
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
log "send it traffic by pointing an agent's Anthropic base URL at the gateway (see README.md)."
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
