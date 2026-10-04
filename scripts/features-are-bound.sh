#!/usr/bin/env bash
# Every scenario in features/ names a teeth case that exists, and every binding
# points at a scenario.
#
# WHY BOTH DIRECTIONS
#
# A scenario bound to nothing is a paragraph describing what somebody wanted, and
# it proves nothing about what the code does. A binding pointing at a case that
# was renamed or deleted is worse than none: it reads as held, and a reader has
# no way to tell without grepping. Two different lies, and each is invisible from
# the other side alone.
#
# This repository had no such gate: features/the-declassify-key-is-minted.feature
# said so in its own header ("this repository has no runner and no binding gate,
# so the binding is by eye"). By eye is the version that rots while nobody is
# looking, so this is the binding made mechanical.
#
# THE BINDING FORMAT
#
# A scenario is bound by one or more comment lines directly under it:
#
#     # -> gates-have-teeth.sh "<the exact case name in run_case>"
#
# The name is the first argument of a `run_case` in scripts/gates-have-teeth.sh,
# which is the mutation harness: a case there plants the fault the scenario
# describes and requires the gate to catch it (or, for a "must not catch" case,
# not to). A scenario's proof is therefore a case that has been red against the
# broken tree.
#
# WHY NOT A BDD RUNNER
#
# The ask the scenarios serve is readability: a person reads Given / When / Then
# instead of a diff. A runner would add a step-definition style to a repository
# that is bash end to end for that, and the binding gate delivers the readable
# half at a fraction of the surface.
#
# WHAT THIS DOES NOT DO
#
# It does not check that a case ASSERTS what its scenario says, and nothing
# mechanical can: the steps are prose and the binding is a pointer. What it
# catches is the pointer breaking, which is the failure that happens on its own.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

TEETH="scripts/gates-have-teeth.sh"

if [ ! -d features ]; then
  echo "FAIL: features/ is gone, so this gate measured nothing" >&2
  exit 1
fi
if [ ! -f "$TEETH" ]; then
  echo "FAIL: $TEETH is gone, so no binding can be judged and this measured nothing" >&2
  exit 1
fi

python3 - "$TEETH" features/*.feature <<'PY'
import re
import sys

teeth_path, *feature_paths = sys.argv[1:]
teeth = open(teeth_path).read()
cases = set(re.findall(r'^run_case "([^"]+)"', teeth, re.M))
if not cases:
    print(f"FAIL: no run_case found in {teeth_path}, so this measured NOTHING.")
    sys.exit(1)

scenarios = 0
bindings = 0
broken = 0
for path in feature_paths:
    current = None
    bound = 0

    def close(path, current, bound):
        global broken
        if current is not None and bound == 0:
            print(f"FAIL: {path}: scenario {current!r} is bound to no case")
            broken += 1

    for line in open(path):
        m = re.match(r"^  Scenario:\s*(.+?)\s*$", line)
        if m:
            close(path, current, bound)
            current, bound = m.group(1), 0
            scenarios += 1
            continue
        b = re.match(r'^\s*# -> gates-have-teeth\.sh "([^"]+)"\s*$', line)
        if b:
            bindings += 1
            if current is None:
                print(f"FAIL: {path}: a binding {b.group(1)!r} sits outside any scenario")
                broken += 1
                continue
            bound += 1
            if b.group(1) not in cases:
                print(f"FAIL: {path}: scenario {current!r} names the case {b.group(1)!r} and no such run_case exists")
                broken += 1
    close(path, current, bound)

if scenarios == 0:
    print("FAIL: no scenarios found in features/, so this gate measured NOTHING.")
    sys.exit(1)
if broken:
    print(f"{broken} broken binding(s).")
    sys.exit(1)
print(f"features: {scenarios} scenarios, {bindings} bindings, 0 broken ({len(cases)} cases in {teeth_path})")
PY
