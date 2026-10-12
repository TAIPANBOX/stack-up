#!/usr/bin/env bash
# Every gateway start in this launcher runs tokenfuse's agent firewall from one
# switch, and the switch defaults to enforce.
#
# WHY
#
# tokenfuse's agent firewall reads TOKENFUSE_FIREWALL. Unset, it runs in shadow:
# it writes what it would refuse and refuses nothing. The decision (2026-10-13)
# is that the launcher runs it in enforce by default, shipped as its own change
# after a test stack, and that an operator keeps one switch, --firewall
# enforce|shadow|off, to run it in shadow or off.
#
# tokenfuse's from_env() reads TOKENFUSE_FIREWALL for enforce, shadow and off,
# and keeps the default for any other value without a word (crates/gateway/src/
# firewall.rs, tokenfuse main b3373bf). A misspelt switch would therefore run the
# box in shadow while the operator believes it enforces. So the launcher refuses
# every other word at argument parsing, before anything is built.
#
# WHAT IT HOLDS
#
# 1. Every gateway start carries exactly one TOKENFUSE_FIREWALL assignment, and
#    its value is the variable the switch fills. Not absent, not a literal, and
#    not a second assignment that could override the first.
# 2. The switch's default is enforce. @claude 2026-10-13: a default of shadow or
#    off changes what a stand does when nobody asked for a change, so it is a
#    decision, and a default read from the caller's environment is not the switch.
# 3. The MCP broker start does not carry the setting. The broker is the same binary
#    on a subcommand: it is not the gateway and reads no firewall.
# 4. --firewall takes enforce, shadow or off, and any other word exits 2 at
#    argument parsing. The plan names the mode, and a plan with no flag names
#    enforce. A refusal and a plan leave the state directory alone.
#
# WHAT IT LOOKS AT
#
# The same subjects gateway-cache-is-off.sh finds: every line that launches
# "$GATEWAY_BIN" at the command position, and the backslash-continued prefix above
# it. The broker's launch is judged by item 3, not counted as a gateway start.
#
# AND IT REFUSES TO REPORT OK ON NOTHING
#
# No up.sh, no GATEWAY_BIN assignment, no gateway start, or a launcher with no
# --plan: this says it measured nothing and fails.
#
# WHAT IT DOES NOT DO
#
# It does not start a gateway. That a running gateway refuses a dangerous
# capability on a run that read untrusted input is tokenfuse's own test (its
# invariants 25 to 27 and 93), and it needs a built gateway.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
LAUNCHER="$ROOT/up.sh"

fail() { printf 'firewall-is-enforce: %s\n' "$*" >&2; exit 1; }

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

# 1. every gateway start carries exactly one assignment, and it is the variable.
for line in $LAUNCH_LINES; do
  block="$(launch_block "$line")"
  count="$(grep -cE '(^|[[:space:]])TOKENFUSE_FIREWALL=' <<<"$block")"
  if [ "$count" -eq 0 ]; then
    printf 'up.sh:%s: this gateway start does not set TOKENFUSE_FIREWALL.\n' "$line" >&2
    printf '  Unset, tokenfuse runs its agent firewall in shadow: it records what it would\n' >&2
    printf '  refuse and refuses nothing.\n' >&2
    problems=$(( problems + 1 ))
    continue
  fi
  # shellcheck disable=SC2016
  if [ "$count" -ne 1 ] || ! grep -qE '(^|[[:space:]])TOKENFUSE_FIREWALL="\$FIREWALL_MODE"([[:space:]\\]|$)' <<<"$block"; then
    printf 'up.sh:%s: TOKENFUSE_FIREWALL is not set from "$FIREWALL_MODE" alone.\n' "$line" >&2
    printf '  A literal, a second assignment or another variable cannot be overridden by --firewall.\n' >&2
    problems=$(( problems + 1 ))
  fi
done

# 2. the switch's default is enforce.
default_line="$(grep -E '^FIREWALL_MODE=' "$LAUNCHER" | head -1)"
if [ "$default_line" != 'FIREWALL_MODE="enforce"' ]; then
  printf 'up.sh: the firewall default is not FIREWALL_MODE="enforce" (%s).\n' "${default_line:-no FIREWALL_MODE assignment}" >&2
  printf '  A default of shadow or off, or one read from the caller'"'"'s environment, changes behaviour nobody asked for.\n' >&2
  problems=$(( problems + 1 ))
fi

# 3. the MCP broker is not the gateway and carries no switch.
for bline in $BROKER_LINES; do
  if grep -qE '(^|[[:space:]])TOKENFUSE_FIREWALL=' <<<"$(launch_block "$bline")"; then
    printf 'up.sh:%s: the MCP broker start sets TOKENFUSE_FIREWALL.\n' "$bline" >&2
    printf '  The broker is tokenfuse'"'"'s mcp-broker subcommand, not the gateway, and reads no firewall.\n' >&2
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
  *"unknown option"*) fail "up.sh has no --plan, so the firewall switch is not measurable and this measured nothing" ;;
esac
if [ "$rc" -ne 0 ]; then
  printf 'up.sh --plan: exit %s, wanted 0\n' "$rc" >&2; problems=$(( problems + 1 ))
fi
if ! grep -qF 'launch: agent firewall: enforce' <<<"$out"; then
  printf 'up.sh --plan: the default plan does not name the agent firewall as enforce.\n' >&2
  printf '%s\n' "$out" | head -4 | sed 's/^/      /' >&2
  problems=$(( problems + 1 ))
fi

accepted=0; refused=0
accept() {
  accepted=$(( accepted + 1 ))
  run --firewall "$1" --plan
  if [ "$rc" -ne 0 ] || ! grep -qF "launch: agent firewall: $1" <<<"$out"; then
    printf -- '--firewall %s: exit %s, wanted 0 and the plan naming it\n' "$1" "$rc" >&2
    problems=$(( problems + 1 ))
  fi
}
refuse() {
  refused=$(( refused + 1 ))
  run --firewall "$1" --plan
  if [ "$rc" -ne 2 ] || ! grep -qF -- '--firewall takes enforce, shadow or off' <<<"$out"; then
    printf -- '--firewall %q: exit %s, wanted 2 naming the flag\n' "$1" "$rc" >&2
    printf '%s\n' "$out" | head -3 | sed 's/^/      /' >&2
    problems=$(( problems + 1 ))
  fi
}
for v in enforce shadow off; do accept "$v"; done
for v in "" Enforce ENFORCE enfroce on true 0 "off " " shadow" none; do refuse "$v"; done
run --firewall=shadow --plan
if [ "$rc" -ne 0 ] || ! grep -qF 'launch: agent firewall: shadow' <<<"$out"; then
  printf -- '--firewall=shadow: exit %s, wanted 0 and the plan naming it\n' "$rc" >&2
  problems=$(( problems + 1 ))
fi
# A refusal and a plan leave the state directory alone.
if [ -e "$STACK_UP_HOME" ]; then
  printf 'a refusal or a plan created %s\n' "$STACK_UP_HOME" >&2
  problems=$(( problems + 1 ))
fi

if [ "$problems" -gt 0 ]; then
  fail "$problems problem(s). See CLAUDE.md, invariant 18."
fi

printf 'every gateway start in up.sh runs the agent firewall from the switch, default enforce (%d checked; %d --firewall words accepted and %d refused)\n' "$LAUNCH_COUNT" "$accepted" "$refused"
