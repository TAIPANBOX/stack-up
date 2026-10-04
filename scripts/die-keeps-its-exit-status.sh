#!/usr/bin/env bash
# up.sh exits with the status it was exiting with, and says a clean stop is a
# clean stop.
#
# WHY
#
# `die` prints its error and runs `exit 1`. up.sh sets an EXIT trap, and the
# trap's `cleanup` ended in a hard-coded `exit 0`, which replaces the status the
# script was exiting with. So from the moment the trap was armed, a refusal
# ("the gateway did not come up", "--run-budget-ceiling needs a gateway built
# from tokenfuse v1.5.0 or newer", "typryx wardryx-proxy did not come up")
# printed its error and exited 0, and anything driving the launcher (a script,
# a CI step, a supervisor) read a failed bring-up as a success. Measured
# 2026-10-04 while running the refusals of the 2026-10-04 releases: the exit
# status was 0 after each `error:` line.
#
# WHAT IT HOLDS, running the launcher's own `cleanup` and its own trap lines
# (cut out of up.sh, not copied):
#
#   1. Exiting with a failure status after the trap is armed, with nothing
#      started, leaves with that status.
#   2. The same with a service started: it is stopped AND the status survives.
#   3. SIGTERM and SIGINT are the operator stopping the stack on purpose:
#      status 0, services stopped.
#   4. Falling off the end is 0.
#   5. The hold loop's "a service died underneath us" path calls `cleanup 1`:
#      a stack that stopped because a plane died did not stop cleanly.
#
# AND IT REFUSES TO REPORT OK ON NOTHING
#
# No up.sh, no `cleanup` function, or no trap line naming it, and this says it
# measured nothing and fails.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

LAUNCHER="up.sh"
[ -f "$LAUNCHER" ] || { echo "die-keeps-its-exit-status: no $LAUNCHER, so this measured nothing"; exit 1; }

fn="$(sed -n '/^cleanup() {/,/^}/p' "$LAUNCHER")"
traps="$(grep -E '^trap .*cleanup' "$LAUNCHER")"
if [ -z "$fn" ]; then
  echo "die-keeps-its-exit-status: $LAUNCHER has no cleanup function, so this measured nothing"; exit 1
fi
if [ -z "$traps" ]; then
  echo "die-keeps-its-exit-status: $LAUNCHER arms no trap on cleanup, so this measured nothing"; exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/pids"

fails=0
n=0
bad() { fails=$((fails + 1)); printf 'FAIL: %s\n' "$1"; }

# run_case <name> <wanted status> <body>: a fresh bash that has the launcher's
# cleanup and trap lines, one stand-in service when asked, and then <body>.
run_case() {
  local name="$1" want="$2" body="$3" rc
  n=$((n + 1))
  rm -f "$work/svc.pid"
  bash -c "
    log() { :; }; warn() { :; }
    PIDS_DIR='$work/pids'
    STARTED=()
    $fn
    $traps
    $body
  " >/dev/null 2>&1
  rc=$?
  if [ "$rc" -ne "$want" ]; then
    bad "$name: exit $rc, wanted $want"
    return
  fi
  # A service the case started must be gone.
  if [ -f "$work/svc.pid" ] && kill -0 "$(cat "$work/svc.pid")" 2>/dev/null; then
    kill -KILL "$(cat "$work/svc.pid")" 2>/dev/null
    bad "$name: the started service was left running"
  fi
}

START="sleep 60 & echo \$! > '$work/svc.pid'; STARTED+=(\"svc:\$!:TERM\")"

run_case "a failure with nothing started"        3 "exit 3"
run_case "a failure with a service started"      4 "$START; exit 4"
run_case "SIGTERM is a deliberate stop"          0 "$START; kill -TERM \$\$; sleep 5"
run_case "SIGINT is a deliberate stop"           0 "$START; kill -INT \$\$; sleep 5"
run_case "falling off the end"                   0 "$START; true"
run_case "an explicit exit 0"                    0 "exit 0"

# 5. the hold loop.
n=$((n + 1))
if ! grep -qE '^[[:space:]]+cleanup 1$' "$LAUNCHER"; then
  bad "the hold loop does not call 'cleanup 1' when a service dies, so a stack that stopped because a plane died exits 0"
fi

if [ "$fails" -gt 0 ]; then
  printf 'FAIL: %d of %d exit-status check(s) failed.\n' "$fails" "$n"
  exit 1
fi
printf 'OK: %d exit-status checks: a failure keeps its status with and without a service started, a deliberate stop is 0, and a dead plane exits 1.\n' "$n"
