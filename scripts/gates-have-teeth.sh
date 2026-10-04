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
# invariant: components.json says what this launcher actually installs.
#
# Two cases and they check different halves. The first is ordinary drift: a
# plane brought up and not declared. The second is the one this estate keeps
# learning: a reader whose subject moved reports agreement about nothing, so
# `register` disappearing from up.sh must say "measured NOTHING" rather than
# comparing an empty list against an empty list and passing.
run_case "manifest-is-true: a plane is brought up and not declared" fail \
	'./scripts/manifest-is-true.sh' \
	"$(py 'import json
p = "components.json"
d = json.load(open(p))
c = d["components"][0]["checked"]
before = len(c["installs_services"])
c["installs_services"] = [s for s in c["installs_services"] if s != "scopyx"]
assert len(c["installs_services"]) == before - 1, "scopyx was not in the declared list"
json.dump(d, open(p, "w"), indent=2)')" \
	"and components.json does not say so"

run_case "manifest-is-true: up.sh stops registering anything" fail \
	'./scripts/manifest-is-true.sh' \
	"$(py 'import re
s = open("up.sh").read()
out, n = re.subn(r"(?m)^(\s*)register\s", r"\1supervise ", s)
assert n > 0, "up.sh has no register call to remove"
open("up.sh", "w").write(out)')" \
	"measured NOTHING"

run_case "loopback-only: a launcher URL leaves loopback" fail \
	'./scripts/loopback-only.sh' \
	"$(py 'edit("up.sh", "WARDRYX_URL=\"http://127.0.0.1:$WARDRYX_PORT\"", "WARDRYX_URL=\"http://0.0.0.0:$WARDRYX_PORT\"")')" \
	"is not loopback"

run_case "revoke-key-not-printed: the mint log prints the key itself" fail \
	'./scripts/revoke-key-not-printed.sh' \
	"$(py 'edit("up.sh", "log \"vouchryx: minting a revocation key\"", "log \"vouchryx: minting a revocation key: $(cat \"$DELEG_DIR/revoke.key\" 2>/dev/null)\"")')" \
	"outside the VOUCHRYX_REVOKE_KEYS assignment"

# The edit somebody makes without reading tokenfuse#319: drop the one
# assignment that turns shadow mode off, on one of the two gateway starts.
# edit() replaces only the first occurrence, so the other start still sets it.
run_case "gateway-cache-is-off: one gateway start drops TOKENFUSE_CACHE" fail \
	'./scripts/gateway-cache-is-off.sh' \
	"$(py 'edit("up.sh", "  TOKENFUSE_CACHE=\"off\" \\", "")')" \
	"does not set TOKENFUSE_CACHE"

# invariant 11: the gateway's declassify key is minted per run and reaches the
# gateway through its environment only. POST /v1/fuse/declassify lifts a run's
# taint label and its credential is optional in the gateway, so a start without
# the key leaves the endpoint open to anything that reaches the gateway port.
# edit() replaces only the first occurrence, so the other start still sets it.
run_case "declassify-is-keyed: one gateway start drops TOKENFUSE_DECLASSIFY_KEY" fail \
	'./scripts/declassify-is-keyed.sh' \
	"$(py 'edit("up.sh", "  TOKENFUSE_DECLASSIFY_KEY=\"$GATEWAY_DECLASSIFY_KEY\" \\\n", "")')" \
	"does not set TOKENFUSE_DECLASSIFY_KEY"

# A literal: a key committed to a public repository is no key.
run_case "declassify-is-keyed: the key becomes a literal" fail \
	'./scripts/declassify-is-keyed.sh' \
	"$(py 'edit("up.sh", "TOKENFUSE_DECLASSIFY_KEY=\"$GATEWAY_DECLASSIFY_KEY\"", "TOKENFUSE_DECLASSIFY_KEY=\"fixed-key\"")')" \
	"not set from a variable"

# The gateway is started as `env VAR=... bin`. An argument to env is on env's
# own command line for the moment before it execs, where ps can read it; a
# prefix assignment ahead of env is not.
run_case "declassify-is-keyed: the key becomes an argument to env" fail \
	'./scripts/declassify-is-keyed.sh' \
	"$(py 'edit("up.sh", "  TOKENFUSE_DECLASSIFY_KEY=\"$GATEWAY_DECLASSIFY_KEY\" \\\n  env ${DELEG_ENV[@]+\"${DELEG_ENV[@]}\"} \\\n", "  env ${DELEG_ENV[@]+\"${DELEG_ENV[@]}\"} \\\n  TOKENFUSE_DECLASSIFY_KEY=\"$GATEWAY_DECLASSIFY_KEY\" \\\n")')" \
	"is an argument to env"

# Minted, but not fresh: one key for every run is a published key.
run_case "declassify-is-keyed: the mint becomes a fixed string" fail \
	'./scripts/declassify-is-keyed.sh' \
	"$(py 'edit("up.sh", "GATEWAY_DECLASSIFY_KEY=\"$(rand_hex 24)\"", "GATEWAY_DECLASSIFY_KEY=\"fixed-key\"")')" \
	"never minted with rand_hex"

# The mint below the first start: the first gateway runs with an empty key,
# which the gateway reads as unset.
run_case "declassify-is-keyed: the mint moves below the first gateway start" fail \
	'./scripts/declassify-is-keyed.sh' \
	"$(py 'import re
s = open("up.sh").read()
m = re.search(r"^GATEWAY_DECLASSIFY_KEY=\"\$\(rand_hex 24\)\"\n\[ -n [^\n]*\n[^\n]*\n", s, re.M)
assert m, "mint block not found"
blk = m.group(0)
t = s.replace(blk, "", 1)
anchor = "register gateway \"$!\" INT\n"
assert anchor in t
t = t.replace(anchor, anchor + blk, 1)
assert t != s
open("up.sh", "w").write(t)')" \
	"is minted after the first gateway start"

# The gateway reads an EMPTY key as unset. A mint that fails quietly must stop
# the launcher, not start the gateway with the endpoint open.
run_case "declassify-is-keyed: the refusal on an empty mint is removed" fail \
	'./scripts/declassify-is-keyed.sh' \
	"$(py 'import re
s = open("up.sh").read()
t = re.sub(r"\[ -n \"\$GATEWAY_DECLASSIFY_KEY\" \] \\\n  \|\| die [^\n]*\n", "", s, count=1)
assert t != s
open("up.sh", "w").write(t)')" \
	"no refusal on an empty"

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

# invariant 10: the typed-answers data mode. Every one of these is an edit
# somebody makes with a reason: to let a blank file through, to loosen the URL
# check so a proxy path works, to make typed answers the default, to print the
# key once while debugging, or to drop the lines that keep a stale exported
# variable from redirecting the key.
run_case "typed-mode: a blank key file is accepted" fail \
	'./scripts/typed-mode.sh' \
	"$(py 'edit("up.sh", "grep -q '"'"'[^[:space:]]'"'"' \"$TYPED_KEY_FILE\"", "true")')" \
	"jev, empty file: exit 0, wanted 2"

run_case "typed-mode: own-model takes a URL that does not end in /v1" fail \
	'./scripts/typed-mode.sh' \
	"$(py 'edit("up.sh", "(/[^?#[:space:]]*)?/v1/?$ ]]", ".*$ ]]")')" \
	"own-model, URL not /v1: exit 0, wanted 2"

run_case "typed-mode: --with-typed alone stops being the stub" fail \
	'./scripts/typed-mode.sh' \
	"$(py 'edit("up.sh", "TYPED_BACKEND=\"${TYPRYX_BACKEND:-stub}\"", "TYPED_BACKEND=\"${TYPRYX_BACKEND:-jev}\"")')" \
	"last plan does not contain: env: TYPRYX_BACKEND=stub"

run_case "typed-mode: typed answers become the default" fail \
	'./scripts/typed-mode.sh' \
	"$(py 'edit("up.sh", "WITH_TYPED=0\n# The typed-answers", "WITH_TYPED=1\n# The typed-answers")')" \
	"no flags: output does not say: typryx is not started"

run_case "typed-mode: the launch log prints the key file's content" fail \
	'./scripts/typed-mode.sh' \
	"$(py 'edit("up.sh", "log \"typryx data: $TYPED_LEAVES\"", "log \"typryx data: $TYPED_LEAVES $(cat \"$TYPED_KEY_FILE\" 2>/dev/null)\"")')" \
	"reads the key file instead of only naming it"

run_case "typed-mode: a plan writes into the state directory" fail \
	'./scripts/typed-mode.sh' \
	"$(py 'edit("up.sh", "resolve_typed_mode\nif [ \"$TYPED_PLAN\" -eq 1 ]", "resolve_typed_mode\nmkdir -p \"$STACK_UP_HOME\"\nif [ \"$TYPED_PLAN\" -eq 1 ]")')" \
	"a refusal or a plan created"

run_case "typed-mode: a stale TYPRYX_JEV_URL can redirect the key" fail \
	'./scripts/typed-mode.sh' \
	"$(py 'edit("up.sh", "TYPRYX_ENV=(-u TYPRYX_JEV_URL -u TYPRYX_JEV_MODEL\n", "TYPRYX_ENV=(-u TYPRYX_JEV_MODEL\n")')" \
	"last plan does not contain: env: -u TYPRYX_JEV_URL"

# Found running typryx through the array, not by the plan: `env` stops reading
# options at the first NAME=VALUE, so an `-u` placed after one is executed as a
# program. The plan looked right and the launch would have died.
run_case "typed-mode: an -u placed after an assignment in the env array" fail \
	'./scripts/typed-mode.sh' \
	"$(py 'edit("up.sh", "TYPRYX_ENV=(-u TYPRYX_JEV_KEY_FILE -u TYPRYX_JEV_URL -u TYPRYX_JEV_MODEL -u TYPRYX_OPENAI_KEY_FILE\n", "TYPRYX_ENV=(-u TYPRYX_JEV_KEY_FILE -u TYPRYX_JEV_URL -u TYPRYX_JEV_MODEL\n")
edit("up.sh", "\"TYPRYX_OPENAI_MODEL=$TYPED_MODEL\")\n      fi", "\"TYPRYX_OPENAI_MODEL=$TYPED_MODEL\" -u TYPRYX_OPENAI_KEY_FILE)\n      fi")')" \
	"an -u comes after an assignment"

# The local training log (`--typed-training`). Each of these is an edit with a
# reason: make it on by default because "people will want it", drop the refusal
# that says it has nothing to attach to, let the training variable jump ahead of
# the `-u` entries, skip the tightening of a directory that already exists, or
# stop asking whether typryx can log at all.
run_case "typed-mode: the training log is on by default" fail \
	'./scripts/typed-mode.sh' \
	"$(py 'edit("up.sh", "TYPED_PLAN=0\nTYPED_TRAINING=0\n", "TYPED_PLAN=0\nTYPED_TRAINING=1\n")')" \
	"--typed-mode off: exit 2, wanted 0"

run_case "typed-mode: --typed-training with no typryx is ignored, not refused" fail \
	'./scripts/typed-mode.sh' \
	"$(py 'edit("up.sh", "    [ \"$WITH_TYPED\" -eq 1 ] || typed_refuse \"--typed-training needs typryx to run", "    [ \"$WITH_TYPED\" -eq 1 ] || true # \"--typed-training needs typryx to run")')" \
	"training, no typryx to attach to: exit 0, wanted 2"

run_case "typed-mode: the training variable jumps ahead of the -u entries" fail \
	'./scripts/typed-mode.sh' \
	"$(py 'edit("up.sh", "TYPRYX_ENV+=(\"TYPRYX_TRAINING_DIR=$TYPED_TRAINING_DIR\")", "TYPRYX_ENV=(\"TYPRYX_TRAINING_DIR=$TYPED_TRAINING_DIR\" \"${TYPRYX_ENV[@]}\")")')" \
	"an -u comes after an assignment"

run_case "typed-mode: the training directory is made with the default umask" fail \
	'./scripts/typed-mode.sh' \
	"$(py 'edit("up.sh", "( umask 077; mkdir -p \"$1\" ) && chmod 700 \"$1\"", "mkdir -p \"$1\"")')" \
	"a fresh training directory is"

run_case "typed-mode: a training directory that already existed stays loose" fail \
	'./scripts/typed-mode.sh' \
	"$(py 'edit("up.sh", "( umask 077; mkdir -p \"$1\" ) && chmod 700 \"$1\"", "( umask 077; mkdir -p \"$1\" )")')" \
	"already existed at 755"

run_case "typed-mode: an older typryx is judged able to keep a log" fail \
	'./scripts/typed-mode.sh' \
	"$(py 'edit("up.sh", "case \"$help\" in *-training-dir*) return 0 ;; *) return 1 ;; esac", "return 0")')" \
	"judged able to log"

run_case "typed-mode: a plan creates the training directory" fail \
	'./scripts/typed-mode.sh' \
	"$(py 'edit("up.sh", "    TYPRYX_ENV+=(\"TYPRYX_TRAINING_DIR=$TYPED_TRAINING_DIR\")", "    TYPRYX_ENV+=(\"TYPRYX_TRAINING_DIR=$TYPED_TRAINING_DIR\")\n    typed_make_training_dir \"$TYPED_TRAINING_DIR\"")')" \
	"a refusal or a plan created"

echo
echo "=== and what they must NOT catch ==="

# The three shapes the first version of this gate got wrong, and reported five
# failures over on a tree that was correct: an empty assignment filled in
# later, a value that is a reference rather than a literal, and an address
# inside prose. A gate that flags any of these is deleted by whoever hits it.
run_case "loopback-only: a placeholder, a reference and an address in prose" pass \
	'./scripts/loopback-only.sh' \
	"$(py 'edit("up.sh", "WARDRYX_URL=\"\"", "WARDRYX_URL=\"\"\nSPARE_URL=\"\"\nMIRROR_URL=\"$WARDRYX_URL\"\n# see https://example.com/docs for why this is loopback only")')"

run_case "revoke-key-not-printed: only the path is named, not the content" pass \
	'./scripts/revoke-key-not-printed.sh' \
	"$(py 'edit("up.sh", "log \"vouchryx: minting a revocation key\"", "log \"vouchryx: minting a revocation key\"\n    log \"vouchryx: revocation key at $DELEG_DIR/revoke.key\"")')"

# An unrelated variable added to the same backslash-continued block must not
# make the gate stop finding TOKENFUSE_CACHE="off" in it.
run_case "gateway-cache-is-off: an unrelated var added to the block" pass \
	'./scripts/gateway-cache-is-off.sh' \
	"$(py 'edit("up.sh", "TOKENFUSE_CLOUD_KEY=\"devkey\" \\\n", "TOKENFUSE_CLOUD_KEY=\"devkey\" \\\nTOKENFUSE_SPARE=\"1\" \\\n")')"

# THE FIX FOR THE SAME BINARY'S OTHER SUBCOMMAND. `$GATEWAY_BIN mcp-broker`
# fronts typryx under --with-typed and sets neither TOKENFUSE_UPSTREAM,
# TOKENFUSE_ALLOW_STUB, nor TOKENFUSE_CACHE, because none of the three applies
# to it. Both gates must keep excluding it even when a SECOND such start
# appears elsewhere in up.sh, with an unrelated variable of its own, so the
# exclusion is proven to be about the subcommand rather than one hardcoded
# line.
run_case "gateway-decides-its-upstream: a second mcp-broker start is not mistaken for a gateway start" pass \
	'./scripts/gateway-decides-its-upstream.sh' \
	"$(py 'edit("up.sh", "\n  register tokenfuse-mcp-broker \"$!\" TERM\n", "\n  register tokenfuse-mcp-broker \"$!\" TERM\n  TOKENFUSE_MCP_ADDR=\"127.0.0.1:9999\" \\\n    \"$GATEWAY_BIN\" mcp-broker > /dev/null 2>&1 &\n")')"

run_case "gateway-cache-is-off: a second mcp-broker start is not mistaken for a gateway start" pass \
	'./scripts/gateway-cache-is-off.sh' \
	"$(py 'edit("up.sh", "\n  register tokenfuse-mcp-broker \"$!\" TERM\n", "\n  register tokenfuse-mcp-broker \"$!\" TERM\n  TOKENFUSE_MCP_ADDR=\"127.0.0.1:9999\" \\\n    \"$GATEWAY_BIN\" mcp-broker > /dev/null 2>&1 &\n")')"

# The broker is the same binary on a subcommand and never serves the route, so a
# second such start, with a variable of its own, must not be judged a gateway.
run_case "declassify-is-keyed: a second mcp-broker start is not mistaken for a gateway start" pass \
	'./scripts/declassify-is-keyed.sh' \
	"$(py 'edit("up.sh", "\n  register tokenfuse-mcp-broker \"$!\" TERM\n", "\n  register tokenfuse-mcp-broker \"$!\" TERM\n  TOKENFUSE_MCP_ADDR=\"127.0.0.1:9999\" \\\n    \"$GATEWAY_BIN\" mcp-broker > /dev/null 2>&1 &\n")')"

# An unrelated variable added to the same continued block must not hide the key.
run_case "declassify-is-keyed: an unrelated var added to the block" pass \
	'./scripts/declassify-is-keyed.sh' \
	"$(py 'edit("up.sh", "TOKENFUSE_CLOUD_KEY=\"devkey\" \\\n", "TOKENFUSE_CLOUD_KEY=\"devkey\" \\\nTOKENFUSE_SPARE=\"1\" \\\n")')"

# A reworded comment beside the mint is not a change to the key.
run_case "declassify-is-keyed: the comment above the mint is reworded" pass \
	'./scripts/declassify-is-keyed.sh' \
	"$(py 'edit("up.sh", "The refusal below is load-bearing, not tidiness", "The refusal below is load-bearing, not mere tidiness")')"

# AND THE FIX MUST NOT BECOME A NEW HOLE. If the exclusion matched on ANYTHING
# mentioning "mcp-broker" rather than on the subcommand position right after
# the binary, a real gateway start missing its precondition, with an unrelated
# trailing comment that happens to say the same word, would be excused by it.
run_case "gateway-decides-its-upstream: a stray mention of mcp-broker does not excuse a real gateway start" fail \
	'./scripts/gateway-decides-its-upstream.sh' \
	"$(py 'edit("up.sh", "TOKENFUSE_ALLOW_STUB=\"1\" \\\n  TOKENFUSE_MODE=\"enforce\" \\\n  TOKENFUSE_CACHE=\"off\" \\\n  TOKENFUSE_EVENTS_PATH=\"$EVENTS_FILE\" \\\n  TOKENFUSE_DATA_DIR=\"$STACK_UP_HOME/traces/gateway\" \\\n  TOKENFUSE_CLOUD_URL=\"http://127.0.0.1:$CLOUD_PORT\" \\\n  TOKENFUSE_CLOUD_KEY=\"devkey\" \\\n    \"$GATEWAY_BIN\" > \"$LOGS_DIR/gateway.log\" 2>&1 &\nfi", "TOKENFUSE_MODE=\"enforce\" \\\n  TOKENFUSE_CACHE=\"off\" \\\n  TOKENFUSE_EVENTS_PATH=\"$EVENTS_FILE\" \\\n  TOKENFUSE_DATA_DIR=\"$STACK_UP_HOME/traces/gateway\" \\\n  TOKENFUSE_CLOUD_URL=\"http://127.0.0.1:$CLOUD_PORT\" \\\n  TOKENFUSE_CLOUD_KEY=\"devkey\" \\\n    \"$GATEWAY_BIN\" > \"$LOGS_DIR/gateway.log\" 2>&1 &  # not mcp-broker\nfi")')" \
	"neither TOKENFUSE_UPSTREAM nor TOKENFUSE_ALLOW_STUB"

# up.sh reads the domain from the environment and routines.sh from a file.
# Both are correct and they LOOK different; a gate comparing the raw lines
# rather than the defaults would fire on a tree that is right.
run_case "one-trust-domain: two spellings of the same default" pass \
	'./scripts/one-trust-domain.sh' \
	"$(py 'edit("routines.sh", "DEMO_TRUST_DOMAIN=\"demo.local\"", "DEMO_TRUST_DOMAIN=\"demo.local\"   # read from the file below")')"

# The key file's PATH is fine to name: the plan and the launch log do, on
# purpose, so an operator can see which file was used. Only its bytes are not.
run_case "typed-mode: a log line names the key file's path, not its content" pass \
	'./scripts/typed-mode.sh' \
	"$(py 'edit("up.sh", "log \"typryx data: $TYPED_LEAVES\"", "log \"typryx data: $TYPED_LEAVES\"\n  log \"typryx key file: ${TYPED_KEY_FILE:-none}\"")')"

# Rewording the launch's own confirmation line is not a fault: the gate judges
# what is set and whether it is private, not the sentence announcing it.
run_case "typed-mode: the training log's launch line is reworded" pass \
	'./scripts/typed-mode.sh' \
	"$(py 'edit("up.sh", "(0700, this machine only; no backend answers in it)", "(private, local)")')"

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

run_case "gateway-cache-is-off: no up.sh left to read" fail \
	'./scripts/gateway-cache-is-off.sh' \
	"$(py 'import subprocess, os
assert os.path.exists("up.sh"), "expected up.sh"
subprocess.run(["git", "mv", "up.sh", "up.bash"], check=True)')" \
	"measured nothing"

run_case "declassify-is-keyed: no up.sh left to read" fail \
	'./scripts/declassify-is-keyed.sh' \
	"$(py 'import subprocess, os
assert os.path.exists("up.sh"), "expected up.sh"
subprocess.run(["git", "mv", "up.sh", "up.bash"], check=True)')" \
	"measured nothing"

# The gateway start renamed out from under the gate: its launch lines are how
# it finds its subjects, and it must say it found none rather than report OK.
run_case "declassify-is-keyed: no gateway start left to judge" fail \
	'./scripts/declassify-is-keyed.sh' \
	"$(py 's = open("up.sh").read()
t = s.replace("\"$GATEWAY_BIN\" > \"$LOGS_DIR/gateway.log\" 2>&1 &", "gateway_launcher > \"$LOGS_DIR/gateway.log\" 2>&1 &")
assert t != s
open("up.sh", "w").write(t)')" \
	"nowhere, so this measured nothing"

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

run_case "typed-mode: no up.sh left to drive" fail \
	'./scripts/typed-mode.sh' \
	"$(py 'import subprocess, os
assert os.path.exists("up.sh"), "expected up.sh"
subprocess.run(["git", "mv", "up.sh", "up.bash"], check=True)')" \
	"measured nothing"

# The static half reads the launcher for the key file's variable. Rename it
# and the plan still works, so only that half notices it has nothing to read.
run_case "typed-mode: the key file variable is renamed away" fail \
	'./scripts/typed-mode.sh' \
	"$(py 's = open("up.sh").read()
assert "TYPED_KEY_FILE" in s, "variable not present"
open("up.sh", "w").write(s.replace("TYPED_KEY_FILE", "TYPED_KEYF"))')" \
	"measured nothing"

# The two training-log checks run the launcher's OWN functions, cut out of up.sh
# by name. Rename one and the plan still works, so only that half can notice it
# has nothing to run.
run_case "typed-mode: the training directory function is renamed away" fail \
	'./scripts/typed-mode.sh' \
	"$(py 's = open("up.sh").read()
assert "typed_make_training_dir" in s, "function not present"
open("up.sh", "w").write(s.replace("typed_make_training_dir", "typed_mk_trdir"))')" \
	"measured nothing"

run_case "typed-mode: the typryx can-it-log function is renamed away" fail \
	'./scripts/typed-mode.sh' \
	"$(py 's = open("up.sh").read()
assert "typed_bin_has_training" in s, "function not present"
open("up.sh", "w").write(s.replace("typed_bin_has_training", "typed_bin_can_log"))')" \
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
