#!/usr/bin/env bash
# Every gateway start in this launcher runs tokenfuse's PII masks from one switch,
# and the switch defaults to shadow.
#
# WHY
#
# tokenfuse reads TOKENFUSE_DLP_PII on the gateway and TOKENFUSE_MCP_DLP_PII on the
# MCP broker. Unset, both are off, so a launcher that sets nothing records no
# personal data in prompts or tool arguments. @decided 2026-10-13: the launcher runs
# them in shadow by default, which writes what it finds to the event stream and
# refuses nothing, and an operator keeps one switch, --pii off|shadow|mask|block, to
# change that.
#
# tokenfuse's loaders keep off for any value they do not name, and say nothing
# (crates/gateway/src/defaults.rs, dlp_pii_mode_from; the broker's own match in
# crates/gateway/src/main.rs). A misspelt switch would therefore run with the scanner
# off while the operator believes it records. So the launcher refuses every other
# word at argument parsing, before anything is built.
#
# WHAT IT HOLDS
#
# 1. Every gateway start carries exactly one TOKENFUSE_DLP_PII assignment, and its
#    value is the variable the switch fills. Not absent, not a literal, and not a
#    second assignment that could override the first.
# 2. The switch's default is shadow, written as a literal. A default read from the
#    caller's environment is not the switch.
# 3. The MCP broker start carries exactly one TOKENFUSE_MCP_DLP_PII assignment, from
#    the same variable.
# 4. --pii takes off, shadow, mask or block, and any other word exits 2 at argument
#    parsing. The plan names the mode. A refusal and a plan leave the state directory
#    alone.
#
# WHAT IT LOOKS AT
#
# The same subjects firewall-is-enforce.sh finds: every line that launches
# "$GATEWAY_BIN" at the command position, with the backslash-continued prefix above
# it. The broker launch is judged by item 3, not counted as a gateway start.
#
# AND IT REFUSES TO REPORT OK ON NOTHING
#
# No up.sh, no GATEWAY_BIN assignment, no gateway start, or no --plan: this says it
# measured nothing and fails.
#
# WHAT IT DOES NOT DO
#
# It does not start a gateway or a broker. That a running gateway records a
# personal-data hit in shadow and refuses one in block is tokenfuse's own test, and
# it needs a built gateway.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
LAUNCHER="$ROOT/up.sh"

fail() { printf 'pii-is-shadow: %s\n' "$*" >&2; exit 1; }

[[ -f "$LAUNCHER" ]] || fail "no up.sh at $LAUNCHER, so this measured nothing"

BIN_VAR="$(grep -oE '^GATEWAY_BIN="[^"]*"' "$LAUNCHER" | head -1)"
[[ -n "$BIN_VAR" ]] || fail "no GATEWAY_BIN assignment in up.sh, so this measured nothing"

# Plain loop, not mapfile: bash 3.2 is macOS's own /bin/bash.
LAUNCH_LINES=""
LAUNCH_COUNT=0
while IFS= read -r n; do
  # The here-document always delivers one line, empty when grep found nothing.
  [ -n "$n" ] || continue
  LAUNCH_LINES="$LAUNCH_LINES $n"
  LAUNCH_COUNT=$(( LAUNCH_COUNT + 1 ))
done <<EOF
$(
  # shellcheck disable=SC2016
  # The $ is literal on purpose: this searches for the TEXT "$GATEWAY_BIN" in
  # another script.
  grep -nE '^[[:space:]]*"\$GATEWAY_BIN"' "$LAUNCHER" \
    | grep -vE ':[[:space:]]*"\$GATEWAY_BIN"[[:space:]]+mcp-broker([[:space:]]|$)' \
    | cut -d: -f1
)
EOF
[ "$LAUNCH_COUNT" -gt 0 ] || fail "up.sh launches \$GATEWAY_BIN nowhere, so this measured nothing"

# shellcheck disable=SC2016
BROKER_LINES="$(grep -nE '^[[:space:]]*"\$GATEWAY_BIN"[[:space:]]+mcp-broker([[:space:]]|$)' "$LAUNCHER" \
  | cut -d: -f1 | tr '\n' ' ')"

# The launch at line $1 with the backslash-continued prefix above it, whole-line
# comments removed: the text the launch's own environment is made of.
launch_block() {
  local line="$1" start=$1 prev prev_text
  while [ "$start" -gt 1 ]; do
    prev=$(( start - 1 ))
    prev_text="$(sed -n "${prev}p" "$LAUNCHER")"
    [[ "$prev_text" =~ \\$ ]] || break
    start="$prev"
  done
  sed -n "${start},${line}p" "$LAUNCHER" | grep -vE '^[[:space:]]*#'
}

problems=0

# 1. every gateway start carries exactly one PII assignment, and it is the switch.
for line in $LAUNCH_LINES; do
  block="$(launch_block "$line")"
  count="$(grep -cE '(^|[[:space:]])TOKENFUSE_DLP_PII=' <<<"$block")"
  if [ "$count" -eq 0 ]; then
    printf 'up.sh:%s: this gateway start does not set TOKENFUSE_DLP_PII.\n' "$line" >&2
    printf '  Unset, tokenfuse runs its PII masks off, and personal data in prompts is not recorded.\n' >&2
    problems=$(( problems + 1 ))
    continue
  fi
  # shellcheck disable=SC2016
  if [ "$count" -ne 1 ] || ! grep -qE '(^|[[:space:]])TOKENFUSE_DLP_PII="\$PII_MODE"([[:space:]\\]|$)' <<<"$block"; then
    printf 'up.sh:%s: TOKENFUSE_DLP_PII is not set from "$PII_MODE" alone.\n' "$line" >&2
    printf '  A literal, a second assignment or another variable cannot be overridden by --pii.\n' >&2
    problems=$(( problems + 1 ))
  fi
done

# 2. the switch's default is shadow, written as a literal.
default_line="$(grep -E '^PII_MODE=' "$LAUNCHER" | head -1)"
if [ "$default_line" != 'PII_MODE="shadow"' ]; then
  printf 'up.sh: the PII default is not PII_MODE="shadow" (%s).\n' "${default_line:-no PII_MODE assignment}" >&2
  printf '  Off or block changes what a stand records when nobody asked for a change, and a value\n' >&2
  printf "  read from the caller's environment is not the switch.\n" >&2
  problems=$(( problems + 1 ))
fi

# 3. the MCP broker start, where the launcher has one, carries the same switch.
for bline in $BROKER_LINES; do
  block="$(launch_block "$bline")"
  count="$(grep -cE '(^|[[:space:]])TOKENFUSE_MCP_DLP_PII=' <<<"$block")"
  # shellcheck disable=SC2016
  if [ "$count" -eq 0 ]; then
    printf 'up.sh:%s: the MCP broker start does not set TOKENFUSE_MCP_DLP_PII.\n' "$bline" >&2
    printf '  Unset, the broker runs its PII masks off, and the calls it forwards are not scanned.\n' >&2
    problems=$(( problems + 1 ))
  elif [ "$count" -ne 1 ] || ! grep -qE '(^|[[:space:]])TOKENFUSE_MCP_DLP_PII="\$PII_MODE"([[:space:]\\]|$)' <<<"$block"; then
    printf 'up.sh:%s: TOKENFUSE_MCP_DLP_PII is not set from "$PII_MODE" alone.\n' "$bline" >&2
    problems=$(( problems + 1 ))
  fi
done

# 4. the switch is judged before anything runs. --plan stops once the arguments
# are resolved, so this drives the same code path the real launch uses.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export STACK_UP_HOME="$work/home"
out=""; rc=0
run() { out="$(./up.sh "$@" 2>&1)"; rc=$?; }

run --plan
case "$out" in
  *"unknown option"*) fail "up.sh has no --plan, so the PII switch is not measurable and this measured nothing" ;;
esac
if [ "$rc" -ne 0 ]; then
  printf 'up.sh --plan: exit %s, wanted 0\n' "$rc" >&2; problems=$(( problems + 1 ))
fi
if ! grep -qF 'launch: PII masks: shadow' <<<"$out"; then
  printf 'up.sh --plan: the default plan does not name the PII masks as shadow.\n' >&2
  printf '%s\n' "$out" | head -4 | sed 's/^/      /' >&2
  problems=$(( problems + 1 ))
fi

accepted=0; refused=0
accept() {
  accepted=$(( accepted + 1 ))
  run --pii "$1" --plan
  if [ "$rc" -ne 0 ] || ! grep -qF "launch: PII masks: $1" <<<"$out"; then
    printf -- '--pii %s: exit %s, wanted 0 and the plan naming it\n' "$1" "$rc" >&2
    problems=$(( problems + 1 ))
  fi
}
refuse() {
  refused=$(( refused + 1 ))
  run --pii "$1" --plan
  if [ "$rc" -ne 2 ] || ! grep -qF -- '--pii takes off, shadow, mask or block' <<<"$out"; then
    printf -- '--pii %q: exit %s, wanted 2 naming the flag\n' "$1" "$rc" >&2
    printf '%s\n' "$out" | head -3 | sed 's/^/      /' >&2
    problems=$(( problems + 1 ))
  fi
}
for v in off shadow mask block; do accept "$v"; done
for v in "" Shadow SHADOW on Off "off " " block" none pass true 0 allow; do refuse "$v"; done
run --pii=mask --plan
if [ "$rc" -ne 0 ] || ! grep -qF 'launch: PII masks: mask' <<<"$out"; then
  printf -- '--pii=mask: exit %s, wanted 0 and the plan naming it\n' "$rc" >&2
  problems=$(( problems + 1 ))
fi
# A refusal and a plan leave the state directory alone.
if [ -e "$STACK_UP_HOME" ]; then
  printf 'a refusal or a plan created %s\n' "$STACK_UP_HOME" >&2
  problems=$(( problems + 1 ))
fi

if [ "$problems" -gt 0 ]; then
  fail "$problems problem(s). See CLAUDE.md, invariant 19."
fi

printf 'every gateway start in up.sh sets TOKENFUSE_DLP_PII from the switch, default shadow, and the MCP broker start sets TOKENFUSE_MCP_DLP_PII the same way (%d gateway start(s) checked; %d --pii words accepted and %d refused)\n' "$LAUNCH_COUNT" "$accepted" "$refused"
