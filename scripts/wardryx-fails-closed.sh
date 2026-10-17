#!/usr/bin/env bash
# The gateway's policy decision point fails closed in this launcher, and the
# launcher stops when that point does not come up. Invariant 20.
#
# WHY
#
# The launcher sets the gateway to enforce a wardryx decision and set no fail
# mode. tokenfuse's default is open, so a wardryx that was slow, unreachable or
# dead turned every deny and every hold into an allow for as long as it stayed
# that way, visible only in a response header. The launcher made it worse: when
# wardryx did not come up it printed that the gateway would fail open and went
# on. A stranger cloning this repository got a stand that allowed what its own
# policy denied.
#
# WHAT IT HOLDS
#
# 1. Every gateway start ("$GATEWAY_BIN" at the command position, the mcp-broker
#    subcommand excluded as in the neighbouring gates) that sets
#    TOKENFUSE_WARDRYX_MODE also sets TOKENFUSE_WARDRYX_FAILMODE to the literal
#    "closed" in the same start block.
# 2. The wardryx health wait is `wait_health wardryx ... || die ...`, not a
#    warning. A wardryx that does not come up stops the launcher, and the EXIT
#    trap stops what it had started.
# 3. Nothing outside a comment says the gateway fails open, and the wardryx block
#    never turns WANT_POLICY off after the gateway is wired to it. A fetch or
#    build failure there is a stop too, not a quiet skip.
#
# WHAT IT DOES NOT HOLD
#
# A running gateway refusing a decision while wardryx is silent. That is
# tokenfuse's own test and needs a built gateway. This gate shows that the
# launcher hands the gateway the closed mode and stops when wardryx is missing.
#
# AND IT REFUSES TO REPORT OK ON NOTHING
#
# No up.sh, no gateway start wired to wardryx, no wardryx health wait, or no
# wardryx block: it says it measured nothing and fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$ROOT/up.sh"

fail() { printf 'wardryx-fails-closed: %s\n' "$*" >&2; exit 1; }

[[ -f "$LAUNCHER" ]] || fail "no up.sh at $LAUNCHER, so this measured nothing"

problems=0

# block_start <line> - the first line of the backslash-continued prefix that
# ends at <line> (the launch line itself when nothing continues into it).
block_start() {
  local start="$1" prev prev_text
  while [ "$start" -gt 1 ]; do
    prev=$(( start - 1 ))
    prev_text="$(sed -n "${prev}p" "$LAUNCHER")"
    [[ "$prev_text" =~ \\$ ]] || break
    start="$prev"
  done
  printf '%s\n' "$start"
}

# 1. The gateway starts that are wired to wardryx.
GATEWAY_STARTS=""
# The $ is literal: these search for the TEXT "$GATEWAY_BIN" in up.sh.
# shellcheck disable=SC2013,SC2016
for n in $(grep -nE '^[[:space:]]*"\$GATEWAY_BIN"' "$LAUNCHER" \
            | grep -vE ':[[:space:]]*"\$GATEWAY_BIN"[[:space:]]+mcp-broker([[:space:]]|$)' \
            | cut -d: -f1); do
  GATEWAY_STARTS="$GATEWAY_STARTS $n"
done
[ -n "$GATEWAY_STARTS" ] || fail "up.sh starts \$GATEWAY_BIN nowhere, so this measured nothing"

WIRED=0
for line in $GATEWAY_STARTS; do
  start="$(block_start "$line")"
  block="$(sed -n "${start},${line}p" "$LAUNCHER" | grep -vE '^[[:space:]]*#')"
  grep -qE 'TOKENFUSE_WARDRYX_MODE=' <<<"$block" || continue
  WIRED=$(( WIRED + 1 ))
  fail_mode="$(grep -oE 'TOKENFUSE_WARDRYX_FAILMODE=[^ \\]*' <<<"$block" | head -1)"
  if [ -z "$fail_mode" ]; then
    printf 'up.sh:%s: this gateway start is wired to wardryx but does not set TOKENFUSE_WARDRYX_FAILMODE,\n' "$line" >&2
    printf '  so tokenfuse'"'"'s default applies: open, which allows every decision wardryx cannot answer.\n' >&2
    problems=$(( problems + 1 ))
  elif [ "$fail_mode" != 'TOKENFUSE_WARDRYX_FAILMODE="closed"' ]; then
    printf 'up.sh:%s: %s, not closed.\n' "$line" "$fail_mode" >&2
    printf '  An open fail mode allows every decision wardryx cannot answer.\n' >&2
    problems=$(( problems + 1 ))
  fi
done
[ "$WIRED" -gt 0 ] || fail "no gateway start is wired to wardryx (TOKENFUSE_WARDRYX_MODE), so this measured nothing"

# 2. The wardryx health wait must stop the launcher when it fails.
WAITS=0
# Line numbers are single words, so word splitting is what is wanted here.
# shellcheck disable=SC2013
for n in $(grep -nE '^[[:space:]]*wait_health wardryx[[:space:]]' "$LAUNCHER" | cut -d: -f1); do
  WAITS=$(( WAITS + 1 ))
  text="$(sed -n "${n}p" "$LAUNCHER")"
  if ! grep -qE '\|\|[[:space:]]*die([[:space:]]|$)' <<<"$text"; then
    printf 'up.sh:%s: wardryx is waited for with a warning, not a stop. A wardryx that does not come up\n' "$n" >&2
    printf '  leaves the gateway, wired to it, refusing every decision while the launcher reports a stand.\n' >&2
    problems=$(( problems + 1 ))
  fi
done
[ "$WAITS" -gt 0 ] || fail "up.sh waits for wardryx nowhere, so this measured nothing"

# 3a. Nothing outside a comment says the gateway fails open.
open_text="$(grep -nEi 'fail(s|ing)?[ -]open' "$LAUNCHER" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
if [ -n "$open_text" ]; then
  while IFS= read -r hit; do
    printf 'up.sh:%s: says the gateway will fail open, which a stand with wardryx down must not claim as its plan.\n' "${hit%%:*}" >&2
    problems=$(( problems + 1 ))
  done <<<"$open_text"
fi

# 3b. The wardryx block never switches the policy plane off after the gateway is wired to it.
BLOCK_FROM="$(grep -nE '^# Wardryx \(optional\)' "$LAUNCHER" | cut -d: -f1 | head -1)"
BLOCK_TO="$(grep -nE '^# Idryx \(optional\)' "$LAUNCHER" | cut -d: -f1 | head -1)"
[ -n "$BLOCK_FROM" ] && [ -n "$BLOCK_TO" ] || fail "up.sh has no wardryx block between its headings, so this measured nothing"
offs="$(sed -n "${BLOCK_FROM},${BLOCK_TO}p" "$LAUNCHER" | grep -vE '^[[:space:]]*#' | grep -E 'WANT_POLICY=0' || true)"
if [ -n "$offs" ]; then
  printf 'up.sh: the wardryx block turns the policy plane off after the gateway is wired to it:\n' >&2
  printf '  %s\n' "$offs" >&2
  printf '  The gateway would keep pointing at a wardryx this run does not have. Stop instead.\n' >&2
  problems=$(( problems + 1 ))
fi

if [ "$problems" -gt 0 ]; then
  fail "$problems problem(s). See CLAUDE.md, invariant 20."
fi

printf 'wardryx: %d gateway start(s) wired to it fail closed, %d wait(s) stop the launcher when it does not come up, nothing says fail open, and the wardryx block never switches the plane off\n' \
  "$WIRED" "$WAITS"
