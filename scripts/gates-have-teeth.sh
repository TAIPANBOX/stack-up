#!/usr/bin/env bash
# Checks that the gates in `scripts/` still FAIL on the faults they exist to
# catch, still PASS on what they must not catch, and REFUSE to report success
# when they measured nothing at all.
#
# WHY
#
# Every gate here parses text, and a text parser does not break loudly: it
# stops matching and reports success. The mutants that proved each one existed
# as prose, in commit messages and in the `*(gate: ...)*` markers in CLAUDE.md,
# which is a record of what was true once. Nothing ran them again.
#
# A gate that has quietly stopped catching anything looks exactly like a gate
# with nothing to catch, and stays that way until the fault it guards ships.
#
# WHY THE THIRD PROPERTY IS SEPARATE FROM THE FIRST
#
# Because here it found a real hole, the third in the estate on the same day
# and the worst of them by consequence.
#
# `loopback-only.sh` skips a launcher file that is not there, and skipping all
# three was a pass: it printed "every resolved address, bind and connection in
# the launcher is loopback" and exited 0 having read no address at all.
# Renaming the launchers, or moving them into a subdirectory, is ordinary
# housekeeping.
#
# This is the first thing a stranger runs, and the invariant is that it does
# not publish a money plane onto whatever network the laptop is on. Fixed in
# the commit before this one; the case below is what keeps it fixed.
#
# HOW IT MUTATES WITHOUT LEAVING A MESS
#
# It edits tracked files in place, so it refuses to start unless the tree is
# clean, restores with `git checkout` after every case, restores again from a
# trap on any exit path including a kill, and asserts the tree is clean before
# reporting success.
#
#
# A GATE THAT IS ALREADY FAILING CANNOT BE JUDGED
#
# No case proves anything if the gate was already failing before the mutation.
# So every case runs the gate on the UNMUTATED tree first and reports
# UNJUDGEABLE. Found on 2026-08-09 in it-rat, where one gate was legitimately
# red and a case against it would have been indistinguishable from a working
# one.
#
# It covered only the fail-cases at first, which left the mirror of the same
# bug: on a red gate a pass-case reports OVEREAGER, "the gate failed on
# something it must not catch", and sends the reader to look at a harmless
# mutation. The verdict was being given without the predicate it depends on.
#
# A MUTATION THAT DID NOT APPLY PROVES NOTHING
#
# Every edit asserts it changed the file. A case whose edit applied nothing is
# a failure here, not a pass. That is not hypothetical: five such mutations
# were caught across idryx and tokenfuse on 2026-08-09, and three of the five
# had been verified BY HAND against the same gate minutes earlier. The hand
# version and the harness version differ only in how many layers of quoting sit
# between the text and python, which is exactly the difference nobody sees.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

if [ -n "$(git status --porcelain)" ]; then
	printf 'this script mutates tracked files, so it needs a clean tree.\n'
	printf 'commit or stash first; it restores with `git checkout` and cannot\n'
	printf 'tell your edits from its own.\n'
	exit 1
fi

# Untracked files too: a mutation may RENAME a tracked file, and `git checkout`
# restores the original while leaving the new name behind. And the INDEX, since
# a gate may read `git ls-files` rather than the disk, so a mutation has to move
# the file in both. Safe because this
# script refuses to start unless the tree is clean, so anything untracked
# during a run was created by the run. `-x` is deliberately absent: ignored
# build output is not ours to delete.
restore() {
	git reset -q --hard HEAD 2>/dev/null
	git clean -fdq 2>/dev/null
}
baseline_dir="$(mktemp -d)"

# One trap for both, because a second `trap ... EXIT` REPLACES the first
# rather than adding to it. Writing them separately disarmed `restore` on
# every interrupt path, which would leave a mutated tree behind on Ctrl-C.
cleanup() {
	restore
	rm -rf "$baseline_dir"
}
trap cleanup EXIT INT TERM


failures=0
cases=0

# run_case <name> <expect: fail|pass> <gate> <python edit> [required output]
#
# The needle separates "it failed" from "it failed for the reason this case is
# about". Without it, a case expecting failure is satisfied by any failure,
# including one this harness caused itself.
run_case() {
	local name="$1" expect="$2" gate="$3" edit="$4" needle="${5:-}"
	cases=$((cases + 1))

	# The baseline applies to EVERY case, not only the ones expecting a failure.
	# It was `fail`-only until 2026-08-09, which left the mirror of the bug it was
	# written for: on a gate that is already red, a `pass` case reports OVEREAGER,
	# "the gate failed on something it must not catch", and sends the reader to
	# look at a harmless mutation while the gate was failing without it. Neither
	# verdict means anything on a red gate, so neither is given.
	skip_baseline=0
	if [ "$expect" = fail_env ]; then
		# `fail` with the baseline skipped, for cases whose fault IS the command
		# rather than a mutation: red before and after is the point there.
		expect=fail
		skip_baseline=1
	fi

	if [ "$skip_baseline" = 0 ]; then
		local key base_out
		key="$baseline_dir/$(printf '%s' "$gate" | cksum | tr -d ' ')"
		if [ ! -f "$key" ]; then
			if eval "$gate" >/dev/null 2>&1; then printf 'green' >"$key"; else printf 'red' >"$key"; fi
		fi
		base_out="$(cat "$key")"
		if [ "$base_out" = red ]; then
			printf 'UNJUDGEABLE  %s\n             the gate is already failing on a clean tree, so neither a\n             failure nor a pass after the mutation would prove anything\n' "$name"
			failures=$((failures + 1))
			return
		fi
	fi

	if ! python3 -c "$edit"; then
		printf 'BROKEN  %s\n        its mutation did not apply, so this case proved nothing\n' "$name"
		failures=$((failures + 1))
		restore
		return
	fi

	local out rc
	out=$(eval "$gate" 2>&1)
	rc=$?
	restore

	# Exit code first, then wording. Checking the needle before the expectation
	# turns "it did not fail at all" into "it failed for the wrong reason",
	# which sends the reader to look at prose when the gate is toothless.
	if [ "$expect" = fail ] && [ "$rc" -ne 0 ] && [ -n "$needle" ] &&
		! printf '%s' "$out" | grep -qF -- "$needle"; then
		printf 'WRONG REASON  %s\n              it failed, but not saying: %s\n' "$name" "$needle"
		failures=$((failures + 1))
		return
	fi
	if [ "$expect" = fail ] && [ "$rc" -eq 0 ]; then
		printf 'TOOTHLESS  %s\n           the gate passed on a fault it exists to catch\n' "$name"
		failures=$((failures + 1))
	elif [ "$expect" = pass ] && [ "$rc" -ne 0 ]; then
		printf 'OVEREAGER  %s\n           the gate failed on something it must not catch\n' "$name"
		failures=$((failures + 1))
		printf '%s\n' "$out" | head -4 | sed 's/^/           /'
	else
		printf 'ok  %-58s (%s)\n' "$name" "$expect"
	fi
}

py() { printf 'def edit(p, a, b):\n    s = open(p).read()\n    assert a in s, "pattern not found in " + p\n    open(p, "w").write(s.replace(a, b, 1))\n%s\n' "$1"; }

echo "=== faults each gate must catch ==="

# The whole invariant: a bind or a URL in the launcher points at loopback and
# nowhere else. This is the edit somebody makes to reach the dashboard from
# another machine, and it works, which is why nothing else would notice.
run_case "loopback-only: a launcher URL leaves loopback" fail \
	'./scripts/loopback-only.sh' \
	"$(py 'edit("up.sh", "WARDRYX_URL=\"http://127.0.0.1:$WARDRYX_PORT\"", "WARDRYX_URL=\"http://0.0.0.0:$WARDRYX_PORT\"")')" \
	"is not loopback"

# The two launchers drift apart on the trust domain. This is the edit an
# operator makes when the seal imports nothing: change the one they found,
# leave the other, and the same records directory is then sealed under one
# name by ./up.sh and another by the timer.
run_case "one-trust-domain: the two launchers disagree" fail \
	'./scripts/one-trust-domain.sh' \
	"$(py 'edit("routines.sh", "DEMO_TRUST_DOMAIN=\"demo.local\"", "DEMO_TRUST_DOMAIN=\"acme.example\"")')" \
	"different trust domains"

# THE ONE THAT WAS TRUE UNTIL 2026-08-27. Take the backstop away and the
# routine reports ok on a run that sealed none of a full bus, which is how
# seven segments came to hold nothing but the synthetic demo fleet while four
# real planes wrote to the same directory for weeks.
run_case "one-trust-domain: a seal that maps nothing reports ok again" fail \
	'./scripts/one-trust-domain.sh' \
	"$(py 'edit("routines.sh", "  if [ \"$written\" -eq 0 ] && [ \"$foreign\" -gt 0 ]; then", "  if false; then")')" \
	"does not refuse a seal that wrote nothing"

# THE ONE THAT MATTERS MORE. Move the pre-flight check after the import loop
# and it still reports the fault, correctly, on a run that has already
# committed a cursor past every line. The events are gone by then.
run_case "one-trust-domain: the domain is checked after the plane was read" fail \
	'./scripts/one-trust-domain.sh' \
	"$(py 'import re
s = open("routines.sh").read()
m = re.search(r"  local probe seen matched\n(?:.*\n)*?  fi\n\n", s)
assert m, "pre-flight block not found"
block = m.group(0)
s = s.replace(block, "", 1)
anchor = "  if [ ! -d \"$RECORDS_DIR\" ]; then"
assert anchor in s, "post-loop anchor not found"
s = s.replace(anchor, block + anchor, 1)
open("routines.sh", "w").write(s)')" \
	"runs AFTER the plane was already told to read"

echo
echo "=== and what they must NOT catch ==="

# The three shapes the first version of this gate got wrong, and reported five
# failures over on a tree that was correct: an empty assignment filled in
# later, a value that is a reference rather than a literal, and an address
# inside prose. A gate that flags any of these is deleted by whoever hits it.
run_case "loopback-only: a placeholder, a reference and an address in prose" pass \
	'./scripts/loopback-only.sh' \
	"$(py 'edit("up.sh", "WARDRYX_URL=\"\"", "WARDRYX_URL=\"\"\nSPARE_URL=\"\"\nMIRROR_URL=\"$WARDRYX_URL\"\n# see https://example.com/docs for why this is loopback only")')"

# up.sh reads the domain from the environment and routines.sh from a file.
# Both are correct and they LOOK different; a gate comparing the raw lines
# rather than the defaults would fire on a tree that is right.
run_case "one-trust-domain: two spellings of the same default" pass \
	'./scripts/one-trust-domain.sh' \
	"$(py 'edit("routines.sh", "DEMO_TRUST_DOMAIN=\"demo.local\"", "DEMO_TRUST_DOMAIN=\"demo.local\"   # read from the file below")')"

echo
echo "=== and the one this estate learned the hard way ==="
echo "    a gate whose subject is gone must SAY so, not report OK on nothing"

# THE HOLE. All three launcher files renamed: every one is skipped, and before
# 2026-08-09 skipping every one of them was a clean run.
# The same hole, one gate over: both subjects renamed away.
run_case "one-trust-domain: no launcher left to compare" fail \
	'./scripts/one-trust-domain.sh' \
	"$(py 'import subprocess, os
n = 0
for f in ("up.sh", "routines.sh"):
    if os.path.exists(f):
        subprocess.run(["git", "mv", f, f[:-3] + ".bash"], check=True)
        n += 1
assert n == 2, "expected both launchers"')" \
	"measured nothing"

run_case "loopback-only: no launcher left to read" fail \
	'./scripts/loopback-only.sh' \
	"$(py 'import subprocess, os
n = 0
for f in ("up.sh", "down.sh", "routines.sh"):
    if os.path.exists(f):
        subprocess.run(["git", "mv", f, f[:-3] + ".bash"], check=True)
        n += 1
assert n, "no launcher files in this repo"')" \
	"measured nothing"

echo
if [ -n "$(git status --porcelain)" ]; then
	printf 'FAIL: this script left the tree dirty, so it cannot be trusted about anything above\n'
	git status --porcelain | head -5
	exit 1
fi

if [ "$failures" -gt 0 ]; then
	printf '%d of %d cases failed.\n' "$failures" "$cases"
	printf 'A gate that has quietly stopped catching anything looks exactly like a gate\n'
	printf 'with nothing to catch, and stays that way until the fault it guards ships.\n'
	exit 1
fi

printf 'OK: %d cases. Every gate fails on its own fault, passes on a non-fault,\n' "$cases"
printf '    and refuses to report success when it measured nothing.\n'
