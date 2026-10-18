#!/usr/bin/env bash
# The gateway and the MCP broker of this launcher hold the security postures they
# set, from values minted for this run. Invariant 22.
#
# WHY
#
# Until this invariant the launcher ran its gateway with no client key (any
# caller is admitted), with the built-in `devkey` literal as its key to wardryx
# (wardryx 2.0+ refuses that role on /v1/decide, and the literal is public in this
# repository), and the MCP broker with its secret and tool scans in shadow. The
# estate's posture check (estate-gates C25) reads these settings in every
# launcher and found all six of them missing here.
#
# The fix copies the shapes the other gates already hold: a value minted with
# rand_hex above the first start, refused when empty right after the mint, and
# handed to the process as a prefix assignment (the client spec and the wardryx
# key are secrets, so they never sit on env's command line).
#
# WHAT IT HOLDS
#
# 1. Every gateway start ("$GATEWAY_BIN" at the command position, the mcp-broker
#    subcommand excluded) sets TOKENFUSE_CLIENT_KEYS from one run variable, as a
#    prefix assignment ahead of env. That variable is minted with rand_hex above
#    the first start and refused when empty (a `|| die` right after the mint).
# 2. Every gateway start sets TOKENFUSE_IDENTITY_STRICT to the literal enforce.
# 3. Every gateway start that names a wardryx key takes it from a run variable
#    minted and refused the same way. The literal devkey is a fault.
# 4. The MCP broker start sets TOKENFUSE_MCP_DLP and TOKENFUSE_MCP_SCAN to the
#    literal block.
# 5. The broker's wardryx array sets TOKENFUSE_WARDRYX_FAILMODE to the literal
#    closed, and takes TOKENFUSE_WARDRYX_KEY from a run variable minted and refused.
# 6. No line outside a comment names the devkey literal, and WARDRYX_ALLOW_DEVKEY
#    is not assigned anywhere.
# 7. wardryx's WARDRYX_KEYS names the gateway's wardryx key as role pep, so the
#    key the gateway presents is the one wardryx answers to.
#
# WHAT IT DOES NOT HOLD
#
# That a running gateway or broker refuses a call without its key, that wardryx
# refuses the role it is given, or that the broker's DLP and scan block a secret
# or a poisoned tool. Those are tokenfuse's and wardryx's own tests and need a
# built binary. This gate proves the launcher hands the values over.
#
# AND IT REFUSES TO REPORT OK ON NOTHING
#
# No up.sh, no gateway start, no broker start or no wardryx array: it says it
# measured nothing and fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$ROOT/up.sh"

fail() { printf 'postures-are-held: %s\n' "$*" >&2; exit 1; }

[[ -f "$LAUNCHER" ]] || fail "no up.sh at $LAUNCHER, so this measured nothing"

problems=0

# live - "n:text" for every line that is not a comment.
live() { grep -nE '' "$LAUNCHER" | grep -vE '^[0-9]+:[[:space:]]*#'; }

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

# minted <var> - the line of the rand_hex mint of <var>, empty if there is none.
minted() {
  grep -nE "^$1=\".*\\\$\\(rand_hex [0-9]+\\).*\"" "$LAUNCHER" | head -1 | cut -d: -f1
}

# refused <var> <mint line> - a refusal on an empty <var> with a `|| die` right
# after the mint (within the next three lines).
refused() {
  local after
  after="$(sed -n "$(( $2 + 1 )),$(( $2 + 3 ))p" "$LAUNCHER")"
  grep -qE "\[ -n \"\\\$$1\" \]" <<<"$after" && grep -qE '\|\| *die' <<<"$after"
}

# 1-3. Every gateway start.
# The $ is literal: these search for the TEXT "$GATEWAY_BIN" in up.sh.
GATEWAY_STARTS=""
GATEWAY_COUNT=0
FIRST_GATEWAY=""
# shellcheck disable=SC2013,SC2016
for n in $(grep -nE '^[[:space:]]*"\$GATEWAY_BIN"' "$LAUNCHER" \
            | grep -vE ':[[:space:]]*"\$GATEWAY_BIN"[[:space:]]+mcp-broker([[:space:]]|$)' \
            | cut -d: -f1); do
  GATEWAY_STARTS="$GATEWAY_STARTS $n"
  GATEWAY_COUNT=$(( GATEWAY_COUNT + 1 ))
  [ -n "$FIRST_GATEWAY" ] || FIRST_GATEWAY="$n"
done
[ "$GATEWAY_COUNT" -gt 0 ] || fail "up.sh launches \$GATEWAY_BIN nowhere, so this measured nothing"

CLIENT_VAR=""
PEP_VAR=""
for line in $GATEWAY_STARTS; do
  start="$(block_start "$line")"
  block="$(sed -n "${start},${line}p" "$LAUNCHER" | grep -vE '^[[:space:]]*#')"

  # 1. The client keys: one run variable, ahead of env.
  spec="$(grep -oE 'TOKENFUSE_CLIENT_KEYS="[^"]*"' <<<"$block" | head -1)"
  if [ -z "$spec" ]; then
    printf 'up.sh:%s: this gateway start does not set TOKENFUSE_CLIENT_KEYS, so the metered door admits any caller.\n' "$line" >&2
    problems=$(( problems + 1 ))
  elif ! [[ "$spec" =~ ^TOKENFUSE_CLIENT_KEYS=\"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?\"$ ]]; then
    printf 'up.sh:%s: this gateway start takes TOKENFUSE_CLIENT_KEYS from something other than a run variable (%s).\n' "$line" "$spec" >&2
    printf '  A literal is a secret in a public repository, and an empty value admits every caller.\n' >&2
    problems=$(( problems + 1 ))
  else
    var="${BASH_REMATCH[1]}"
    if [ -n "$CLIENT_VAR" ] && [ "$var" != "$CLIENT_VAR" ]; then
      printf 'up.sh:%s: two gateway starts take their client keys from different variables ($%s and $%s).\n' "$line" "$CLIENT_VAR" "$var" >&2
      problems=$(( problems + 1 ))
    fi
    CLIENT_VAR="$var"
    assign_ln="$(grep -nE 'TOKENFUSE_CLIENT_KEYS=' <<<"$block" | head -1 | cut -d: -f1)"
    env_ln="$(grep -nE '^[[:space:]]*env([[:space:]]|$)' <<<"$block" | head -1 | cut -d: -f1)"
    if [ -n "$env_ln" ] && [ "$assign_ln" -ge "$env_ln" ]; then
      printf 'up.sh:%s: TOKENFUSE_CLIENT_KEYS is an argument to env, not a prefix assignment (the secret would be on env'"'"'s command line).\n' "$line" >&2
      problems=$(( problems + 1 ))
    fi
  fi

  # 2. Identity strict is enforce, named, not left to the binary's default.
  strict="$(grep -oE 'TOKENFUSE_IDENTITY_STRICT="[^"]*"' <<<"$block" | head -1)"
  if [ "$strict" != 'TOKENFUSE_IDENTITY_STRICT="enforce"' ]; then
    printf 'up.sh:%s: this gateway start does not set TOKENFUSE_IDENTITY_STRICT="enforce" (%s).\n' "$line" "${strict:-unset}" >&2
    problems=$(( problems + 1 ))
  fi

  # 3. The gateway's wardryx key, where the start has one: a run variable, never devkey.
  wkey="$(grep -oE 'TOKENFUSE_WARDRYX_KEY="[^"]*"' <<<"$block" | head -1)"
  if [ -n "$wkey" ]; then
    if ! [[ "$wkey" =~ ^TOKENFUSE_WARDRYX_KEY=\"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?\"$ ]]; then
      printf 'up.sh:%s: this gateway start hands wardryx a literal key (%s), not a run variable. The devkey literal is wardryx'"'"'s built-in admin credential.\n' "$line" "$wkey" >&2
      problems=$(( problems + 1 ))
    else
      PEP_VAR="${BASH_REMATCH[1]}"
    fi
  fi
done

if [ -z "$CLIENT_VAR" ]; then
  fail "$problems problem(s): no gateway start takes its client keys from a run variable. See CLAUDE.md, invariant 22."
fi

# The client keys are minted above the first start, with the refusal after it.
mint_ln="$(minted "$CLIENT_VAR")"
if [ -z "$mint_ln" ]; then
  printf 'up.sh: %s is never minted with rand_hex, so the client keys are not per run.\n' "$CLIENT_VAR" >&2
  problems=$(( problems + 1 ))
else
  if [ "$mint_ln" -ge "$FIRST_GATEWAY" ]; then
    printf 'up.sh:%s: %s is minted after the first gateway start (line %s).\n' "$mint_ln" "$CLIENT_VAR" "$FIRST_GATEWAY" >&2
    problems=$(( problems + 1 ))
  fi
  if ! refused "$CLIENT_VAR" "$mint_ln"; then
    printf 'up.sh:%s: no refusal (|| die) on an empty %s right after the mint. An empty value admits every caller.\n' "$mint_ln" "$CLIENT_VAR" >&2
    problems=$(( problems + 1 ))
  fi
fi

if [ -n "$PEP_VAR" ]; then
  pmint_ln="$(minted "$PEP_VAR")"
  if [ -z "$pmint_ln" ]; then
    printf 'up.sh: %s is never minted with rand_hex, so the wardryx key is not per run.\n' "$PEP_VAR" >&2
    problems=$(( problems + 1 ))
  elif ! refused "$PEP_VAR" "$pmint_ln"; then
    printf 'up.sh:%s: no refusal (|| die) on an empty %s right after the mint.\n' "$pmint_ln" "$PEP_VAR" >&2
    problems=$(( problems + 1 ))
  fi
else
  printf 'up.sh: no gateway start names a wardryx key from a run variable, so the gateway'"'"'s policy-plane key is not per run.\n' >&2
  problems=$(( problems + 1 ))
fi

# 4-5. The MCP broker start and its wardryx array.
# The $ is literal: this searches for the TEXT "$GATEWAY_BIN" in up.sh.
# shellcheck disable=SC2016
BROKER_LAUNCH="$(grep -nE '^[[:space:]]*"\$GATEWAY_BIN" mcp-broker([[:space:]]|$)' "$LAUNCHER" | head -1 | cut -d: -f1)"
[ -n "$BROKER_LAUNCH" ] || fail "up.sh launches the mcp-broker nowhere, so this measured nothing"
bstart="$(block_start "$BROKER_LAUNCH")"
bblock="$(sed -n "${bstart},${BROKER_LAUNCH}p" "$LAUNCHER" | grep -vE '^[[:space:]]*#')"

for name in TOKENFUSE_MCP_DLP TOKENFUSE_MCP_SCAN; do
  if ! grep -qE "^[[:space:]]*${name}=\"block\"" <<<"$bblock"; then
    printf 'up.sh:%s: the MCP broker start does not set %s="block" (the broker'"'"'s %s).\n' "$BROKER_LAUNCH" "$name" \
      "$( [ "$name" = TOKENFUSE_MCP_DLP ] && echo 'secrets in tool arguments are only shadowed' || echo 'tool scan warns instead of blocking' )" >&2
    problems=$(( problems + 1 ))
  fi
done

if ! grep -q 'BROKER_WARDRYX_ENV\[@\]' <<<"$bblock"; then
  fail "$problems problem(s): the MCP broker start does not read BROKER_WARDRYX_ENV, so its wardryx settings cannot be judged. See CLAUDE.md, invariant 22."
fi
arr_open="$(grep -nE '^[[:space:]]*BROKER_WARDRYX_ENV=\($' "$LAUNCHER" | head -1 | cut -d: -f1)"
[ -n "$arr_open" ] || fail "up.sh reads BROKER_WARDRYX_ENV but never defines it, so this measured nothing"
arr="$(sed -n "$(( arr_open + 1 )),\$p" "$LAUNCHER" | sed '/^[[:space:]]*)[[:space:]]*$/,$d' | grep -vE '^[[:space:]]*#')"

if ! grep -qE '"TOKENFUSE_WARDRYX_FAILMODE=closed"' <<<"$arr"; then
  printf 'up.sh:%s: the broker'"'"'s wardryx array does not set "TOKENFUSE_WARDRYX_FAILMODE=closed" (the broker would allow a call wardryx cannot answer).\n' "$arr_open" >&2
  problems=$(( problems + 1 ))
fi
bkey="$(grep -oE '"TOKENFUSE_WARDRYX_KEY=[^"]*"' <<<"$arr" | head -1)"
if ! [[ "$bkey" =~ ^\"TOKENFUSE_WARDRYX_KEY=\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?\"$ ]]; then
  printf 'up.sh:%s: the broker'"'"'s wardryx array does not hand TOKENFUSE_WARDRYX_KEY a run variable (%s).\n' "$arr_open" "${bkey:-unset}" >&2
  problems=$(( problems + 1 ))
else
  bvar="${BASH_REMATCH[1]}"
  bmint="$(minted "$bvar")"
  if [ -z "$bmint" ] || ! refused "$bvar" "$bmint"; then
    printf 'up.sh: the broker'"'"'s wardryx key %s is not minted with rand_hex and refused when empty.\n' "$bvar" >&2
    problems=$(( problems + 1 ))
  fi
fi

# 6. No devkey literal and no devkey switch outside a comment.
while IFS= read -r hit; do
  printf 'up.sh:%s: names the devkey literal outside a comment (%s).\n' "${hit%%:*}" "${hit#*:}" >&2
  problems=$(( problems + 1 ))
done < <(live | grep -E 'devkey' || true)
while IFS= read -r hit; do
  printf 'up.sh:%s: assigns WARDRYX_ALLOW_DEVKEY, which lets wardryx answer the devkey literal.\n' "${hit%%:*}" >&2
  problems=$(( problems + 1 ))
done < <(live | grep -E 'WARDRYX_ALLOW_DEVKEY=' || true)

# 7. wardryx's key list names the gateway's key as pep.
keys_line="$(live | grep -E 'WARDRYX_KEYS="' | head -1)"
if [ -z "$keys_line" ]; then
  printf 'up.sh: no WARDRYX_KEYS assignment, so wardryx has no key list at all.\n' >&2
  problems=$(( problems + 1 ))
elif [ -z "$PEP_VAR" ] || ! grep -qE "WARDRYX_KEYS=\"\\\$\\{?${PEP_VAR}\\}?:[^:\",]+:pep" <<<"$keys_line"; then
  printf 'up.sh: WARDRYX_KEYS does not name the gateway'"'"'s wardryx key as role pep (%s).\n' "$keys_line" >&2
  problems=$(( problems + 1 ))
fi

if [ "$problems" -gt 0 ]; then
  fail "$problems problem(s). See CLAUDE.md, invariant 22."
fi

printf 'the gateway and the MCP broker hold their postures from values minted for this run: %d gateway start(s) take $%s as client keys, identity strict is enforce, the wardryx key is $%s, the broker blocks DLP and scans (block), and wardryx answers only the pep key; no devkey literal outside a comment\n' \
  "$GATEWAY_COUNT" "$CLIENT_VAR" "$PEP_VAR"
