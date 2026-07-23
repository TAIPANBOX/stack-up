#!/usr/bin/env bash
#
# stack-up routines: schedule and run the stack's own recurring GOVERNANCE
# work (not the agents themselves).
#
# The stack produces governance signal on its own: a FinOps export, a crypto-
# inventory trend, a quality-drift check, an identity-anomaly sweep, and (opt
# in) a fire drill. Nobody looks at these unless something runs them on a
# schedule, so this script is that schedule: it installs OS-native timers
# (systemd on Linux, launchd on macOS) that each invoke `routines.sh run
# <name>` at a fixed time, and it is also the thing those timers invoke.
#
# Routines (daily, staggered five minutes apart so they never collide):
#
#   focus-export     06:07  tokenfuse-gateway focus-export -> a FOCUS-format
#                            FinOps CSV from the gateway's own Parquet trace
#   qryx-trend       06:17  qryx scan (save evidence) + qryx trend -> crypto-
#                            inventory compliance-score history
#   verdryx-drift    06:27  verdryx drift against a baseline you set -> a
#                            quality-regression check
#   idryx-detect     06:37  idryx detect over the tokenfuse event stream ->
#                            an identity/access anomaly sweep
#   mockryx-drill    06:47  Monday only, OPT-IN (--with-drill): a live fire
#                            drill against your own gateway. It sends real
#                            traffic through it to whatever LLM provider is
#                            configured there, which can spend that
#                            provider's money, and it is deliberately built
#                            to trip your policies -- that is what a drill
#                            is for. Never installed unless you ask for it.
#
# Subcommands:
#   list               one line per routine: installed as a timer? last run?
#   run <name>         run one routine now and record the result. This is
#                      the entrypoint the OS scheduler invokes; safe to run
#                      by hand too.
#   install            install timers for the four safe routines above
#     [--with-drill]   also install the mockryx-drill timer (prints the
#                      warning above again, first, before touching anything)
#   uninstall          remove exactly and only what install created, tracked
#                      in a manifest -- never anything install did not make
#   status             the last record per routine, plus the scheduler's own
#                      view (systemctl list-timers / launchctl print),
#                      filtered to stack-up's own units
#   -h, --help         show this and exit
#
# Every run is recorded twice: appended as one line to
# $STACK_UP_HOME/routines/history.ndjson (the full history) and written
# atomically to $STACK_UP_HOME/routines/status/<name>.json (just the
# latest). Both use the schema documented in README.md under "Scheduled
# governance runs" -- it is a stable contract read by the Genaryx console, so
# it does not change shape casually.
#
# A precondition that is not met (a missing binary, a missing store, unset
# config) is recorded as "skipped" with the exact reason, and that is not a
# failure: a routine with nothing to do yet is the expected state right after
# a fresh install, not a broken one.
#
# Config: $STACK_UP_HOME/routines/config is an optional shell fragment,
# sourced if present, for:
#   ROUTINE_QRYX_SCAN_PATH      qryx-trend's scan target (default: repos/)
#   ROUTINE_VERDRYX_BASELINE    required for verdryx-drift; no default, so
#                               that routine stays skipped until you set one
#   ROUTINE_VERDRYX_WINDOW      verdryx-drift's --window (default: 5)
#   ROUTINE_DRILL_SCENARIOS     mockryx-drill's scenarios directory
#
# ROUTINES_UNIT_DIR overrides where install/uninstall read and write unit
# files, and skips touching the real launchctl/systemctl when it is set. It
# exists for tests: generate the unit files into a scratch directory and
# inspect them without registering anything with the real scheduler.
#
# A note on clocks: the timers above fire in whatever time zone the OS
# scheduler uses (local time, whatever the machine is set to). Every
# timestamp inside a recorded run is UTC. Those are two different clocks by
# design -- see README.md.
#
# Apache-2.0. Part of https://github.com/TAIPANBOX

set -uo pipefail

# --------------------------------------------------------------------------
# Constants and layout
# --------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

STACK_UP_HOME="${STACK_UP_HOME:-$HOME/.stack-up}"
TAIPAN_HOME="${TAIPAN_HOME:-$HOME/.taipan}"
BIN_DIR="$TAIPAN_HOME/bin"

EVENTS_DIR="$STACK_UP_HOME/events"
# keep in sync with up.sh
EVENTS_FILE="$EVENTS_DIR/tokenfuse.ndjson"

ROUTINES_DIR="$STACK_UP_HOME/routines"
HISTORY_FILE="$ROUTINES_DIR/history.ndjson"
STATUS_DIR="$ROUTINES_DIR/status"
OUT_DIR="$ROUTINES_DIR/out"
LOGS_DIR="$ROUTINES_DIR/logs"
CONFIG_FILE="$ROUTINES_DIR/config"
INSTALLED_MANIFEST="$ROUTINES_DIR/installed.txt"

# All five routines, and the four considered safe to install by default.
# mockryx-drill is opt-in only (--with-drill) and is deliberately never in
# DEFAULT_ROUTINES.
ROUTINE_NAMES=(focus-export qryx-trend verdryx-drift idryx-detect mockryx-drill)
DEFAULT_ROUTINES=(focus-export qryx-trend verdryx-drift idryx-detect)

# --------------------------------------------------------------------------
# Small helpers (verbatim from up.sh/down.sh, so every stack-up script logs
# the same way)
# --------------------------------------------------------------------------

log()  { printf '\033[1;36m[stack-up]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[stack-up]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[stack-up] error:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

is_macos() { [ "$(uname -s)" = "Darwin" ]; }

# Print the comment header above, from the first descriptive line to the
# last contiguous comment line. Derived rather than a fixed line range, so
# editing the header can never silently truncate --help halfway through.
usage() { awk 'NR<3 {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$0"; }

is_known_routine() {
  local n
  for n in "${ROUTINE_NAMES[@]}"; do
    [ "$n" = "$1" ] && return 0
  done
  return 1
}

ensure_dirs() {
  mkdir -p "$ROUTINES_DIR" "$STATUS_DIR" "$OUT_DIR" "$LOGS_DIR"
}

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
  fi
}

now_rfc3339() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# --------------------------------------------------------------------------
# Schedule: every routine runs at :07/:17/:27/:37/:47 past 06:00, so five
# routines with real (if small) work never start in the same minute. Only
# mockryx-drill is weekly (Monday); the rest are daily.
# --------------------------------------------------------------------------

routine_hour() { echo 6; }  # every routine runs in the 06:xx hour

routine_minute() {
  case "$1" in
    focus-export)  echo 7 ;;
    qryx-trend)    echo 17 ;;
    verdryx-drift) echo 27 ;;
    idryx-detect)  echo 37 ;;
    mockryx-drill) echo 47 ;;
  esac
}

routine_is_weekly() { [ "$1" = "mockryx-drill" ]; }  # Monday-only; else daily

# --------------------------------------------------------------------------
# Locking: a portable mkdir-based lock per routine. mkdir is atomic on every
# filesystem this runs on, which a lockfile written with `>` is not. A lock
# older than 60 minutes is treated as abandoned -- nothing here runs anywhere
# near that long -- and broken with a warning, never silently. Always
# released on exit via a single top-level trap, so a killed run cannot wedge
# the routine shut forever.
# --------------------------------------------------------------------------

CURRENT_LOCK_DIR=""

release_lock_on_exit() {
  if [ -n "$CURRENT_LOCK_DIR" ] && [ -d "$CURRENT_LOCK_DIR" ]; then
    rmdir "$CURRENT_LOCK_DIR" 2>/dev/null
  fi
}
trap release_lock_on_exit EXIT

# lock_age_seconds <path> -> seconds since its mtime (0 if unreadable).
# Tries BSD stat first (macOS), then GNU stat (Linux).
lock_age_seconds() {
  local path="$1" mtime
  mtime="$(stat -f %m "$path" 2>/dev/null)"
  [ -n "$mtime" ] || mtime="$(stat -c %Y "$path" 2>/dev/null)"
  [ -n "$mtime" ] || { echo 0; return; }
  echo $(( $(date +%s) - mtime ))
}

# acquire_lock <name> -> 0 and sets CURRENT_LOCK_DIR, or 1 if another run
# holds it.
acquire_lock() {
  local name="$1" dir="$ROUTINES_DIR/.lock.$1" age
  if mkdir "$dir" 2>/dev/null; then
    CURRENT_LOCK_DIR="$dir"
    return 0
  fi
  age="$(lock_age_seconds "$dir")"
  if [ "$age" -gt 3600 ]; then
    warn "$name: breaking a lock older than ${age}s (> 60m) at $dir"
    rmdir "$dir" 2>/dev/null
    if mkdir "$dir" 2>/dev/null; then
      CURRENT_LOCK_DIR="$dir"
      return 0
    fi
  fi
  warn "$name: another run holds the lock ($dir); skipping this invocation"
  return 1
}

# --------------------------------------------------------------------------
# Record schema (STABLE CONTRACT -- see README.md "Scheduled governance
# runs"). Built with python3, never string concatenation, so quotes and
# newlines in a reason/summary line are escaped correctly instead of
# breaking the JSON. Written atomically to status/<name>.json: a temp file
# in the same directory, then a rename, so a reader never observes a
# half-written file.
# --------------------------------------------------------------------------

write_record() {
  local name="$1" started="$2" finished="$3" exit_code="$4" status="$5" \
        reason="$6" artifact="$7" summary="$8"
  mkdir -p "$STATUS_DIR"
  python3 - "$name" "$started" "$finished" "$exit_code" "$status" "$reason" \
    "$artifact" "$summary" "$HISTORY_FILE" "$STATUS_DIR/$name.json" <<'PY'
import json
import os
import sys

(name, started, finished, exit_code, status, reason, artifact, summary,
 history_file, status_path) = sys.argv[1:11]

record = {
    "schema": "stackup.routine-run/v1",
    "routine": name,
    "started_at": started,
    "finished_at": finished,
    "exit_code": int(exit_code),
    "status": status,
    "reason": reason or None,
    "artifact": artifact or None,
    "summary": summary or None,
}
line = json.dumps(record)

with open(history_file, "a") as f:
    f.write(line + "\n")

tmp_path = status_path + ".tmp"
with open(tmp_path, "w") as f:
    f.write(line + "\n")
os.replace(tmp_path, status_path)  # same filesystem: atomic rename
PY
}

# --------------------------------------------------------------------------
# The five routines. Each checks its own preconditions and, if any are
# unmet, records "skipped" with an exact reason and returns -- a skip is not
# a failure. Every real invocation writes its output to its own truncated
# log ($LOGS_DIR/<name>.log) first, then the routine derives its summary by
# reading that log back, so what is recorded always matches what actually
# ran.
#
# Each sets RESULT_STATUS, RESULT_REASON, RESULT_ARTIFACT, RESULT_SUMMARY,
# RESULT_EXIT_CODE as globals rather than returning them, because bash has
# no clean way to return five values from a function.
# --------------------------------------------------------------------------

routine_focus_export() {
  local gw="$BIN_DIR/tokenfuse-gateway" traces_dir="$STACK_UP_HOME/traces/gateway"
  if [ ! -x "$gw" ]; then
    RESULT_STATUS=skipped; RESULT_EXIT_CODE=0
    RESULT_REASON="missing executable $gw"
    return
  fi
  if [ ! -d "$traces_dir" ]; then
    RESULT_STATUS=skipped; RESULT_EXIT_CODE=0
    RESULT_REASON="missing traces directory $traces_dir"
    return
  fi
  # An empty trace directory is an unmet precondition, not a failure:
  # focus-export exits 1 with "no calls found in the trace" when there are
  # zero rows, byte-identical to a real error, so a fresh box would read as
  # a broken routine for days until the gateway sees its first traffic. No
  # Parquet segments yet -> nothing to export -> skip, with the reason.
  local segment
  segment="$(find "$traces_dir" -name '*.parquet' -print 2>/dev/null | head -n1)"
  if [ -z "$segment" ]; then
    RESULT_STATUS=skipped; RESULT_EXIT_CODE=0
    RESULT_REASON="no Parquet trace segments in $traces_dir yet (the gateway has recorded no traffic)"
    return
  fi

  local out="$OUT_DIR/focus-$(date -u +%Y%m%d).csv"
  local log="$LOGS_DIR/focus-export.log"
  : > "$log"
  "$gw" focus-export --traces "$traces_dir" --out "$out" >"$log" 2>&1
  local rc=$?
  RESULT_EXIT_CODE=$rc

  if [ "$rc" -eq 0 ] && [ -f "$out" ]; then
    local data
    data="$(python3 -c '
import sys
with open(sys.argv[1], newline="") as f:
    n = sum(1 for _ in f)
print(max(n - 1, 0))
' "$out")"
    RESULT_STATUS=ok
    RESULT_ARTIFACT="out/$(basename "$out")"
    RESULT_SUMMARY="$data data row(s) exported to $(basename "$out")"
  else
    RESULT_STATUS=error
    RESULT_REASON="$(tail -n1 "$log" 2>/dev/null)"
    RESULT_SUMMARY="tokenfuse-gateway focus-export exited $rc"
  fi
}

routine_qryx_trend() {
  local qryx="$BIN_DIR/qryx"
  local scan_path="${ROUTINE_QRYX_SCAN_PATH:-$STACK_UP_HOME/repos}"
  if [ ! -x "$qryx" ]; then
    RESULT_STATUS=skipped; RESULT_EXIT_CODE=0
    RESULT_REASON="missing executable $qryx"
    return
  fi
  if [ ! -d "$scan_path" ]; then
    RESULT_STATUS=skipped; RESULT_EXIT_CODE=0
    RESULT_REASON="scan path $scan_path does not exist (set ROUTINE_QRYX_SCAN_PATH in $CONFIG_FILE)"
    return
  fi

  local evidence="$OUT_DIR/qryx-evidence.jsonl"
  local log="$LOGS_DIR/qryx-trend.log"
  : > "$log"

  # No --fail-on/--fail-on-new/--policy is passed below, and that is
  # deliberate, not an oversight: read against Qryx/cmd/qryx/main.go, `qryx
  # scan` only ever exits non-zero for FINDINGS when one of those flags is
  # given. Without them (as here) it exits 0 on a completed scan no matter
  # what it finds, and non-zero only for a genuine usage/tool error -- so
  # "findings are still a successful governance run" already holds simply
  # because we never pass a flag that would make findings fail the exit
  # code in the first place. Same story for `qryx trend`: it only exits
  # non-zero (3) with --fail-on-regression, which is not passed either.
  "$qryx" scan --save-evidence "$evidence" "$scan_path" >>"$log" 2>&1
  local scan_rc=$?
  if [ "$scan_rc" -ne 0 ]; then
    RESULT_EXIT_CODE=$scan_rc
    RESULT_STATUS=error
    RESULT_REASON="$(tail -n1 "$log" 2>/dev/null)"
    RESULT_SUMMARY="qryx scan exited $scan_rc"
    return
  fi

  echo "--- qryx trend ---" >> "$log"
  "$qryx" trend "$evidence" >>"$log" 2>&1
  local trend_rc=$?
  RESULT_EXIT_CODE=$trend_rc
  if [ "$trend_rc" -eq 0 ]; then
    RESULT_STATUS=ok
    [ -f "$evidence" ] && RESULT_ARTIFACT="out/$(basename "$evidence")"
    RESULT_SUMMARY="$(tail -n1 "$log" 2>/dev/null)"
  else
    RESULT_STATUS=error
    RESULT_REASON="$(tail -n1 "$log" 2>/dev/null)"
    RESULT_SUMMARY="qryx trend exited $trend_rc"
  fi
}

routine_verdryx_drift() {
  local vx="$BIN_DIR/verdryx" db="$TAIPAN_HOME/verdryx.db"
  if [ ! -x "$vx" ]; then
    RESULT_STATUS=skipped; RESULT_EXIT_CODE=0
    RESULT_REASON="missing executable $vx"
    return
  fi
  if [ ! -f "$db" ]; then
    RESULT_STATUS=skipped; RESULT_EXIT_CODE=0
    RESULT_REASON="missing store $db"
    return
  fi
  if [ -z "${ROUTINE_VERDRYX_BASELINE:-}" ]; then
    RESULT_STATUS=skipped; RESULT_EXIT_CODE=0
    RESULT_REASON="ROUTINE_VERDRYX_BASELINE is not set; set it in $CONFIG_FILE"
    return
  fi

  local log="$LOGS_DIR/verdryx-drift.log"
  : > "$log"
  # verdryx/cli.py's _cmd_drift never calls sys.exit() on the verdict itself
  # (on-track or regressed): it only _die()s (exit 1) for a real error --
  # no such baseline, the baseline's eval run gone, or no eval runs to
  # compare. So "regressed" is status ok here for the same reason as qryx
  # above: the tool's own exit code already treats detecting a regression
  # as success.
  VERDRYX_DB="$db" "$vx" drift --baseline "$ROUTINE_VERDRYX_BASELINE" \
    --window "${ROUTINE_VERDRYX_WINDOW:-5}" >>"$log" 2>&1
  local rc=$?
  RESULT_EXIT_CODE=$rc
  if [ "$rc" -eq 0 ]; then
    local verdict
    verdict="$(sed -n 's/.*verdict:[[:space:]]*//p' "$log" | head -n1 | tr -d '[:space:]')"
    [ -n "$verdict" ] || verdict="unknown"
    RESULT_STATUS=ok
    RESULT_SUMMARY="verdict: $verdict"
  else
    RESULT_STATUS=error
    RESULT_REASON="$(tail -n1 "$log" 2>/dev/null)"
    RESULT_SUMMARY="verdryx drift exited $rc"
  fi
}

routine_idryx_detect() {
  local idryx="$BIN_DIR/idryx"
  if [ ! -x "$idryx" ]; then
    RESULT_STATUS=skipped; RESULT_EXIT_CODE=0
    RESULT_REASON="missing executable $idryx"
    return
  fi
  if [ ! -f "$EVENTS_FILE" ]; then
    RESULT_STATUS=skipped; RESULT_EXIT_CODE=0
    RESULT_REASON="missing events file $EVENTS_FILE"
    return
  fi

  local out="$OUT_DIR/idryx-detect-latest.json"
  local log="$LOGS_DIR/idryx-detect.log"
  : > "$log"
  # idryx detect exits 0 regardless of alert count (verified in
  # Idryx/cmd/idryx/main.go's runDetect: it returns a non-nil error only for
  # a real usage/graph-building/output failure, never for the alerts it
  # found), so no findings-vs-error split is needed here.
  "$idryx" detect --load "tokenfuse:$EVENTS_FILE" --format json >"$out" 2>"$log"
  local rc=$?
  RESULT_EXIT_CODE=$rc
  if [ "$rc" -eq 0 ]; then
    local count
    count="$(python3 -c '
import json
import sys
try:
    with open(sys.argv[1]) as f:
        print(len(json.load(f)))
except Exception:
    print("unknown")
' "$out")"
    RESULT_STATUS=ok
    RESULT_ARTIFACT="out/$(basename "$out")"
    RESULT_SUMMARY="$count alert(s)"
  else
    RESULT_STATUS=error
    RESULT_REASON="$(tail -n1 "$log" 2>/dev/null)"
    RESULT_SUMMARY="idryx detect exited $rc"
  fi
}

routine_mockryx_drill() {
  local mx="$BIN_DIR/mockryx"
  local scenarios="${ROUTINE_DRILL_SCENARIOS:-$STACK_UP_HOME/repos/mockryx/scenarios}"
  if [ ! -x "$mx" ]; then
    RESULT_STATUS=skipped; RESULT_EXIT_CODE=0
    RESULT_REASON="missing executable $mx"
    return
  fi
  if ! curl -fsS -m 3 -o /dev/null "http://127.0.0.1:4100/healthz" 2>/dev/null; then
    RESULT_STATUS=skipped; RESULT_EXIT_CODE=0
    RESULT_REASON="no healthy gateway at http://127.0.0.1:4100/healthz"
    return
  fi
  if [ ! -d "$scenarios" ]; then
    RESULT_STATUS=skipped; RESULT_EXIT_CODE=0
    RESULT_REASON="scenarios directory $scenarios does not exist (set ROUTINE_DRILL_SCENARIOS in $CONFIG_FILE)"
    return
  fi

  local out="$OUT_DIR/drill-$(date -u +%Y%m%dT%H%M%SZ).json"
  local log="$LOGS_DIR/mockryx-drill.log"
  : > "$log"
  # Flags before the positional dir: mockryx's flag set stops parsing at the
  # first non-flag token (see cmd/mockryx/main.go), so `run <dir> --gateway
  # X` would leave --gateway unset and strand <dir>. Only this order works.
  "$mx" run --gateway "http://127.0.0.1:4100" --save "$out" "$scenarios" >"$log" 2>&1
  local rc=$?
  RESULT_EXIT_CODE=$rc
  [ -f "$out" ] && RESULT_ARTIFACT="out/$(basename "$out")"
  case "$rc" in
    0) RESULT_STATUS=ok;       RESULT_SUMMARY="$(tail -n1 "$log" 2>/dev/null)" ;;
    1) RESULT_STATUS=findings; RESULT_SUMMARY="$(tail -n1 "$log" 2>/dev/null)" ;;
    *) RESULT_STATUS=error
       RESULT_REASON="$(tail -n1 "$log" 2>/dev/null)"
       RESULT_SUMMARY="mockryx run exited $rc" ;;
  esac
}

# --------------------------------------------------------------------------
# run <name>
# --------------------------------------------------------------------------

cmd_run() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    echo "stack-up: run needs a routine name (one of: ${ROUTINE_NAMES[*]})" >&2
    return 2
  fi
  if ! is_known_routine "$name"; then
    echo "stack-up: unknown routine '$name' (one of: ${ROUTINE_NAMES[*]})" >&2
    return 2
  fi

  ensure_dirs
  load_config
  acquire_lock "$name" || return 1

  local started finished
  started="$(now_rfc3339)"

  RESULT_STATUS=error
  RESULT_REASON=""
  RESULT_ARTIFACT=""
  RESULT_SUMMARY=""
  RESULT_EXIT_CODE=1

  case "$name" in
    focus-export)  routine_focus_export ;;
    qryx-trend)    routine_qryx_trend ;;
    verdryx-drift) routine_verdryx_drift ;;
    idryx-detect)  routine_idryx_detect ;;
    mockryx-drill) routine_mockryx_drill ;;
  esac

  finished="$(now_rfc3339)"
  write_record "$name" "$started" "$finished" "$RESULT_EXIT_CODE" "$RESULT_STATUS" \
    "$RESULT_REASON" "$RESULT_ARTIFACT" "$RESULT_SUMMARY"

  log "$name: $RESULT_STATUS -- ${RESULT_SUMMARY:-${RESULT_REASON:-no detail}}"

  [ "$RESULT_STATUS" = "error" ] && return 1
  return 0
}

# --------------------------------------------------------------------------
# list / status
# --------------------------------------------------------------------------

# timer_installed <name> -> 0 if a timer/plist for it exists at the
# resolved unit directory (honors ROUTINES_UNIT_DIR, same as install/
# uninstall, so a scratch-dir install shows up here too).
timer_installed() {
  local name="$1" dir
  dir="$(resolve_unit_dir)"
  if is_macos; then
    [ -f "$dir/dev.taipanbox.stack-up.routine-$name.plist" ]
  else
    [ -f "$dir/stack-up-routine-$name.timer" ]
  fi
}

# last_status_line <name> -> one human-readable line from status/<name>.json,
# or "never run".
last_status_line() {
  local f="$STATUS_DIR/$1.json"
  if [ ! -f "$f" ]; then
    echo "never run"
    return
  fi
  python3 - "$f" <<'PY'
import json
import sys

try:
    with open(sys.argv[1]) as fh:
        r = json.load(fh)
except Exception as e:
    print(f"status file unreadable ({e})")
    raise SystemExit

status = r.get("status", "?")
finished = r.get("finished_at", "?")
reason = r.get("reason") or ""
summary = r.get("summary") or ""
detail = reason if status in ("skipped", "error") and reason else summary
print(f"{status:<8} {finished}  {detail}")
PY
}

cmd_list() {
  ensure_dirs
  printf '%-16s %-10s %s\n' "ROUTINE" "TIMER" "LAST RUN"
  local n
  for n in "${ROUTINE_NAMES[@]}"; do
    local timer="no"
    timer_installed "$n" && timer="yes"
    printf '%-16s %-10s %s\n' "$n" "$timer" "$(last_status_line "$n")"
  done
}

cmd_status() {
  cmd_list
  echo
  log "scheduler state (filtered to stack-up's own routines):"
  if is_macos; then
    if have launchctl; then
      launchctl print "gui/$(id -u)" 2>/dev/null | grep -i "stack-up.routine" \
        || echo "  (none registered)"
    else
      echo "  (launchctl not found)"
    fi
  elif have systemctl; then
    if [ "$(id -u)" -eq 0 ]; then
      systemctl list-timers --all 2>/dev/null | grep -i "stack-up-routine" \
        || echo "  (none found)"
    else
      systemctl --user list-timers --all 2>/dev/null | grep -i "stack-up-routine" \
        || echo "  (none found)"
    fi
  else
    echo "  (no supported scheduler -- systemd or launchd -- found on this host)"
  fi
}

# --------------------------------------------------------------------------
# install / uninstall
#
# Two backends, chosen by OS: systemd units on Linux, launchd plists on
# macOS. ROUTINES_UNIT_DIR overrides where files are written/read and, when
# set, skips touching the real scheduler entirely -- a test generates unit
# files into a scratch directory and inspects them with nothing registered
# anywhere real.
# --------------------------------------------------------------------------

# resolve_unit_dir -> the directory unit files are written to and read from.
resolve_unit_dir() {
  if [ -n "${ROUTINES_UNIT_DIR:-}" ]; then
    echo "$ROUTINES_UNIT_DIR"
    return
  fi
  if is_macos; then
    echo "$HOME/Library/LaunchAgents"
  elif [ "$(id -u)" -eq 0 ]; then
    echo "/etc/systemd/system"
  else
    echo "$HOME/.config/systemd/user"
  fi
}

# sysctl_cmd <args...> - systemctl, scoped --user unless running as root.
# A tiny wrapper instead of an optional-flag array: an empty array element
# under `set -u` is an unbound-variable error on bash < 4.4 (this repo's
# baseline, matching up.sh's own `set -uo pipefail`), so the "maybe --user"
# flag is branched here instead of built as `("${maybe_user_flag[@]}")`.
sysctl_cmd() {
  if [ "$(id -u)" -eq 0 ]; then
    systemctl "$@"
  else
    systemctl --user "$@"
  fi
}

# record_installed <path...> - merge new paths into the manifest, deduped
# and sorted, so re-running install (e.g. later with --with-drill) adds to
# it instead of clobbering what an earlier install recorded.
record_installed() {
  [ $# -eq 0 ] && return 0
  mkdir -p "$ROUTINES_DIR"
  python3 - "$INSTALLED_MANIFEST" "$@" <<'PY'
import sys

manifest_path = sys.argv[1]
new_paths = sys.argv[2:]

existing = []
try:
    with open(manifest_path) as f:
        existing = [line.rstrip("\n") for line in f if line.strip()]
except FileNotFoundError:
    pass

merged = sorted(set(existing) | set(new_paths))
with open(manifest_path, "w") as f:
    for p in merged:
        f.write(p + "\n")
PY
}

install_systemd_unit() {  # <name> <unit_dir> -> appends to NEW_PATHS
  local name="$1" dir="$2"
  local svc="$dir/stack-up-routine-$name.service"
  local timer="$dir/stack-up-routine-$name.timer"
  local onc_time oncalendar
  onc_time="$(printf '%02d:%02d:00' "$(routine_hour "$name")" "$(routine_minute "$name")")"
  if routine_is_weekly "$name"; then
    oncalendar="Mon *-*-* $onc_time"
  else
    oncalendar="*-*-* $onc_time"
  fi

  cat > "$svc" <<EOF
[Unit]
Description=stack-up governance routine: $name

[Service]
Type=oneshot
ExecStart=/bin/bash $SCRIPT_PATH run $name
EOF

  cat > "$timer" <<EOF
[Unit]
Description=stack-up governance routine timer: $name

[Timer]
OnCalendar=$oncalendar
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
EOF

  NEW_PATHS+=("$svc" "$timer")
}

install_launchd_unit() {  # <name> <unit_dir> -> appends to NEW_PATHS
  local name="$1" dir="$2"
  local label="dev.taipanbox.stack-up.routine-$name"
  local plist="$dir/$label.plist"
  local hour minute weekday_block=""
  hour="$(routine_hour "$name")"
  minute="$(routine_minute "$name")"
  if routine_is_weekly "$name"; then
    weekday_block="        <key>Weekday</key>
        <integer>1</integer>
"
  fi

  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT_PATH</string>
        <string>run</string>
        <string>$name</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
$weekday_block        <key>Hour</key>
        <integer>$hour</integer>
        <key>Minute</key>
        <integer>$minute</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$LOGS_DIR/$name.scheduler.log</string>
    <key>StandardErrorPath</key>
    <string>$LOGS_DIR/$name.scheduler.log</string>
</dict>
</plist>
PLIST

  NEW_PATHS+=("$plist")
}

activate_systemd() {  # <name...>
  sysctl_cmd daemon-reload || warn "install: systemctl daemon-reload failed"
  local n
  for n in "$@"; do
    sysctl_cmd enable --now "stack-up-routine-$n.timer" \
      || warn "install: could not enable stack-up-routine-$n.timer"
  done
}

activate_launchd() {  # <name...>
  local uid label plist n
  uid="$(id -u)"
  for n in "$@"; do
    label="dev.taipanbox.stack-up.routine-$n"
    plist="$(resolve_unit_dir)/$label.plist"
    if ! launchctl bootstrap "gui/$uid" "$plist" 2>/dev/null; then
      launchctl load -w "$plist" 2>/dev/null \
        || { warn "install: could not load $label via bootstrap or load -w"; continue; }
    fi
    launchctl enable "gui/$uid/$label" 2>/dev/null \
      || warn "install: could not enable $label"
  done
}

cmd_install() {
  local with_drill=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --with-drill) with_drill=1 ;;
      *) echo "stack-up: install: unknown option '$1' (try --help)" >&2; return 2 ;;
    esac
    shift
  done

  if [ "$with_drill" -eq 1 ]; then
    warn "install --with-drill: mockryx-drill's weekly timer sends REAL traffic"
    warn "through your local gateway to whatever LLM provider is configured"
    warn "there. That traffic can spend that provider's money, and the drill is"
    warn "deliberately built to trip your policies -- that is what a fire drill"
    warn "is for. Installing its timer alongside the four safe routines."
  fi

  ensure_dirs

  local targets=("${DEFAULT_ROUTINES[@]}")
  [ "$with_drill" -eq 1 ] && targets+=(mockryx-drill)

  local unit_dir
  unit_dir="$(resolve_unit_dir)"
  mkdir -p "$unit_dir" || die "install: could not create $unit_dir"

  NEW_PATHS=()
  local n
  for n in "${targets[@]}"; do
    if is_macos; then
      install_launchd_unit "$n" "$unit_dir"
    else
      install_systemd_unit "$n" "$unit_dir"
    fi
  done

  [ "${#NEW_PATHS[@]}" -gt 0 ] && record_installed "${NEW_PATHS[@]}"

  if [ -z "${ROUTINES_UNIT_DIR:-}" ]; then
    if is_macos; then
      activate_launchd "${targets[@]}"
    elif have systemctl; then
      activate_systemd "${targets[@]}"
    else
      warn "install: no supported scheduler (systemd or launchd) found; unit files were written but nothing was activated."
    fi
  else
    log "install: ROUTINES_UNIT_DIR is set ($ROUTINES_UNIT_DIR); wrote unit files there and left the real scheduler untouched."
  fi

  log "install: done. '$SCRIPT_PATH status' shows it."
}

cmd_uninstall() {
  ensure_dirs
  if [ ! -f "$INSTALLED_MANIFEST" ]; then
    log "uninstall: nothing to do (no $INSTALLED_MANIFEST)"
    return 0
  fi

  local paths=()
  while IFS= read -r p; do
    paths+=("$p")
  done < <(grep -v '^[[:space:]]*$' "$INSTALLED_MANIFEST" 2>/dev/null)

  if [ "${#paths[@]}" -eq 0 ]; then
    log "uninstall: manifest is empty; nothing to remove"
    rm -f "$INSTALLED_MANIFEST"
    return 0
  fi

  if [ -z "${ROUTINES_UNIT_DIR:-}" ]; then
    # Only deactivate routines this manifest actually names, derived from
    # the recorded filenames themselves rather than looping every known
    # routine name and hoping disable/bootout no-ops quietly on the rest.
    local names_in_manifest n
    names_in_manifest="$(printf '%s\n' "${paths[@]}" | grep -oE 'routine-[a-z-]+' | sed 's/^routine-//' | sort -u)"
    for n in $names_in_manifest; do
      if is_macos; then
        launchctl bootout "gui/$(id -u)/dev.taipanbox.stack-up.routine-$n" >/dev/null 2>&1 \
          || launchctl unload -w "$HOME/Library/LaunchAgents/dev.taipanbox.stack-up.routine-$n.plist" >/dev/null 2>&1
      elif have systemctl; then
        sysctl_cmd disable --now "stack-up-routine-$n.timer" >/dev/null 2>&1
      fi
    done
    if ! is_macos && have systemctl; then
      sysctl_cmd daemon-reload >/dev/null 2>&1
    fi
  else
    log "uninstall: ROUTINES_UNIT_DIR is set; skipping launchctl/systemctl and just removing the files."
  fi

  local p removed=0
  for p in "${paths[@]}"; do
    if [ -e "$p" ]; then
      rm -f "$p" && removed=$((removed + 1))
    fi
  done

  rm -f "$INSTALLED_MANIFEST"
  log "uninstall: removed $removed file(s) that install created."
}

# --------------------------------------------------------------------------
# Dispatch
# --------------------------------------------------------------------------

[ $# -gt 0 ] || { usage >&2; exit 2; }

case "$1" in
  -h|--help) usage; exit 0 ;;
  list)      shift; cmd_list "$@" ;;
  run)       shift; cmd_run "$@" ;;
  install)   shift; cmd_install "$@" ;;
  uninstall) shift; cmd_uninstall "$@" ;;
  status)    shift; cmd_status "$@" ;;
  *) echo "stack-up: unknown command '$1' (try --help)" >&2; exit 2 ;;
esac
