#!/usr/bin/env bash
# Enforces CLAUDE.md invariant 27: the demo's calls through the gateway are made
# after every plane that answers them, so the demo shows the Breaker and not a
# gap in the start order.
#
# WHY
#
# Two ordering faults made the demo's six calls answer nothing, both measured on
# a Linux bring-up on 2026-10-19, and neither one is loud: the stand comes up,
# the summary says "the gateway answered nothing", and the dashboard shows only
# the seed.
#
# 1. A gateway configured with a control plane refuses every call that carries a
#    run id (503 seed_pending) until it has read the Cloud's money state
#    (tokenfuse invariant 103). The Cloud was started after the gateway, so the
#    startup seed found nothing listening.
# 2. The gateway fails closed on wardryx, and the demo ran before wardryx was
#    started.
#
# WHAT IT HOLDS, in up.sh, by line order of non-comment lines
#
# 1. The first Cloud start ("$CLOUD_BIN" at the command position) and its
#    `wait_health cloud` come before the first gateway start ("$GATEWAY_BIN" at
#    the command position, the mcp-broker subcommand excluded).
# 2. `demo_traffic` is called exactly once (the definition excluded).
# 3. That call comes after `wait_health wardryx`, and before the first start of
#    a plane that reads the bus the demo fills (`register idryx`,
#    `register heraldyx`, `register trailryx`, whichever exist).
#
# WHAT IT DOES NOT HOLD
#
# That a running stand answers the demo with two 200s and four 402s. That needs
# the built binaries and is a bring-up, not this text check.
#
# AND IT REFUSES TO REPORT OK ON NOTHING
#
# No up.sh, no Cloud start, no gateway start, no wardryx health wait, or no
# demo call, and it says it measured nothing and fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$ROOT/up.sh"

fail() { printf 'demo-runs-after-its-planes: %s\n' "$*" >&2; exit 1; }

[[ -f "$LAUNCHER" ]] || fail "no up.sh at $LAUNCHER, so this measured nothing"

# First non-comment line number matching an extended regex, or empty. The regex
# goes through the environment, because awk -v would eat its backslashes.
first() { RE="$1" awk '!/^[[:space:]]*#/ && $0 ~ ENVIRON["RE"] { print NR; exit }' "$LAUNCHER"; }

cloud_start="$(first '^[[:space:]]*"\$CLOUD_BIN"')"
cloud_wait="$(first '^[[:space:]]*wait_health cloud ')"
# The mcp-broker start is "$GATEWAY_BIN" mcp-broker; it is not the gateway.
gateway_start="$(awk '!/^[[:space:]]*#/ && /^[[:space:]]*"\$GATEWAY_BIN"/ && !/mcp-broker/ { print NR; exit }' "$LAUNCHER")"
wardryx_wait="$(first '^[[:space:]]*wait_health wardryx ')"
demo_calls="$(awk '!/^[[:space:]]*#/ && /^[[:space:]]*demo_traffic[[:space:]]*$/ { print NR }' "$LAUNCHER")"

[[ -n "$cloud_start" ]] || fail "no Cloud start (\"\$CLOUD_BIN\" at the command position) in up.sh, so this measured nothing"
[[ -n "$gateway_start" ]] || fail "no gateway start (\"\$GATEWAY_BIN\" at the command position) in up.sh, so this measured nothing"
[[ -n "$wardryx_wait" ]] || fail "no 'wait_health wardryx' in up.sh, so this measured nothing"
[[ -n "$demo_calls" ]] || fail "no demo_traffic call in up.sh, so this measured nothing"

problems=0
report() { printf 'demo-runs-after-its-planes: %s\n' "$*" >&2; problems=$((problems + 1)); }

if [[ "$cloud_start" -gt "$gateway_start" ]]; then
  report "the Cloud starts on line $cloud_start, after the gateway on line $gateway_start: the gateway's startup seed finds no Cloud and refuses run calls 503 seed_pending"
fi
if [[ -z "$cloud_wait" ]]; then
  report "no 'wait_health cloud' in up.sh: the gateway may start before the Cloud listens"
elif [[ "$cloud_wait" -gt "$gateway_start" ]]; then
  report "'wait_health cloud' is on line $cloud_wait, after the gateway start on line $gateway_start"
fi

n_calls="$(printf '%s\n' "$demo_calls" | wc -l | tr -d ' ')"
if [[ "$n_calls" -ne 1 ]]; then
  report "demo_traffic is called $n_calls times (lines $(printf '%s' "$demo_calls" | tr '\n' ' ')), expected once"
fi
demo_call="$(printf '%s\n' "$demo_calls" | head -1)"
if [[ "$demo_call" -lt "$wardryx_wait" ]]; then
  report "demo_traffic is called on line $demo_call, before 'wait_health wardryx' on line $wardryx_wait: the gateway fails closed on wardryx"
fi

readers=0
for reader in idryx heraldyx trailryx; do
  line="$(first "^[[:space:]]*register $reader ")"
  [[ -n "$line" ]] || continue
  readers=$((readers + 1))
  if [[ "$demo_call" -gt "$line" ]]; then
    report "demo_traffic is called on line $demo_call, after $reader starts on line $line: $reader reads the bus the demo fills"
  fi
done

if [[ "$problems" -gt 0 ]]; then
  fail "$problems problem(s). See CLAUDE.md, invariant 27."
fi
printf 'OK: the Cloud (line %s) starts before the gateway (line %s); demo_traffic is called once, on line %s, after wardryx answers (line %s) and before %s bus reader(s) start.\n' \
  "$cloud_start" "$gateway_start" "$demo_call" "$wardryx_wait" "$readers"
