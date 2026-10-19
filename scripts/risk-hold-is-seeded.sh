#!/usr/bin/env bash
# shellcheck disable=SC2016 # the patterns here are literal text from up.sh, not expansions
# With --typed-risk-signal, a brokered tool call that the risk signal never reaches
# is held for a person, not allowed for want of a signal. Invariant 28.
#
# WHY
#
# A signal that never arrives leaves a hold_if_signal rule nothing to read, so the
# call went on as if it were harmless. A producer outage, a spent budget, or a call
# padded past the arguments cap each opened the broker to exactly the calls the
# signal exists to stop (wardryx v1.4.0 release notes). A flag that stopped nothing
# when the classifier was silent was the defect, so the launcher seeds the hold with
# the flag, and no other run gets it.
#
# WHAT IT HOLDS
#
# 1. The rule stack-up-typed-risk-hold is written only under --typed-risk-signal.
# 2. The rule reads the signal the proxy adds (action.risk_class), holds the three
#    values that carry a risk (destructive, external_send, financial) at 0.8 or
#    above, holds when the signal is absent (when_absent: hold), and targets every
#    agent (agent://*). A brokered call carries the broker's agent id, which is not
#    one trust domain, so a narrower target would leave an operator's own agents
#    outside the hold.
# 3. The launcher refuses, before it starts wardryx, a wardryx binary that does not
#    read when_absent. An older one refuses the key at start, which is a louder
#    failure, but the flag was asked for by name, so the refusal says why.
# 4. Nothing switches WARDRYX_APPROVAL_SINGLE_USE off. wardryx v1.4.0 says single-use
#    stays on wherever when_absent: hold is set: a padded call has one digest, and a
#    token that fits every such call would lift all of them.
# 5. No rule anywhere sets when_absent to allow or deny.

set -uo pipefail

problems=0
problem() { printf 'risk-hold-is-seeded: %s\n' "$1" >&2; problems=$((problems + 1)); }

if [ ! -f up.sh ]; then
  printf 'risk-hold-is-seeded: measured nothing: up.sh is not here (run from the repository root)\n' >&2
  exit 1
fi

# The seeded rule, from its name line to the YAML terminator.
rule="$(awk '/^- name: stack-up-typed-risk-hold$/ { f = 1 } f { print } f && /^YAML$/ { exit }' up.sh)"
if [ -z "$rule" ]; then
  printf 'risk-hold-is-seeded: measured nothing: up.sh seeds no stack-up-typed-risk-hold rule\n' >&2
  exit 1
fi

# 1. The last if/fi before the rule is the --typed-risk-signal guard.
rule_line="$(grep -n -x -- '- name: stack-up-typed-risk-hold' up.sh | cut -d: -f1 | head -1)"
guard="$(head -n "$rule_line" up.sh | grep -E '^[[:space:]]*(if |fi[[:space:]]*$)' | tail -1)"
case "$guard" in
  *'if [ "$TYPED_RISK_SIGNAL" -eq 1 ]; then'*) ;;
  *) problem "stack-up-typed-risk-hold is written outside the --typed-risk-signal guard (the last if before it is: $(printf '%s' "$guard" | sed -E 's/^[[:space:]]+//'))" ;;
esac

# 2. The rule's content.
for req in \
  '  hold_if_signal:' \
  '  target: "agent://*"' \
  '    name: action.risk_class' \
  '    values: [destructive, external_send, financial]' \
  '    min_probability: 0.8' \
  '    when_absent: hold'
do
  printf '%s\n' "$rule" | grep -qxF -- "$req" \
    || problem "rule stack-up-typed-risk-hold does not contain: $req"
done

# 3. wardryx is checked for when_absent before it starts, and the check refuses.
grep -qF 'bin_reads_setting "$WARDRYX_BIN" when_absent' up.sh \
  || problem "the launcher does not check that the wardryx binary reads when_absent"
if grep -qF 'bin_reads_setting "$WARDRYX_BIN" when_absent' up.sh; then
  grep -n -A3 -F 'bin_reads_setting "$WARDRYX_BIN" when_absent' up.sh | grep -q 'die ' \
    || problem "the check for when_absent does not refuse a wardryx that lacks it (no die within three lines)"
fi

# 4. single-use stays on.
if grep -nE '^[^#]*WARDRYX_APPROVAL_SINGLE_USE=("?)(false|0)("?)([[:space:]]|$)' up.sh >/dev/null; then
  problem "up.sh switches WARDRYX_APPROVAL_SINGLE_USE off, and a hold on a missing signal needs single-use"
fi

# 5. no rule sets when_absent to allow or deny.
if grep -nE '^[^#]*when_absent:[[:space:]]*(allow|deny)' up.sh >/dev/null; then
  problem "a rule in up.sh sets when_absent to allow or deny; only hold is seeded"
fi

if [ "$problems" -ne 0 ]; then
  exit 1
fi
echo "risk-hold-is-seeded: under --typed-risk-signal wardryx is given stack-up-typed-risk-hold (action.risk_class in destructive, external_send or financial at 0.8 or more, held when absent, for every agent); the launcher refuses a wardryx that does not read when_absent; single-use is not switched off; no other run is given the hold"
