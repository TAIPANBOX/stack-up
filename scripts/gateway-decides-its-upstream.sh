#!/usr/bin/env bash
# Every gateway start in this launcher says which upstream it is using.
#
# WHY
#
# tokenfuse's gateway refuses to start unless it is told one of two things:
# TOKENFUSE_UPSTREAM=<url>, forward to a real provider, or TOKENFUSE_ALLOW_STUB=1,
# answer from a built-in stub and meter a fixed 1000 input / 500 output tokens as
# spend. Neither means it exits, because a gateway that quietly stubbed would
# invent both the model answers and the money. That precondition landed in
# tokenfuse on 2026-07-25 and nothing in THIS repository moved with it, so
# `./up.sh` died at "gateway did not come up" for a month.
#
# WHY A GATE AND NOT A COMMENT
#
# Because the failure is invisible on a developer's own machine. A gateway
# binary installed before 2026-07-25 starts perfectly well without either
# variable, so whoever last ran this launcher saw it work while a stranger
# cloning it saw the only command the README gives them fail. The check that
# would have caught it cannot be "did it run here".
#
# It is also a repeat: taipan set neither variable from 2026-07-25 to
# 2026-08-20 and records that in its own test. One repository learning a lesson
# is not the estate learning it.
#
# WHAT IT LOOKS AT
#
# Every line that launches the gateway binary, and the environment block
# immediately above it, which in this launcher is a backslash-continued prefix.
# The gateway is started from a variable ($GATEWAY_BIN) rather than by name, so
# this resolves that assignment first rather than grepping for a literal.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
# It does not require the stub specifically. A future stack-up that pointed at a
# real provider would set TOKENFUSE_UPSTREAM and must pass unchanged: the
# invariant is that the choice is MADE, not which way it went.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$ROOT/up.sh"

fail() { printf 'gateway-decides-its-upstream: %s\n' "$*" >&2; exit 1; }

[[ -f "$LAUNCHER" ]] || fail "no up.sh at $LAUNCHER, so nothing was measured"

# The variable the launcher starts the gateway through. Resolved rather than
# assumed: a renamed variable must make this gate say it measured nothing, not
# pass by finding no launches.
BIN_VAR="$(grep -oE '^GATEWAY_BIN="[^"]*"' "$LAUNCHER" | head -1)"
[[ -n "$BIN_VAR" ]] || fail "no GATEWAY_BIN assignment in up.sh, so nothing was measured"

# Lines that actually launch it: "$GATEWAY_BIN" ...
#
# Read with a plain loop rather than `mapfile`, which is bash 4 and therefore
# absent on macOS's own /bin/bash 3.2. A gate that only runs on the maintainer's
# shell is the same class of mistake as the fault this file exists to catch.
# It must be the COMMAND position, not any mention. The first version of this
# gate matched every use of the variable and reported three faults where there
# are two: the third was `[ -x "$GATEWAY_BIN" ]`, an installability test with no
# environment prefix and nothing to decide. A gate that fires on a correct line
# is deleted by whoever is unblocking a release, so the pattern is anchored to
# the start of the line, which is where a command sits and an argument does not.
LAUNCH_LINES=""
LAUNCH_COUNT=0
while IFS= read -r n; do
  LAUNCH_LINES="$LAUNCH_LINES $n"
  LAUNCH_COUNT=$(( LAUNCH_COUNT + 1 ))
done <<EOF
$(
  # shellcheck disable=SC2016
  # The $ is literal on purpose: this searches for the TEXT "$GATEWAY_BIN" in
  # another script, and expanding it here would search for this shell's own
  # (empty) variable and quietly match nothing, which is the silent-pass shape
  # gates-have-teeth.sh exists to catch.
  grep -nE '^[[:space:]]*"\$GATEWAY_BIN"' "$LAUNCHER" | cut -d: -f1
)
EOF
[ "$LAUNCH_COUNT" -gt 0 ] || fail "up.sh launches \$GATEWAY_BIN nowhere, so nothing was measured"

problems=0
for line in $LAUNCH_LINES; do
  # Walk back over the backslash-continued environment prefix that belongs to
  # this launch. A line NOT ending in a backslash ends the prefix, which is the
  # same rule the shell itself applies.
  start="$line"
  while [ "$start" -gt 1 ]; do
    prev=$(( start - 1 ))
    prev_text="$(sed -n "${prev}p" "$LAUNCHER")"
    [[ "$prev_text" =~ \\$ ]] || break
    start="$prev"
  done

  block="$(sed -n "${start},${line}p" "$LAUNCHER")"
  if ! grep -qE 'TOKENFUSE_(ALLOW_STUB|UPSTREAM)=' <<<"$block"; then
    printf 'up.sh:%s: this gateway start sets neither TOKENFUSE_UPSTREAM nor TOKENFUSE_ALLOW_STUB.\n' "$line" >&2
    printf '  The gateway refuses to start with neither, and ./up.sh dies at "gateway did not come up".\n' >&2
    problems=$(( problems + 1 ))
  fi
done

if [ "$problems" -gt 0 ]; then
  fail "$problems gateway start(s) do not say which upstream they use"
fi

printf 'every gateway start in up.sh names its upstream (%d checked)\n' "$LAUNCH_COUNT"
