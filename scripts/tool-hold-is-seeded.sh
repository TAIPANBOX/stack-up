#!/usr/bin/env bash
# shellcheck disable=SC2016 # the patterns here are literal text from up.sh, not expansions
# Under --typed-risk-signal a brokered tool call nothing grants is held for a person, and a
# default run says it has no policy decision point on tool calls. Invariant 34.
#
# WHY
#
# stack-single and stack-k8s hold such a call on a default install. This launcher's broker
# asks wardryx only under the flag, so the hold goes with the flag: a floor on any other run
# would be a rule nothing reads, and it would read as a control. That makes three things that
# have to stay together, and a change to any one of them is silent: the block, the flag that
# guards it, and the sentence that tells a stranger what a default run does not have.
#
# WHAT IT HOLDS
#
# 1. The block is written only under --typed-risk-signal, and the broker's policy gate is
#    started nowhere else.
# 2. The floor's target is "*", so an agent id with no scheme cannot walk past it, and it
#    says when_no_grant: hold, a word wardryx reads. It is the one such line in the launcher.
# 3. grant-drills is the stacks' rule, on agent://mockryx.local/* and no wider, and it is the
#    only grant of every tool. grant-broker-demo names one tool, one id and the broker's
#    static key, because that is how the example this run prints reaches it.
# 4. The launcher refuses, before the block and before wardryx starts, a binary that does
#    not read when_no_grant.
# 5. The pins are at least wardryx v2.6.0 and tokenfuse v1.23.0: the first reads the rule, the
#    second says why it held. scripts/pins-are-release-tags.sh holds their form.
# 6. --typed-plan says so under the flag and not without it.
# 7. README.md says a default run has no policy decision point on tool calls.

set -uo pipefail

problems=0
problem() { printf 'tool-hold-is-seeded: %s\n' "$1" >&2; problems=$((problems + 1)); }

if [ ! -f up.sh ] || [ ! -f README.md ]; then
  printf 'tool-hold-is-seeded: measured nothing: up.sh or README.md is not here (run from the repository root)\n' >&2
  exit 1
fi

block="$(awk '/^# tool-hold: begin/ { f = 1 } f { print } /^# tool-hold: end/ { f = 0 }' up.sh)"
if [ -z "$block" ]; then
  printf 'tool-hold-is-seeded: measured nothing: up.sh writes no tool-hold block\n' >&2
  exit 1
fi

flag_guard='if [ "$TYPED_RISK_SIGNAL" -eq 1 ]; then'
guard_of() { # LINE: the last if or fi above it
  head -n "$1" up.sh | grep -E '^[[:space:]]*(if |fi[[:space:]]*$)' | tail -1
}

# 1. the block and the broker's gate, each under the flag.
begin_line="$(grep -n '^# tool-hold: begin' up.sh | cut -d: -f1 | head -1)"
guard="$(guard_of "$begin_line")"
case "$guard" in
  *"$flag_guard"*) ;;
  *) problem "the tool-hold block is written outside the --typed-risk-signal guard (the last if before it is: $(sed -E 's/^[[:space:]]+//' <<<"$guard"))" ;;
esac
gates=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  gates=$((gates + 1))
  guard="$(guard_of "$line")"
  case "$guard" in
    *"$flag_guard"*) ;;
    *) problem "up.sh:$line starts the broker's policy gate outside --typed-risk-signal, so a floor that goes with the flag would be off where the gate is on" ;;
  esac
done <<<"$(grep -nE '^[[:space:]]*BROKER_WARDRYX_ENV=\(' up.sh | grep -vE 'BROKER_WARDRYX_ENV=\(\)[[:space:]]*$' | cut -d: -f1)"
if [ "$gates" -eq 0 ]; then
  printf 'tool-hold-is-seeded: measured nothing: up.sh never fills BROKER_WARDRYX_ENV\n' >&2
  exit 1
fi

# 2 and 3. the block's lines.
for req in \
  '- name: tool-hold' \
  '  target: "*"' \
  '  when_no_grant: hold' \
  '- name: grant-drills' \
  '  target: agent://mockryx.local/*' \
  '  grant_tool: ["*"]' \
  '- name: grant-broker-demo' \
  '  target: agent://$DEMO_TRUST_DOMAIN/mcp-broker-demo' \
  '  grant_tool: [ask]' \
  '  require_identity_source: [client-key]' \
  '  deny_if_chain_unproven: true'
do
  grep -qxF -- "$req" <<<"$block" \
    || problem "the tool-hold block does not contain: $req"
done
floors="$(grep -cE '^[[:space:]]*(- )?when_no_grant:' up.sh)"
[ "$floors" -eq 1 ] || problem "up.sh writes when_no_grant: on $floors lines; the block's is the only one"
open_grants="$(grep -cF '  grant_tool: ["*"]' <<<"$block")"
[ "$open_grants" -le 1 ] || problem "the block grants every tool $open_grants times; grant-drills is the only rule that may"

# 4. the refusal, above the block.
check_line="$(grep -nF 'bin_reads_setting "$WARDRYX_BIN" when_no_grant' up.sh | cut -d: -f1 | head -1)"
if [ -z "$check_line" ]; then
  problem "the launcher does not check that the wardryx binary reads when_no_grant"
else
  [ "$check_line" -lt "$begin_line" ] || problem "the launcher checks for when_no_grant after it writes the block"
  grep -q 'die ' <<<"$(sed -n "$check_line,$((check_line + 2))p" up.sh)" \
    || problem "the check for when_no_grant does not refuse a wardryx that lacks it (no die within three lines)"
fi

# 5. the floors under the two pins.
at_least() { # COMPONENT FLOOR
  local tag
  tag="$(sed -nE 's/^[[:space:]]+'"$1"'\)[[:space:]]+echo "(v[0-9.]+) .*/\1/p' up.sh)"
  if [ -z "$tag" ]; then
    problem "pin_of has no release tag for $1, so its floor was not judged"
  elif [ "$(printf '%s\n%s\n' "$2" "$tag" | sort -V | head -1)" != "$2" ]; then
    problem "$1 is pinned to $tag, below $2, which the tool hold needs"
  fi
}
at_least wardryx v2.6.0
at_least tokenfuse v1.23.0

# 6. the plan, from the launcher itself.
plan_on="$(./up.sh --with-typed --typed-risk-signal --typed-plan 2>&1)"
plan_off="$(./up.sh --with-typed --typed-plan 2>&1)"
if [ -z "$plan_on" ] || [ -z "$plan_off" ]; then
  printf 'tool-hold-is-seeded: measured nothing: --typed-plan printed nothing\n' >&2
  exit 1
fi
grep -q '^typed: tool hold: on with this flag' <<<"$plan_on" \
  || problem "--typed-plan under the flag does not say the tool hold is on"
if grep -q '^typed: tool hold' <<<"$plan_off"; then
  problem "--typed-plan without the flag says the tool hold is on, and nothing reads it there"
fi

# 7. what a stranger is told.
grep -qi 'a default run has no policy decision point on tool calls' README.md \
  || problem "README.md does not say that a default run has no policy decision point on tool calls"

if [ "$problems" -ne 0 ]; then
  exit 1
fi
echo "tool-hold-is-seeded: under --typed-risk-signal, and nowhere else, wardryx is given tool-hold (target \"*\", when_no_grant: hold) with grant-drills and grant-broker-demo; a wardryx that does not read it is refused; the pins are at least wardryx v2.6.0 and tokenfuse v1.23.0; the plan and README say so"
