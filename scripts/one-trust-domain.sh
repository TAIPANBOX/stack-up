#!/usr/bin/env bash
# The trust domain has one default, and a seal that maps nothing says so.
#
# WHY
#
# The record plane accepts an event only if its agent id begins
# `agent://<domain>/`, matched as one byte prefix against exactly one value.
# A domain that matches nothing is not an error there: every line is counted
# under `foreign_trust_domain` and the process exits 0.
#
# Measured on this launcher on 2026-08-27, before the change this gate holds:
# `routines.sh` passed `demo.local`, every line on the bus was minted under
# `local.invalid`, `mockryx.local` or `acme`, and the seal wrote 0 records
# across 52 lines while recording status `ok`. Seven segments existed in the
# store and all 35 records in them were the synthetic demo fleet. Not one
# event any real plane emitted had ever been sealed.
#
# WHAT IT LOOKS AT, and there are two properties because there were two faults
#
# 1. ONE DEFAULT. `up.sh` and `routines.sh` each carry the fallback domain, and
#    before this they were two literals held together by the comment `# keep in
#    sync with up.sh`. Nothing checked the pair. A config channel read by only
#    one of them would have made them diverge by design: the same records
#    directory sealed under one name by `./up.sh` and another by the timer.
#
# 2. THE SEAL REFUSES BEFORE IT CONSUMES. The record plane's cursor commits the
#    position it reached even when the run wrote zero records, so one pass under
#    a domain matching nothing marks every line read and no correction recovers
#    them: the next pass answers "nothing new. The cursor is at byte N of N (40
#    line(s), 0 record(s) so far)". Measured 2026-08-27. So a check that runs
#    AFTER the import loop is already too late, and this holds the one that runs
#    BEFORE it. The post-loop branch is checked too, as the backstop.
#
# WHAT IT DELIBERATELY DOES NOT CHECK
#
# That the domain is CORRECT for a given box. This launcher mints under several
# domains on purpose: scopyx uses `local.invalid` because RFC 2606 reserves
# `.invalid`, so a sandbox identity cannot be mistaken for a real one in
# somebody's trail. `--trust-domain` takes one value, so partial refusal is the
# designed state here and only a total one is a fault. Which domain a
# deployment should use is a decision, not a property of this source.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
say() { printf '%s\n' "$*" >&2; }

# ---------------------------------------------------------------- property 1
subjects=0
declare -a defaults=()
for f in up.sh routines.sh; do
	[ -f "$f" ] || continue
	subjects=$((subjects + 1))
	# The assignment, with or without a trailing comment, taking the first.
	d="$(sed -n 's/^DEMO_TRUST_DOMAIN=["'"'"']\{0,1\}\([^"'"'"']*\)["'"'"']\{0,1\}.*/\1/p' "$f" | head -n1)"
	if [ -z "$d" ]; then
		say "FAIL: $f has no DEMO_TRUST_DOMAIN assignment; this gate cannot compare what it cannot find"
		fail=1
		continue
	fi
	# up.sh takes it from the environment; the DEFAULT is what must match.
	case "$d" in
		'${STACK_UP_TRUST_DOMAIN:-'*'}') d="${d#\$\{STACK_UP_TRUST_DOMAIN:-}"; d="${d%\}}" ;;
	esac
	defaults+=("$f=$d")
done

if [ "$subjects" -lt 2 ]; then
	say "FAIL: measured nothing; expected up.sh and routines.sh, found $subjects of them"
	exit 1
fi

first="${defaults[0]#*=}"
for entry in "${defaults[@]}"; do
	if [ "${entry#*=}" != "$first" ]; then
		say "FAIL: the two launchers default to different trust domains:"
		for e in "${defaults[@]}"; do say "         $e"; done
		say "       The same records directory would be sealed under two names."
		fail=1
		break
	fi
done
[ "$fail" -eq 0 ] && printf 'ok   one default trust domain, `%s`, in %d launcher(s).\n' "$first" "$subjects"

# ---------------------------------------------------------------- property 2
if [ ! -f routines.sh ]; then
	say "FAIL: routines.sh is gone, so the seal's reporting was not measured"
	exit 1
fi

# THE ONE THAT PREVENTS THE LOSS. Read from the code rather than trusted from
# a comment, and anchored on the variables it must test rather than on prose.
# It must sit BEFORE the import loop: after it, the cursors have moved.
pre_line="$(grep -n 'if \[ -n "\$probe" \] && \[ "\${seen:-0}" -gt 0 \] && \[ "\${matched:-0}" -eq 0 \]' routines.sh | head -n1 | cut -d: -f1)"
loop_line="$(grep -n 'events --file "\$f" --data "\$RECORDS_DIR"' routines.sh | head -n1 | cut -d: -f1)"

if [ -z "$pre_line" ]; then
	say "FAIL: routines.sh does not check the trust domain BEFORE importing."
	say "       The record plane commits a cursor even for a run that wrote zero"
	say "       records, so a check after the loop cannot prevent the loss it"
	say "       reports. Measured 2026-08-27: 40 events, cursor at byte N of N,"
	say "       0 records, and no later correction recovers them."
	fail=1
elif [ -z "$loop_line" ]; then
	say "FAIL: the import loop is gone, so this gate cannot tell whether the check"
	say "       still runs before it. Measured nothing."
	exit 1
elif [ "$pre_line" -ge "$loop_line" ]; then
	say "FAIL: the trust-domain check is at line $pre_line and the import loop at"
	say "       $loop_line, so it runs AFTER the plane was already told to read."
	say "       By then every cursor has moved and the events are unrecoverable."
	fail=1
else
	printf 'ok   the domain is checked at line %s, before the import loop at %s.\n' "$pre_line" "$loop_line"
fi

# The backstop, for anything the cheap pre-flight parse misses.
branch="$(awk '
  /if \[ "\$written" -eq 0 \] && \[ "\$foreign" -gt 0 \]/ { found = 1 }
  found && /RESULT_STATUS=error/ { print "yes"; exit }
  found && /^  fi$/ { exit }
' routines.sh)"

if [ "$branch" != "yes" ]; then
	say "FAIL: routines.sh does not refuse a seal that wrote nothing while refusing"
	say "       lines for being outside the trust domain. That branch is the"
	say "       backstop behind the pre-flight check above."
	fail=1
else
	printf 'ok   a seal that maps nothing and refuses for the domain is an error, not ok.\n'
fi

# And the counter it rests on has to be read separately from the other seven
# refusal classes, or the branch above fires on refusals that are by design.
if ! grep -q 'foreign_trust_domain' routines.sh; then
	say "FAIL: routines.sh no longer reads the foreign_trust_domain counter, so the"
	say "       branch above can only be testing something else."
	fail=1
fi

exit "$fail"
