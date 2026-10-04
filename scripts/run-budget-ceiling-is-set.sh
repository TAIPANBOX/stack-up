#!/usr/bin/env bash
# Every gateway start in this launcher sets TOKENFUSE_MAX_RUN_BUDGET_USD from the
# operator's run-budget ceiling, and the ceiling is a figure the gateway accepts.
#
# WHY
#
# A run's budget comes from the header the AGENT sends (x-fuse-budget-usd), from
# a policy default, or from tokenfuse's built-in USD 5, and the next call of an
# open run can widen it. With no ceiling, the per-run limit of a deployment with
# no client keys, no identity map and no unit caps is whatever the caller says.
# tokenfuse v1.5.0 (invariant 73) adds the operator's ceiling,
# TOKENFUSE_MAX_RUN_BUDGET_USD, and it is OFF unless set: tokenfuse's own release
# notes say "the launchers do not set it yet; until they do, a launcher
# deployment is no more bounded than before". A gateway start that does not set
# it still comes up, answers health checks and serves traffic, so nothing about a
# working stand says the bound is missing.
#
# WHAT IT HOLDS
#
# 1. Every gateway start sets TOKENFUSE_MAX_RUN_BUDGET_USD to "$RUN_BUDGET_CEILING_USD",
#    the variable --run-budget-ceiling fills. Not absent, not a literal (a literal
#    cannot be overridden, so the flag would change nothing), not another name.
# 2. That variable's default is 5.00. @claude 2026-10-04: 5.00 equals tokenfuse's
#    own DEFAULT_RUN_BUDGET, so an ordinary run is unchanged and only a
#    caller-declared larger budget is clamped. A different default changes what a
#    stranger's first run is allowed to do, and that is a decision, not a typo.
# 3. The flag is refused, exit 2 and before anything is built, for every figure
#    the gateway would itself refuse at start (measured against a v1.5.0 gateway
#    2026-10-04: 0, 0.00, .5, 5., +5, -1, 1e9, a word, a seventh decimal and a
#    value past 9223372036854.775807 all exit 2), and accepted for the ones it
#    starts on. A gateway that dies at "did not come up" after a multi-minute
#    build is the failure this moves to the first millisecond.
# 4. A gateway too old to read the variable is refused when the operator asked
#    for a figure and warned about otherwise. The function that decides is cut
#    out of up.sh and run on three files: one that names the setting, one that
#    does not, and one that is not there.
#
# WHAT IT LOOKS AT
#
# The same subjects gateway-cache-is-off.sh finds: every line that launches
# "$GATEWAY_BIN" at the command position and the backslash-continued prefix above
# it. `"$GATEWAY_BIN" mcp-broker` is the same binary on a subcommand and holds no
# run budget (it brokers credentials and never opens a run), so it is not a
# subject.
#
# AND IT REFUSES TO REPORT OK ON NOTHING
#
# No up.sh, no GATEWAY_BIN assignment, no gateway start, or a launcher that does
# not know --plan, and this says it measured nothing and fails.
#
# WHAT IT DOES NOT DO
#
# It does not start a gateway: that the running gateway clamps a caller's budget
# is tokenfuse's own test (invariant 73), and that a clamped call carries
# x-fuse-budget-clamped was shown against a built gateway by hand in the pull
# request that added this.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
LAUNCHER="$ROOT/up.sh"

fail() { printf 'run-budget-ceiling-is-set: %s\n' "$*" >&2; exit 1; }

[[ -f "$LAUNCHER" ]] || fail "no up.sh at $LAUNCHER, so this measured nothing"

BIN_VAR="$(grep -oE '^GATEWAY_BIN="[^"]*"' "$LAUNCHER" | head -1)"
[[ -n "$BIN_VAR" ]] || fail "no GATEWAY_BIN assignment in up.sh, so this measured nothing"

# Plain loop, not `mapfile`: bash 3.2 is macOS's own /bin/bash.
LAUNCH_LINES=""
LAUNCH_COUNT=0
while IFS= read -r n; do
  # The here-document always delivers one line, empty when grep found nothing;
  # without this skip a launcher with no gateway start counts as one start.
  [ -n "$n" ] || continue
  LAUNCH_LINES="$LAUNCH_LINES $n"
  LAUNCH_COUNT=$(( LAUNCH_COUNT + 1 ))
done <<EOF
$(
  # shellcheck disable=SC2016
  # The $ is literal: this searches for the TEXT "$GATEWAY_BIN" in another script.
  grep -nE '^[[:space:]]*"\$GATEWAY_BIN"' "$LAUNCHER" \
    | grep -vE ':[[:space:]]*"\$GATEWAY_BIN"[[:space:]]+mcp-broker([[:space:]]|$)' \
    | cut -d: -f1
)
EOF
[ "$LAUNCH_COUNT" -gt 0 ] || fail "up.sh launches \$GATEWAY_BIN nowhere, so this measured nothing"

problems=0

# 1. every start sets it, from the variable.
for line in $LAUNCH_LINES; do
  start="$line"
  while [ "$start" -gt 1 ]; do
    prev=$(( start - 1 ))
    prev_text="$(sed -n "${prev}p" "$LAUNCHER")"
    [[ "$prev_text" =~ \\$ ]] || break
    start="$prev"
  done
  # Whole-line comments are not part of the command.
  block="$(sed -n "${start},${line}p" "$LAUNCHER" | grep -vE '^[[:space:]]*#')"
  if ! grep -qE 'TOKENFUSE_MAX_RUN_BUDGET_USD=' <<<"$block"; then
    printf 'up.sh:%s: this gateway start does not set TOKENFUSE_MAX_RUN_BUDGET_USD.\n' "$line" >&2
    printf '  Unset, tokenfuse applies no ceiling and a caller chooses its own per-run budget.\n' >&2
    problems=$(( problems + 1 ))
    continue
  fi
  # shellcheck disable=SC2016
  if ! grep -qE 'TOKENFUSE_MAX_RUN_BUDGET_USD="\$RUN_BUDGET_CEILING_USD"' <<<"$block"; then
    printf 'up.sh:%s: TOKENFUSE_MAX_RUN_BUDGET_USD is not set from "$RUN_BUDGET_CEILING_USD".\n' "$line" >&2
    printf '  A literal or another variable cannot be overridden by --run-budget-ceiling.\n' >&2
    problems=$(( problems + 1 ))
  fi
done

# 2. the default is 5.00.
default_line="$(grep -E '^RUN_BUDGET_CEILING_USD=' "$LAUNCHER" | head -1)"
if [ -z "$default_line" ]; then
  printf 'up.sh: RUN_BUDGET_CEILING_USD is never assigned, so the ceiling has no default.\n' >&2
  problems=$(( problems + 1 ))
elif [ "$default_line" != 'RUN_BUDGET_CEILING_USD="5.00"' ]; then
  printf 'up.sh: the ceiling default is not 5.00 (%s). 5.00 equals tokenfuse'"'"'s own default run budget,\n' "$default_line" >&2
  printf '  so an ordinary run is unchanged; any other default is a decision.\n' >&2
  problems=$(( problems + 1 ))
fi

# 3. the flag is judged before anything runs. --plan stops after the arguments
# are resolved, so this drives the same code path the real launch uses.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export STACK_UP_HOME="$work/home"
out=""; rc=0
run() { out="$(./up.sh "$@" 2>&1)"; rc=$?; }

run --plan
case "$out" in
  *"unknown option"*) fail "up.sh has no --plan, so the ceiling is not measurable and this measured nothing" ;;
esac
if [ "$rc" -ne 0 ]; then
  printf 'up.sh --plan: exit %s, wanted 0\n' "$rc" >&2; problems=$(( problems + 1 ))
fi
if ! grep -qF 'launch: gateway run-budget ceiling: 5.00 USD per run' <<<"$out"; then
  printf 'up.sh --plan: the default plan does not say the ceiling is 5.00 USD per run.\n' >&2
  printf '%s\n' "$out" | head -4 | sed 's/^/      /' >&2
  problems=$(( problems + 1 ))
fi

accepted=0; refused=0
accept() {
  accepted=$(( accepted + 1 ))
  run --run-budget-ceiling "$1" --plan
  if [ "$rc" -ne 0 ] || ! grep -qF "ceiling: $1 USD per run" <<<"$out"; then
    printf -- '--run-budget-ceiling %s: exit %s, wanted 0 and the plan naming it\n' "$1" "$rc" >&2
    problems=$(( problems + 1 ))
  fi
}
refuse() {
  refused=$(( refused + 1 ))
  run --run-budget-ceiling "$1" --plan
  if [ "$rc" -ne 2 ] || ! grep -qF -- '--run-budget-ceiling takes a positive number' <<<"$out"; then
    printf -- '--run-budget-ceiling %q: exit %s, wanted 2 naming the flag\n' "$1" "$rc" >&2
    printf '%s\n' "$out" | head -3 | sed 's/^/      /' >&2
    problems=$(( problems + 1 ))
  fi
}
for v in 5 5.00 2.50 0.000001 005 999999999999.999999 1000000; do accept "$v"; done
for v in 0 0.00 0.000000 .5 5. +5 -1 1e9 abc "" "5 " 1.2345678 1000000000000 5.5.5 "5,00"; do refuse "$v"; done
# The equals form is the same flag.
run --run-budget-ceiling=2.50 --plan
if [ "$rc" -ne 0 ] || ! grep -qF 'ceiling: 2.50 USD per run' <<<"$out"; then
  printf -- '--run-budget-ceiling=2.50: exit %s, wanted 0 and the plan naming it\n' "$rc" >&2
  problems=$(( problems + 1 ))
fi
# A refusal and a plan leave the state directory alone.
if [ -e "$STACK_UP_HOME" ]; then
  printf 'a refusal or a plan created %s\n' "$STACK_UP_HOME" >&2
  problems=$(( problems + 1 ))
fi

# 4. the old-gateway decision, cut out of up.sh and run, not copied.
fn="$(awk '/^bin_reads_setting\(\) \{/ {p=1} p {print} p && /^\}/ {exit}' "$LAUNCHER")"
if [ -z "$fn" ]; then
  fail "up.sh has no bin_reads_setting function to run, so the old-gateway decision was not measured"
fi
printf 'with the setting named in it\nTOKENFUSE_MAX_RUN_BUDGET_USD\n' > "$work/new-gateway"
printf 'a gateway that predates the setting\n' > "$work/old-gateway"
# shellcheck disable=SC1090
( eval "$fn"
  bin_reads_setting "$work/new-gateway" TOKENFUSE_MAX_RUN_BUDGET_USD || exit 11
  bin_reads_setting "$work/old-gateway" TOKENFUSE_MAX_RUN_BUDGET_USD && exit 12
  bin_reads_setting "$work/missing" TOKENFUSE_MAX_RUN_BUDGET_USD && exit 13
  exit 0 )
case $? in
  0) ;;
  11) printf 'bin_reads_setting does not find a setting that is in the binary.\n' >&2; problems=$(( problems + 1 )) ;;
  12) printf 'bin_reads_setting finds a setting that is NOT in the binary: an old gateway would pass.\n' >&2; problems=$(( problems + 1 )) ;;
  13) printf 'bin_reads_setting says a binary that is not there reads the setting.\n' >&2; problems=$(( problems + 1 )) ;;
  *) printf 'bin_reads_setting could not be run.\n' >&2; problems=$(( problems + 1 )) ;;
esac
# The decision is used where it matters: asked is a refusal, default is a warning.
# shellcheck disable=SC2016
if ! grep -qE 'if ! bin_reads_setting "\$GATEWAY_BIN" TOKENFUSE_MAX_RUN_BUDGET_USD' "$LAUNCHER"; then
  printf 'up.sh never asks whether the gateway reads TOKENFUSE_MAX_RUN_BUDGET_USD.\n' >&2
  problems=$(( problems + 1 ))
fi
# shellcheck disable=SC2016
if ! grep -qE 'RUN_BUDGET_CEILING_ASKED" -eq 1 \]; then' "$LAUNCHER" \
   || ! grep -qE 'die "--run-budget-ceiling needs a gateway built from tokenfuse v1.5.0' "$LAUNCHER"; then
  printf 'up.sh does not refuse a gateway that ignores a ceiling the operator asked for.\n' >&2
  problems=$(( problems + 1 ))
fi

if [ "$problems" -gt 0 ]; then
  fail "$problems problem(s). See CLAUDE.md, the run-budget ceiling invariant."
fi

printf 'every gateway start in up.sh sets TOKENFUSE_MAX_RUN_BUDGET_USD from the ceiling (%d checked, default 5.00, %d figures accepted and %d refused, an old gateway judged both ways)\n' "$LAUNCH_COUNT" "$accepted" "$refused"
