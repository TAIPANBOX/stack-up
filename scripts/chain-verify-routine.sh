#!/usr/bin/env bash
# The chain-verify routine says what the verifier found, and never calls a
# standing break ok.
#
# WHY
#
# `agent-conform watch-dir` (agent-stack-go v1.1.0) announces each break ONCE,
# through a state file, and exits 0 on every run after the first even though the
# stream is still broken. A routine that maps exit 0 to "ok" therefore records a
# green history from the second night on, over a bus whose chain was cut on the
# first. The tool prints a FAIL line for every break it sees, announced or not,
# and the routine reads that line: exit 0 with a FAIL line is "findings".
#
# WHAT IT CHECKS, against a stand-in `agent-conform` in a scratch home whose exit
# code and output this script chooses (so it needs no built verifier and no
# network, and a case cannot be skipped for lack of one):
#
#   1. no verifier installed: skipped, with the reason, exit 0.
#   2. an events directory with no stream: skipped, not an error.
#   3. the verifier exits 0 and prints no FAIL line: ok.
#   4. it exits 1 (a NEW break): findings, and the reason names the break.
#   5. it exits 0 but prints a FAIL line (a break it announced earlier): findings,
#      saying so, NOT ok.
#   6. it exits 2 (it could not do its job): error, the routine exits 1.
#   7. the routine hands the tool the bus as its one directory, its own output
#      named agent-conform.ndjson there (the name is the source its events claim)
#      and a state file that is not an event stream and not in the bus.
#   8. `install` schedules it, daily, at 06:52, in the default set; the
#      mockryx-drill timer is still the only one that is not.
#
# WHAT IT DOES NOT DO
#
# It does not run the real verifier: that a flipped byte on a real bus becomes a
# chain_broken event, and that the second run does not announce it again, was
# shown against the real binary by hand in the pull request that added this
# routine, and agent-stack-go's own tests hold the tool's side.
#
# AND IT REFUSES TO REPORT OK ON NOTHING
#
# No routines.sh, or no chain-verify routine in it, and this says it measured
# nothing and fails.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

ROUTINES="routines.sh"
[ -f "$ROUTINES" ] || { echo "chain-verify-routine: no $ROUTINES, so this measured nothing"; exit 1; }
grep -q '^routine_chain_verify() {' "$ROUTINES" \
  || { echo "chain-verify-routine: $ROUTINES has no routine_chain_verify, so this measured nothing"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export STACK_UP_HOME="$work/home" TAIPAN_HOME="$work/taipan"
mkdir -p "$STACK_UP_HOME/events" "$TAIPAN_HOME/bin"

fails=0
n=0
out=""
rc=0
bad() { fails=$((fails + 1)); printf 'FAIL: %s\n' "$1"; printf '%s\n' "$out" | head -5 | sed 's/^/      /'; }

# status_of: the status and reason the routine last recorded.
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2]) or "")' "$STACK_UP_HOME/routines/status/chain-verify.json" "$1" 2>/dev/null; }

# A stand-in verifier. It records the arguments it was given, prints what the
# case wants and exits with the code the case wants.
make_verifier() { # <exit-code> <output line...>
  local code="$1"; shift
  {
    printf '#!/bin/sh\n'
    printf 'printf "%%s\\n" "$@" > "%s/args"\n' "$work"
    for l in "$@"; do printf 'printf "%%s\\n" "%s"\n' "$l"; done
    printf 'exit %s\n' "$code"
  } > "$TAIPAN_HOME/bin/agent-conform"
  chmod +x "$TAIPAN_HOME/bin/agent-conform"
}

expect() { # <name> <exit> <status> <needle in reason or summary, may be empty>
  local name="$1" want_rc="$2" want_status="$3" needle="$4" got reason summary
  n=$((n + 1))
  out="$(./"$ROUTINES" run chain-verify 2>&1)"; rc=$?
  got="$(field status)"; reason="$(field reason)"; summary="$(field summary)"
  if [ "$rc" -ne "$want_rc" ]; then bad "$name: routine exit $rc, wanted $want_rc"; return; fi
  if [ "$got" != "$want_status" ]; then bad "$name: recorded status '$got', wanted '$want_status'"; return; fi
  if [ -n "$needle" ] && ! printf '%s %s' "$reason" "$summary" | grep -qF -- "$needle"; then
    bad "$name: the record does not say: $needle (reason: $reason | summary: $summary)"
  fi
}

# 1. no verifier installed.
expect "no verifier installed" 0 skipped "missing executable"

# 2. a verifier, and a bus with nothing on it.
make_verifier 0 "agent-conform watch-dir: 0 stream(s), 0 new alert(s) written (0 chain_broken)"
expect "an empty bus is skipped, not an error" 0 skipped "no event files"

# 3. a clean bus.
printf '{}\n' > "$STACK_UP_HOME/events/tokenfuse.ndjson"
make_verifier 0 "PASS tokenfuse.ndjson (hash chain: 5 chained, 1 head(s))" \
  "agent-conform watch-dir: 1 stream(s), 0 new alert(s) written (0 chain_broken)"
expect "a clean bus is ok" 0 ok "0 new alert(s)"

# 4. a NEW break.
make_verifier 1 "FAIL tokenfuse.ndjson:4: chain break (prev_hash_mismatch), 1 break(s) in all; alert pending" \
  "agent-conform watch-dir: 1 stream(s), 1 new alert(s) written (1 chain_broken)"
expect "a new break is findings, and names it" 0 findings "tokenfuse.ndjson:4"

# 5. THE ONE THAT MATTERS: the same break on the next run. The tool exits 0.
make_verifier 0 "FAIL tokenfuse.ndjson:4: chain break (prev_hash_mismatch), 1 break(s) in all; already reported" \
  "agent-conform watch-dir: 2 stream(s), 0 new alert(s) written (0 chain_broken)"
expect "a break already announced is still findings, not ok" 0 findings "already announced and still there"

# 6. the tool could not do its job.
make_verifier 2 "agent-conform watch-dir: read /nope: no such file"
expect "exit 2 is an error and the routine fails" 1 error "agent-conform watch-dir exited 2"

# 7. what the routine hands the tool.
make_verifier 0 "agent-conform watch-dir: 1 stream(s), 0 new alert(s) written (0 chain_broken)"
./"$ROUTINES" run chain-verify >/dev/null 2>&1
args="$(cat "$work/args" 2>/dev/null)"
n=$((n + 1))
want_args="$(printf '%s\n' watch-dir -out "$STACK_UP_HOME/events/agent-conform.ndjson" -state "$STACK_UP_HOME/routines/agent-conform.state.json" "$STACK_UP_HOME/events")"
if [ "$args" != "$want_args" ]; then
  out="got:
$args
wanted:
$want_args"
  bad "the verifier is not given the bus, its own agent-conform.ndjson and a state file outside the bus"
fi

# 8. scheduled daily at 06:52, by default; the drill is still the only opt-in.
unit_dir="$work/units"
ROUTINES_UNIT_DIR="$unit_dir" ./"$ROUTINES" install >/dev/null 2>&1
n=$((n + 1))
shopt -s nullglob
units=("$unit_dir"/*chain-verify*)
drill=("$unit_dir"/*mockryx-drill*)
shopt -u nullglob
if [ "${#units[@]}" -eq 0 ]; then
  out="$(ls "$unit_dir" 2>&1)"
  bad "install wrote no chain-verify unit, so it is not scheduled by default"
else
  n=$((n + 1))
  # launchd carries the minute as <integer>52</integer>, systemd as 06:52:00.
  if ! grep -qE '06:52:00|<integer>52</integer>' "${units[@]}"; then
    out="$(cat "${units[@]}")"
    bad "the chain-verify unit is not at 06:52"
  fi
  n=$((n + 1))
  if grep -qE 'Mon |<key>Weekday</key>' "${units[@]}"; then
    out="$(cat "${units[@]}")"
    bad "the chain-verify unit is weekly, and every routine but the drill is daily"
  fi
fi
n=$((n + 1))
if [ "${#drill[@]}" -gt 0 ]; then
  out="$(ls "$unit_dir")"
  bad "install without --with-drill scheduled the mockryx drill"
fi

if [ "$fails" -gt 0 ]; then
  printf 'FAIL: %d of %d chain-verify check(s) failed.\n' "$fails" "$n"
  exit 1
fi
printf 'OK: %d chain-verify checks: skipped with a reason, ok only when nothing is broken, a standing break is findings, a failed run is an error, and it is scheduled daily at 06:52.\n' "$n"
