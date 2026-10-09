#!/usr/bin/env bash
# The tokenfuse cloud in this launcher holds one key minted for the run, and
# every caller of the cloud uses that same key. Nothing sets the removed
# devkey switch.
#
# WHY
#
# The cloud used to run with an empty TOKENFUSE_CLOUD_KEYS and
# TOKENFUSE_CLOUD_ALLOW_DEVKEY=1, which made the literal bearer `devkey` an
# admin key. tokenfuse removed that fallback (tokenfuse#380): a cloud started
# with the variable set logs an ERROR and exits 2, and an empty key set
# authenticates nobody. A literal key in a public repository is no key either,
# so up.sh mints one per run.
#
# Most ways of getting this wrong are LOUD (the cloud does not come up). One is
# not: a gateway handed a key the cloud does not hold starts fine, meters every
# call, and gets a 401 on every telemetry push, which only its own log shows.
# The dashboard then shows the demo seed and none of the gateway's real runs.
# That is why the gateway's key is checked against the cloud's, by variable name.
#
# WHAT IT HOLDS
#
# 1. No line of up.sh outside a comment sets TOKENFUSE_CLOUD_ALLOW_DEVKEY.
# 2. Every cloud start ("$CLOUD_BIN" at the command position) sets
#    TOKENFUSE_CLOUD_KEYS as "$VAR:<org>:<role>...", a shell variable, never a
#    literal and never empty.
# 3. That variable is minted with rand_hex above the first gateway start (the
#    gateway starts before the cloud and is handed the key at its start), with a
#    refusal on an empty value right after it.
# 4. Every gateway start ("$GATEWAY_BIN" at the command position, the
#    mcp-broker subcommand excluded as in the neighbouring gates) sets
#    TOKENFUSE_CLOUD_KEY from the SAME variable, as a prefix assignment ahead of
#    `env`: an argument to env is on env's command line, where ps can read it.
# 5. Every other use of the cloud's credential, read as one logical line (the
#    backslash continuations joined) that names CLOUD_PORT, presents
#    `Bearer $VAR` (or `Bearer %s` with $VAR among the printf arguments) and
#    `key=$VAR`, never a literal such as `devkey`.
#
# WHAT IT DOES NOT HOLD
#
# Wardryx's and scopyx's own dev-key modes (WARDRYX_ALLOW_DEVKEY, the
# `devkey` placeholder in TOKENFUSE_WARDRYX_KEY and SCOPYX_WARDRYX_KEY). Those
# are wardryx's credential, not the cloud's, and a separate decision. A running
# cloud accepting the key and refusing another, which needs a built cloud.
#
# AND IT REFUSES TO REPORT OK ON NOTHING
#
# No up.sh, no cloud start, no gateway start, or no cloud call to judge, and it
# says it measured nothing and fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$ROOT/up.sh"

fail() { printf 'cloud-key-is-per-run: %s\n' "$*" >&2; exit 1; }

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

# launch_lines <regex> - line numbers whose command position matches.
launch_lines() {
  grep -nE "$1" "$LAUNCHER" | cut -d: -f1
}

# 1. The removed switch.
devkey_set="$(grep -nE 'TOKENFUSE_CLOUD_ALLOW_DEVKEY=' "$LAUNCHER" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
if [ -n "$devkey_set" ]; then
  while IFS= read -r hit; do
    printf 'up.sh:%s: sets TOKENFUSE_CLOUD_ALLOW_DEVKEY. tokenfuse removed the devkey fallback\n' "${hit%%:*}" >&2
    printf '  (tokenfuse#380): a cloud that sees this variable refuses to start, exit 2.\n' >&2
    problems=$(( problems + 1 ))
  done <<<"$devkey_set"
fi

# 2. The cloud starts.
CLOUD_STARTS=""
CLOUD_COUNT=0
KEY_VAR=""
# shellcheck disable=SC2016
# The $ is literal: these search for the TEXT "$CLOUD_BIN" in another script.
for n in $(launch_lines '^[[:space:]]*"\$CLOUD_BIN"'); do
  CLOUD_STARTS="$CLOUD_STARTS $n"
  CLOUD_COUNT=$(( CLOUD_COUNT + 1 ))
done
[ "$CLOUD_COUNT" -gt 0 ] || fail "up.sh starts \$CLOUD_BIN nowhere, so this measured nothing"

for line in $CLOUD_STARTS; do
  start="$(block_start "$line")"
  block="$(sed -n "${start},${line}p" "$LAUNCHER" | grep -vE '^[[:space:]]*#')"
  spec="$(grep -oE 'TOKENFUSE_CLOUD_KEYS="[^"]*"' <<<"$block" | head -1)"
  if [ -z "$spec" ]; then
    printf 'up.sh:%s: this cloud start does not set TOKENFUSE_CLOUD_KEYS, so it authenticates nobody.\n' "$line" >&2
    problems=$(( problems + 1 ))
    continue
  fi
  if ! [[ "$spec" =~ ^TOKENFUSE_CLOUD_KEYS=\"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?:[^\"]+\"$ ]]; then
    printf 'up.sh:%s: this cloud start does not set TOKENFUSE_CLOUD_KEYS from the run'"'"'s key variable\n' "$line" >&2
    printf '  (%s). An empty set authenticates nobody, and a literal is a key in a public repository.\n' "${spec%%=*}" >&2
    problems=$(( problems + 1 ))
    continue
  fi
  var="${BASH_REMATCH[1]}"
  if [ -n "$KEY_VAR" ] && [ "$var" != "$KEY_VAR" ]; then
    printf 'up.sh:%s: two cloud starts hold different keys ($%s and $%s).\n' "$line" "$KEY_VAR" "$var" >&2
    problems=$(( problems + 1 ))
  fi
  KEY_VAR="$var"
done

# 4. The gateway starts, found as declassify-is-keyed.sh finds them.
GATEWAY_STARTS=""
GATEWAY_COUNT=0
FIRST_GATEWAY=""
# Line numbers are single words, so word splitting is what is wanted here, and
# a for loop over $(...) reads nothing when grep finds nothing, where a
# here-document would deliver one empty line (the trap the neighbouring gates
# fell into). The $ in the patterns is literal text, not an expansion.
# shellcheck disable=SC2013,SC2016
for n in $(grep -nE '^[[:space:]]*"\$GATEWAY_BIN"' "$LAUNCHER" \
            | grep -vE ':[[:space:]]*"\$GATEWAY_BIN"[[:space:]]+mcp-broker([[:space:]]|$)' \
            | cut -d: -f1); do
  GATEWAY_STARTS="$GATEWAY_STARTS $n"
  GATEWAY_COUNT=$(( GATEWAY_COUNT + 1 ))
  [ -n "$FIRST_GATEWAY" ] || FIRST_GATEWAY="$n"
done
[ "$GATEWAY_COUNT" -gt 0 ] || fail "up.sh launches \$GATEWAY_BIN nowhere, so this measured nothing"

if [ -n "$KEY_VAR" ]; then
  for line in $GATEWAY_STARTS; do
    start="$(block_start "$line")"
    block="$(sed -n "${start},${line}p" "$LAUNCHER" | grep -vE '^[[:space:]]*#')"
    assign="$(grep -nE 'TOKENFUSE_CLOUD_KEY=' <<<"$block" | head -1)"
    if [ -z "$assign" ]; then
      printf 'up.sh:%s: this gateway start does not set TOKENFUSE_CLOUD_KEY, so it reports to the cloud with no key.\n' "$line" >&2
      problems=$(( problems + 1 ))
      continue
    fi
    if ! grep -qE "TOKENFUSE_CLOUD_KEY=\"\\\$\\{?${KEY_VAR}\\}?\"" <<<"$block"; then
      printf 'up.sh:%s: TOKENFUSE_CLOUD_KEY is not $%s, the key the cloud is started with.\n' "$line" "$KEY_VAR" >&2
      printf '  The gateway would start, meter every call, and get a 401 on every push to the cloud.\n' >&2
      problems=$(( problems + 1 ))
      continue
    fi
    assign_ln="${assign%%:*}"
    env_ln="$(grep -nE '^[[:space:]]*env([[:space:]]|$)' <<<"$block" | head -1 | cut -d: -f1)"
    if [ -n "$env_ln" ] && [ "$assign_ln" -ge "$env_ln" ]; then
      printf 'up.sh:%s: TOKENFUSE_CLOUD_KEY is an argument to env, not a prefix assignment.\n' "$line" >&2
      printf '  env would hold the key on its own command line before it execs the gateway,\n' >&2
      printf '  where ps can read it. Put it before env, so it is in the environment only.\n' >&2
      problems=$(( problems + 1 ))
    fi
  done

  # 3. The mint, above the first gateway start, with a refusal after it.
  mint_ln="$(grep -nE "^${KEY_VAR}=\".*\\\$\\(rand_hex [0-9]+\\).*\"" "$LAUNCHER" | head -1 | cut -d: -f1)"
  if [ -z "$mint_ln" ]; then
    printf 'up.sh: %s is never minted with rand_hex, so the cloud key is not per run.\n' "$KEY_VAR" >&2
    problems=$(( problems + 1 ))
  else
    if [ "$mint_ln" -ge "$FIRST_GATEWAY" ]; then
      printf 'up.sh:%s: %s is minted after the first gateway start (line %s).\n' "$mint_ln" "$KEY_VAR" "$FIRST_GATEWAY" >&2
      problems=$(( problems + 1 ))
    fi
    after="$(sed -n "$(( mint_ln + 1 )),$(( mint_ln + 2 ))p" "$LAUNCHER")"
    if ! grep -qE "\\[ -n \"\\\$${KEY_VAR}\" \\]" <<<"$after"; then
      printf 'up.sh:%s: no refusal on an empty %s right after the mint. An empty key starts a\n' "$mint_ln" "$KEY_VAR" >&2
      printf '  cloud that answers every request 401 while the launcher reports it healthy.\n' >&2
      problems=$(( problems + 1 ))
    fi
  fi

  # 5. Every other use of the cloud's credential: logical lines naming CLOUD_PORT.
  CALLS=0
  logical="$(awk '
    /^[[:space:]]*#/ { next }
    {
      if (buf == "") first = NR
      line = $0
      if (line ~ /\\$/) { sub(/\\$/, "", line); buf = buf line " "; next }
      print first ":" buf line
      buf = ""
    }' "$LAUNCHER" | grep -E 'CLOUD_PORT' || true)"
  while IFS= read -r ll; do
    [ -n "$ll" ] || continue
    ln="${ll%%:*}"
    text="${ll#*:}"
    # The old literal in a credential position, in any wording: the summary once
    # printed "(bearer: devkey)", which the Bearer token below does not match.
    # Not the bare word: a gateway start names CLOUD_PORT and also carries
    # wardryx's own TOKENFUSE_WARDRYX_KEY="devkey", which is not the cloud's.
    if grep -qiE '(bearer[[:space:]:]+|[?&]key=)devkey' <<<"$text"; then
      printf 'up.sh:%s: a use of the cloud'"'"'s credential still presents devkey, the removed public key.\n' "$ln" >&2
      problems=$(( problems + 1 ))
    fi
    tokens="$(grep -oE 'Bearer [^" ]+|[?&]key=[^"&# ]+' <<<"$text" || true)"
    [ -n "$tokens" ] || continue
    while IFS= read -r tok; do
      CALLS=$(( CALLS + 1 ))
      val="${tok#Bearer }"
      val="${val#*key=}"
      case "$val" in
        "\$$KEY_VAR"|"\${$KEY_VAR}") continue ;;
        # Already reported above, once per line, in its own words.
        devkey) continue ;;
        %s)
          if grep -qE "\"\\\$\\{?${KEY_VAR}\\}?\"" <<<"$text"; then continue; fi ;;
      esac
      printf 'up.sh:%s: a use of the cloud'"'"'s credential presents %s, not this run'"'"'s key ($%s).\n' "$ln" "$tok" "$KEY_VAR" >&2
      problems=$(( problems + 1 ))
    done <<<"$tokens"
  done <<<"$logical"
  [ "$CALLS" -gt 0 ] || fail "no call to the cloud in up.sh presents a key (Bearer or key=), so the callers measured nothing"
fi

if [ "$problems" -gt 0 ]; then
  fail "$problems problem(s). See CLAUDE.md, invariant 17."
fi

printf 'the cloud holds one per-run key ($%s), %d gateway start(s) and %d other cloud call(s) use it, nothing sets TOKENFUSE_CLOUD_ALLOW_DEVKEY (%d cloud start(s) checked)\n' \
  "$KEY_VAR" "$GATEWAY_COUNT" "$CALLS" "$CLOUD_COUNT"
