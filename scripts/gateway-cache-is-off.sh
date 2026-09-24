#!/usr/bin/env bash
# Every gateway start in this launcher turns the semantic response cache off.
#
# WHY
#
# Unset, tokenfuse's gateway enables its semantic response cache in shadow
# mode (tokenfuse v1.0.4 crates/gateway/src/main.rs:992-997): every call takes
# one global mutex, walks up to 10,000 cached entries computing cosine
# similarity, serves nothing, and appends another entry. Measured 2026-09-24
# on a 4-core appliance: 50 agents gave 177 calls/s with 403 refusals, 79-92%
# of gateway CPU inside SemanticCache::get; with TOKENFUSE_CACHE=off, 1102
# calls/s, zero refusals, no slowdown over time. tokenfuse#319.
#
# WHY A GATE AND NOT A COMMENT
#
# Because the default is silent: a gateway started with neither variable set
# still comes up, answers health checks, and serves traffic. Nothing about a
# working stand tells an operator that most of its CPU is going to a cache
# that never serves a hit. The check that would catch a future gateway start
# missing this cannot be "did it come up".
#
# WHAT IT LOOKS AT
#
# Every line that launches the gateway binary, and the environment block
# immediately above it, which in this launcher is a backslash-continued
# prefix. The gateway is started from a variable ($GATEWAY_BIN) rather than by
# name, so this resolves that assignment first rather than grepping for a
# literal, the same approach scripts/gateway-decides-its-upstream.sh takes for
# the neighbouring precondition.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
# It does not require any particular OTHER cache setting; it requires only
# that TOKENFUSE_CACHE="off" is present on every gateway start. A future
# stack-up that turns the cache back on deliberately, with an argument made
# for it, changes this gate's expectation, not this launcher's silence.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$ROOT/up.sh"

fail() { printf 'gateway-cache-is-off: %s\n' "$*" >&2; exit 1; }

[[ -f "$LAUNCHER" ]] || fail "no up.sh at $LAUNCHER, so this measured nothing"

# The variable the launcher starts the gateway through. Resolved rather than
# assumed: a renamed variable must make this gate say it measured nothing, not
# pass by finding no launches.
BIN_VAR="$(grep -oE '^GATEWAY_BIN="[^"]*"' "$LAUNCHER" | head -1)"
[[ -n "$BIN_VAR" ]] || fail "no GATEWAY_BIN assignment in up.sh, so this measured nothing"

# Lines that actually launch it: "$GATEWAY_BIN" ...
#
# Read with a plain loop rather than `mapfile`, which is bash 4 and therefore
# absent on macOS's own /bin/bash 3.2. It must be the COMMAND position, not
# any mention: anchored to the start of the line, which is where a command
# sits and an argument does not (the same anchoring
# gateway-decides-its-upstream.sh uses, for the same reason).
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
[ "$LAUNCH_COUNT" -gt 0 ] || fail "up.sh launches \$GATEWAY_BIN nowhere, so this measured nothing"

problems=0
for line in $LAUNCH_LINES; do
  # Walk back over the backslash-continued environment prefix that belongs to
  # this launch. A line NOT ending in a backslash ends the prefix, which is
  # the same rule the shell itself applies.
  start="$line"
  while [ "$start" -gt 1 ]; do
    prev=$(( start - 1 ))
    prev_text="$(sed -n "${prev}p" "$LAUNCHER")"
    [[ "$prev_text" =~ \\$ ]] || break
    start="$prev"
  done

  block="$(sed -n "${start},${line}p" "$LAUNCHER")"
  if ! grep -qE 'TOKENFUSE_CACHE="off"' <<<"$block"; then
    printf 'up.sh:%s: this gateway start does not set TOKENFUSE_CACHE="off".\n' "$line" >&2
    printf '  Unset, the gateway enables its semantic cache in shadow mode: one global\n' >&2
    printf '  mutex per call, up to 10,000 entries compared, nothing served. tokenfuse#319.\n' >&2
    problems=$(( problems + 1 ))
  fi
done

if [ "$problems" -gt 0 ]; then
  fail "$problems gateway start(s) do not turn the semantic cache off"
fi

printf 'every gateway start in up.sh turns the semantic cache off (%d checked)\n' "$LAUNCH_COUNT"
