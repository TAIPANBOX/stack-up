#!/usr/bin/env bash
# The gateway's admin routes in this launcher answer only a key minted for the
# run, and the key never reaches the terminal. Invariant 21.
#
# WHY
#
# tokenfuse's admin routes (GET /v1/runs, POST /v1/runs/{id}/kill, GET /v1/keys,
# GET /v1/policy-plane and GET /v1/agent-ids) answer any local process while
# TOKENFUSE_ADMIN_KEYS is unset. The kill switch is one of them. This launcher
# set none, so any process on the machine could stop a run.
#
# The fix copies the declassify key's shape, which scripts/declassify-is-keyed.sh
# already holds: minted per run with rand_hex, handed to each gateway start as a
# prefix assignment ahead of env, refused when empty. The one difference is that
# the operator needs the value, so it goes to a file, not to the summary.
#
# WHAT IT HOLDS
#
# 1. Every gateway start ("$GATEWAY_BIN" at the command position, the mcp-broker
#    subcommand excluded) sets TOKENFUSE_ADMIN_KEYS from one shell variable, the
#    same variable on every start, and as a prefix assignment ahead of env.
# 2. That variable is minted with rand_hex above the first gateway start, with a
#    refusal on an empty value right after the mint.
# 3. The value is written to a file, and that file is made 0600 with chmod 600.
# 4. The value appears in no line outside a comment except its mint, its refusal,
#    the gateway starts' assignments and the write to that file. A log, warn,
#    echo or printf that names it would print it, and that is a fault.
#
# WHAT IT DOES NOT HOLD
#
# A running gateway refusing a call with no key, which needs a built gateway. And
# that the value is private in a process environment: the same user can read it
# (/proc/<pid>/environ on Linux, `ps eww` on macOS).
#
# AND IT REFUSES TO REPORT OK ON NOTHING
#
# No up.sh, no gateway start, or no variable the starts take the key from: it
# says it measured nothing and fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$ROOT/up.sh"

fail() { printf 'admin-keys-are-per-run: %s\n' "$*" >&2; exit 1; }

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

# 1. Every gateway start takes the key from the same variable, ahead of env.
GATEWAY_STARTS=""
GATEWAY_COUNT=0
FIRST_GATEWAY=""
# The $ is literal: these search for the TEXT "$GATEWAY_BIN" in up.sh.
# shellcheck disable=SC2013,SC2016
for n in $(grep -nE '^[[:space:]]*"\$GATEWAY_BIN"' "$LAUNCHER" \
            | grep -vE ':[[:space:]]*"\$GATEWAY_BIN"[[:space:]]+mcp-broker([[:space:]]|$)' \
            | cut -d: -f1); do
  GATEWAY_STARTS="$GATEWAY_STARTS $n"
  GATEWAY_COUNT=$(( GATEWAY_COUNT + 1 ))
  [ -n "$FIRST_GATEWAY" ] || FIRST_GATEWAY="$n"
done
[ "$GATEWAY_COUNT" -gt 0 ] || fail "up.sh launches \$GATEWAY_BIN nowhere, so this measured nothing"

KEY_VAR=""
for line in $GATEWAY_STARTS; do
  start="$(block_start "$line")"
  block="$(sed -n "${start},${line}p" "$LAUNCHER" | grep -vE '^[[:space:]]*#')"
  spec="$(grep -oE 'TOKENFUSE_ADMIN_KEYS="[^"]*"' <<<"$block" | head -1)"
  if [ -z "$spec" ]; then
    printf 'up.sh:%s: this gateway start does not set TOKENFUSE_ADMIN_KEYS, so its admin routes answer any local process.\n' "$line" >&2
    problems=$(( problems + 1 ))
    continue
  fi
  if ! [[ "$spec" =~ ^TOKENFUSE_ADMIN_KEYS=\"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?\"$ ]]; then
    printf 'up.sh:%s: this gateway start takes TOKENFUSE_ADMIN_KEYS from something other than a run variable (%s).\n' "$line" "$spec" >&2
    printf '  A literal is a key in a public repository, and an empty value leaves the routes open.\n' >&2
    problems=$(( problems + 1 ))
    continue
  fi
  var="${BASH_REMATCH[1]}"
  if [ -n "$KEY_VAR" ] && [ "$var" != "$KEY_VAR" ]; then
    printf 'up.sh:%s: two gateway starts take their admin keys from different variables ($%s and $%s).\n' "$line" "$KEY_VAR" "$var" >&2
    problems=$(( problems + 1 ))
  fi
  KEY_VAR="$var"
  assign_ln="$(grep -nE 'TOKENFUSE_ADMIN_KEYS=' <<<"$block" | head -1 | cut -d: -f1)"
  env_ln="$(grep -nE '^[[:space:]]*env([[:space:]]|$)' <<<"$block" | head -1 | cut -d: -f1)"
  if [ -n "$env_ln" ] && [ "$assign_ln" -ge "$env_ln" ]; then
    printf 'up.sh:%s: TOKENFUSE_ADMIN_KEYS is an argument to env, not a prefix assignment.\n' "$line" >&2
    printf '  env would hold the admin key on its own command line before it execs the gateway,\n' >&2
    printf '  where ps can read it. Put it before env, so it is in the environment only.\n' >&2
    problems=$(( problems + 1 ))
  fi
done

if [ -z "$KEY_VAR" ]; then
  fail "$problems problem(s): no gateway start takes its admin keys from a run variable. See CLAUDE.md, invariant 21."
fi

# 2. The mint, above the first gateway start, with a refusal after it.
mint_ln="$(grep -nE "^${KEY_VAR}=\".*\\\$\\(rand_hex [0-9]+\\).*\"" "$LAUNCHER" | head -1 | cut -d: -f1)"
if [ -z "$mint_ln" ]; then
  printf 'up.sh: %s is never minted with rand_hex, so the admin key is not per run.\n' "$KEY_VAR" >&2
  problems=$(( problems + 1 ))
else
  if [ "$mint_ln" -ge "$FIRST_GATEWAY" ]; then
    printf 'up.sh:%s: %s is minted after the first gateway start (line %s).\n' "$mint_ln" "$KEY_VAR" "$FIRST_GATEWAY" >&2
    problems=$(( problems + 1 ))
  fi
  after="$(sed -n "$(( mint_ln + 1 )),$(( mint_ln + 2 ))p" "$LAUNCHER")"
  if ! grep -qE "\\[ -n \"\\\$${KEY_VAR}\" \\]" <<<"$after"; then
    printf 'up.sh:%s: no refusal on an empty %s right after the mint. An empty key leaves the admin\n' "$mint_ln" "$KEY_VAR" >&2
    printf '  routes open to any local process while the launcher reports a healthy stand.\n' >&2
    problems=$(( problems + 1 ))
  fi
fi

# 3. The value goes to a file, and the file is made 0600.
# The $ in these patterns is regex text, not an expansion.
# shellcheck disable=SC2016
write_re='printf .*"\$'"${KEY_VAR}"'" *> *"\$([A-Za-z_][A-Za-z0-9_]*)"'
FILE_VAR=""
write_ln=""
while IFS= read -r wl; do
  text="${wl#*:}"
  if [[ "$text" =~ $write_re ]]; then
    FILE_VAR="${BASH_REMATCH[1]}"
    write_ln="${wl%%:*}"
    break
  fi
done < <(grep -nE 'printf' "$LAUNCHER" | grep -vE '^[0-9]+:[[:space:]]*#' || true)

if [ -z "$FILE_VAR" ]; then
  printf 'up.sh: %s is never written to a file, so the operator has no way to read it except from the process.\n' "$KEY_VAR" >&2
  problems=$(( problems + 1 ))
else
  chmod_re='chmod 600 "\$'"${FILE_VAR}"'"'
  if ! grep -qE "$chmod_re" <<<"$(sed -n "${write_ln},$(( FIRST_GATEWAY ))p" "$LAUNCHER")"; then
    printf 'up.sh:%s: %s is written, but the file is not made 0600 (chmod 600 "$%s") after the write.\n' "$write_ln" "$KEY_VAR" "$FILE_VAR" >&2
    problems=$(( problems + 1 ))
  fi
fi

# 4. No other line names the value. A comment is prose, not a print.
refs="$(grep -nE "\\\$\\{?${KEY_VAR}\\}?([^A-Za-z0-9_]|\$)" "$LAUNCHER" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
if [ -n "$refs" ]; then
  while IFS= read -r rl; do
    ln="${rl%%:*}"
    text="${rl#*:}"
    if [[ "$text" =~ ^[[:space:]]*${KEY_VAR}= ]]; then continue; fi
    if grep -qE "\\[ -n \"\\\$${KEY_VAR}\" \\]" <<<"$text"; then continue; fi
    if grep -qE "TOKENFUSE_ADMIN_KEYS=\"\\\$\\{?${KEY_VAR}\\}?\"" <<<"$text"; then continue; fi
    if [ -n "$FILE_VAR" ] && [[ "$text" =~ $write_re ]]; then continue; fi
    printf 'up.sh:%s: references the admin key outside the gateway'"'"'s environment and its 0600 file (a print or a pass).\n' "$ln" >&2
    problems=$(( problems + 1 ))
  done <<<"$refs"
fi

if [ "$problems" -gt 0 ]; then
  fail "$problems problem(s). See CLAUDE.md, invariant 21."
fi

printf 'the gateway admin routes need a per-run key ($%s): %d gateway start(s) take it from the environment ahead of env, it is minted with rand_hex, written to $%s and made 0600, and no other line names it\n' \
  "$KEY_VAR" "$GATEWAY_COUNT" "$FILE_VAR"
