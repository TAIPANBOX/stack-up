#!/usr/bin/env bash
# Every gateway start in this launcher gets TOKENFUSE_DECLASSIFY_KEY from a key
# minted fresh for the run, through the process environment and never as an
# argument.
#
# WHY
#
# `POST /v1/fuse/declassify` is the gateway's release valve for its agent
# firewall: a person reviews a run and its taint label comes off. It is not
# behind the admin key. Its own credential, TOKENFUSE_DECLASSIFY_KEY (presented
# as `x-fuse-declassify-key`), is OPTIONAL in the gateway, and with it unset
# anything that can reach the gateway port can clear a run, recorded only as
# `authenticated: false` (tokenfuse crates/gateway/src/declassify.rs). Nothing
# in this estate calls the endpoint, so a key only the operator was shown closes
# it by default and breaks nothing.
#
# WHAT IT HOLDS, THREE THINGS
#
# 1. Every gateway start sets TOKENFUSE_DECLASSIFY_KEY from a shell variable.
#    Not a literal (a key in a public repository is no key), and not absent.
# 2. It is set as a PREFIX assignment ahead of `env`, never as an argument to
#    `env`. The gateway is started as `env VAR=... "$GATEWAY_BIN"`, and an
#    argument to `env` is on `env`'s own command line for the moment before it
#    execs, which `ps` can read. A prefix assignment lands in the environment
#    of the process only, the way SCOPYX_KEYS and VOUCHRYX_REVOKE_KEYS already
#    reach theirs.
# 3. The variable is minted with rand_hex BEFORE the first gateway start and a
#    refusal follows it. The gateway reads an EMPTY value as unset, so a mint
#    that quietly produced nothing would start the gateway with the endpoint
#    open and say nothing.
#
# WHAT IT LOOKS AT
#
# The same subjects gateway-cache-is-off.sh finds: every line that launches
# "$GATEWAY_BIN" at the command position, and the backslash-continued prefix
# above it. `"$GATEWAY_BIN" mcp-broker` is the same binary on a subcommand and
# never serves this route, so it is not a subject (anchored to the subcommand
# position, as the neighbouring gates anchor it).
#
# AND IT REFUSES TO REPORT OK ON NOTHING
#
# No up.sh, no GATEWAY_BIND assignment, or no gateway start found, and this
# says it measured nothing and fails. Silence here is not health.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$ROOT/up.sh"

fail() { printf 'declassify-is-keyed: %s\n' "$*" >&2; exit 1; }

[[ -f "$LAUNCHER" ]] || fail "no up.sh at $LAUNCHER, so this measured nothing"

BIN_VAR="$(grep -oE '^GATEWAY_BIN="[^"]*"' "$LAUNCHER" | head -1)"
[[ -n "$BIN_VAR" ]] || fail "no GATEWAY_BIN assignment in up.sh, so this measured nothing"

# Plain loop, not `mapfile`: bash 3.2 is macOS's own /bin/bash.
LAUNCH_LINES=""
LAUNCH_COUNT=0
while IFS= read -r n; do
  # The here-document always delivers one line, empty when grep found nothing,
  # so without this skip a launcher with NO gateway start counts as one start
  # and the "measured nothing" refusal below can never fire. The neighbouring
  # gates read their subjects the same way and do not skip it.
  [ -n "$n" ] || continue
  LAUNCH_LINES="$LAUNCH_LINES $n"
  LAUNCH_COUNT=$(( LAUNCH_COUNT + 1 ))
done <<EOF
$(
  # shellcheck disable=SC2016
  # The $ is literal: this searches for the TEXT "$GATEWAY_BIN" in another
  # script, and expanding it here would match nothing and pass silently.
  grep -nE '^[[:space:]]*"\$GATEWAY_BIN"' "$LAUNCHER" \
    | grep -vE ':[[:space:]]*"\$GATEWAY_BIN"[[:space:]]+mcp-broker([[:space:]]|$)' \
    | cut -d: -f1
)
EOF
[ "$LAUNCH_COUNT" -gt 0 ] || fail "up.sh launches \$GATEWAY_BIN nowhere, so this measured nothing"

problems=0
VARS_SEEN=""
FIRST_LAUNCH=""
for line in $LAUNCH_LINES; do
  [ -n "$FIRST_LAUNCH" ] || FIRST_LAUNCH="$line"
  [ "$line" -lt "$FIRST_LAUNCH" ] && FIRST_LAUNCH="$line"

  # Walk back over the backslash-continued prefix that belongs to this launch.
  start="$line"
  while [ "$start" -gt 1 ]; do
    prev=$(( start - 1 ))
    prev_text="$(sed -n "${prev}p" "$LAUNCHER")"
    [[ "$prev_text" =~ \\$ ]] || break
    start="$prev"
  done

  # Comments are not part of the command: strip whole-line comments so prose
  # about the variable cannot satisfy, or trip, the checks below.
  block="$(sed -n "${start},${line}p" "$LAUNCHER" | grep -vE '^[[:space:]]*#')"

  assign="$(grep -nE 'TOKENFUSE_DECLASSIFY_KEY=' <<<"$block" | head -1)"
  if [ -z "$assign" ]; then
    printf 'up.sh:%s: this gateway start does not set TOKENFUSE_DECLASSIFY_KEY.\n' "$line" >&2
    printf '  Unset, POST /v1/fuse/declassify is open to anything that reaches the gateway\n' >&2
    printf '  port: it clears a run and records only authenticated: false.\n' >&2
    problems=$(( problems + 1 ))
    continue
  fi

  # The value must be a plain reference to a variable, never a literal.
  if ! grep -qE 'TOKENFUSE_DECLASSIFY_KEY="\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"' <<<"$block"; then
    printf 'up.sh:%s: TOKENFUSE_DECLASSIFY_KEY is not set from a variable.\n' "$line" >&2
    printf '  A literal here is a key committed to a public repository.\n' >&2
    problems=$(( problems + 1 ))
    continue
  fi
  var="$(grep -oE 'TOKENFUSE_DECLASSIFY_KEY="\$\{?[A-Za-z_][A-Za-z0-9_]*' <<<"$block" | head -1 | sed -E 's/.*\$\{?//')"
  VARS_SEEN="$VARS_SEEN $var"

  # A prefix assignment, ahead of `env`. When the start goes through `env`, an
  # assignment on or after that line is an argument to env, on its command line.
  assign_ln="${assign%%:*}"
  env_ln="$(grep -nE '^[[:space:]]*env([[:space:]]|$)' <<<"$block" | head -1 | cut -d: -f1)"
  if [ -n "$env_ln" ] && [ "$assign_ln" -ge "$env_ln" ]; then
    printf 'up.sh:%s: TOKENFUSE_DECLASSIFY_KEY is an argument to env, not a prefix assignment.\n' "$line" >&2
    printf '  env would hold the key on its own command line before it execs the gateway,\n' >&2
    printf '  where ps can read it. Put it before `env`, so it is in the environment only.\n' >&2
    problems=$(( problems + 1 ))
  fi
done

# The mint: each variable is assigned from rand_hex, above the first gateway
# start, with a refusal on empty right after it.
for var in $(printf '%s\n' $VARS_SEEN | sort -u); do
  mint_ln="$(grep -nE "^${var}=\"\\\$\\(rand_hex [0-9]+\\)\"" "$LAUNCHER" | head -1 | cut -d: -f1)"
  if [ -z "$mint_ln" ]; then
    printf 'up.sh: %s is never minted with rand_hex, so the gateway key is not per run.\n' "$var" >&2
    problems=$(( problems + 1 ))
    continue
  fi
  if [ "$mint_ln" -ge "$FIRST_LAUNCH" ]; then
    printf 'up.sh:%s: %s is minted after the first gateway start (line %s).\n' "$mint_ln" "$var" "$FIRST_LAUNCH" >&2
    problems=$(( problems + 1 ))
  fi
  after="$(sed -n "$(( mint_ln + 1 )),$(( mint_ln + 2 ))p" "$LAUNCHER")"
  if ! grep -qE "\\[ -n \"\\\$${var}\" \\]" <<<"$after"; then
    printf 'up.sh:%s: no refusal on an empty %s right after the mint. The gateway reads an\n' "$mint_ln" "$var" >&2
    printf '  empty value as unset, so a failed mint would start it with the endpoint open.\n' >&2
    problems=$(( problems + 1 ))
  fi
done

if [ "$problems" -gt 0 ]; then
  fail "$problems problem(s). See CLAUDE.md, the declassify key invariant."
fi

printf 'every gateway start in up.sh sets TOKENFUSE_DECLASSIFY_KEY from a per-run key in its environment (%d checked)\n' "$LAUNCH_COUNT"
