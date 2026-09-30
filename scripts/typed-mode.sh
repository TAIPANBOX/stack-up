#!/usr/bin/env bash
# Enforces CLAUDE.md invariant 10: the typed-answers data mode is chosen on
# purpose, its refusals happen before anything is built or started, and the
# Jev key's CONTENT is never read or printed by this launcher.
#
# WHY THIS SHAPE
#
# up.sh has no dry run for the stack as a whole (it builds twelve repositories),
# so the data-mode half of it is a function of its arguments alone and has its
# own: `./up.sh --typed-plan ...` resolves the mode, prints what would start and
# what would leave the machine, and exits before anything is built, started or
# written. This script drives that, which means it judges the same code path
# the real launch uses (the plan prints the very array the launch hands to
# `env`), not a copy of it.
#
# WHAT IT CHECKS
#
#   1. Default off: no flags starts nothing; `--with-typed` alone is the stub
#      backend with no environment change at all.
#   2. `jev` without a key file, with a missing one, with an empty one and with
#      a whitespace-only one is refused (exit 2) and names the flag.
#   3. `own-model` without a URL, with a URL that does not end in /v1, with
#      userinfo or a query in it, without a model name, or with an empty key
#      file, is refused.
#   4. A mode that contradicts `--with-typed`, a key file with no mode, and a
#      model URL under `jev` are refused, not silently ignored.
#   5. A good `jev` and a good `own-model` resolve to the right backend, and the
#      plan NEVER contains the key's content, only its path.
#   6. A refusal and a plan leave the state directory untouched.
#   7. Statically: up.sh never reads the key file's bytes. The only touch is a
#      `grep -q` for "not blank", which prints nothing.
#   8. The local training log (`--typed-training`, typryx's TYPRYX_TRAINING_DIR):
#      off by default and absent from every default plan; asking for it without
#      typryx running is refused, not ignored; on, the plan prints the private
#      directory, the ledger beside it and the export command; the directory
#      function makes it 0700 even where it already existed looser; and the
#      check that the typryx binary has a training log at all answers both ways.
#      The last two run the launcher's OWN functions, cut out of up.sh, not a
#      copy of them.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
# It does not start typryx. That the key stays out of the running process's
# arguments and the log is shown by hand in the pull request that added this
# (typryx reads the file itself; the launcher hands it a path in the
# environment). A gate that needs a built typryx and a free port would be
# skipped on the first machine that lacked either, and a skipped gate reads as
# a pass.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

LAUNCHER="up.sh"
[ -f "$LAUNCHER" ] || { echo "typed-mode: no $LAUNCHER, so this measured nothing"; exit 1; }

# Does this launcher know the plan flag at all? An old or renamed launcher
# answers "unknown option", and every check below would then be judging an
# error message. Say so instead of reporting a pass.
probe="$(./"$LAUNCHER" --typed-plan 2>&1; printf 'rc=%s' "$?")"
case "$probe" in
  *"unknown option"*)
    echo "FAIL: $LAUNCHER has no --typed-plan, so the data mode is not measurable and this measured nothing."
    exit 1 ;;
esac

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export STACK_UP_HOME="$work/home"
unset TYPRYX_BACKEND TYPRYX_JEV_URL TYPRYX_JEV_MODEL TYPRYX_JEV_KEY_FILE \
  TYPRYX_OPENAI_URL TYPRYX_OPENAI_MODEL TYPRYX_OPENAI_KEY_FILE

FAKE_KEY="fake-key-0000-not-real-xyzzy"
printf '%s\n' "$FAKE_KEY" > "$work/key"
: > "$work/empty"
printf ' \n\t\n' > "$work/blank"

fails=0
n=0
out=""
rc=0

run() { out="$(./"$LAUNCHER" "$@" 2>&1)"; rc=$?; }

bad() { fails=$((fails + 1)); printf 'FAIL: %s\n' "$1"; printf '%s\n' "$out" | head -6 | sed 's/^/      /'; }

# expect <name> <rc> <needle-or-empty> -- args...
expect() {
  local name="$1" want="$2" needle="$3"; shift 4
  n=$((n + 1))
  run "$@"
  if [ "$rc" -ne "$want" ]; then bad "$name: exit $rc, wanted $want"; return; fi
  if [ -n "$needle" ] && ! printf '%s' "$out" | grep -qF -- "$needle"; then
    bad "$name: output does not say: $needle"; return
  fi
  if printf '%s' "$out" | grep -qF -- "$FAKE_KEY"; then
    bad "$name: the key's CONTENT is in the output"; return
  fi
}

# has / lacks check the output of the last expect.
has() { n=$((n + 1)); printf '%s' "$out" | grep -qF -- "$1" || bad "last plan does not contain: $1"; }
lacks() { n=$((n + 1)); ! printf '%s' "$out" | grep -qF -- "$1" || bad "last plan contains: $1"; }

# Every plan's env lines must have all `-u` before the first NAME=VALUE: `env`
# stops reading options at the first assignment and would run a later `-u` as
# the command. Found by running typryx through the array; the plan alone
# looked right.
env_ordered() {
  n=$((n + 1))
  printf '%s\n' "$out" | awk '/^typed: env: -u /{ if (seen) bad=1; next } /^typed: env: /{ seen=1 } END { exit bad }' \
    || bad "an -u comes after an assignment in the env array, so env would run it as a command"
}

# 1. default off, and --with-typed alone is exactly today's stub.
expect "no flags"               0 "typryx is not started" -- --typed-plan
expect "--typed-mode off"       0 "typryx is not started" -- --typed-mode off --typed-plan
expect "--with-typed alone"     0 "backend: stub"         -- --with-typed --typed-plan
has "env: TYPRYX_BACKEND=stub"
lacks "env: -u"
lacks "jev"
lacks "openai"
env_ordered

# 2. jev
expect "jev, no key file"       2 "--typed-key-file"      -- --typed-mode jev --typed-plan
expect "jev, missing file"      2 "does not exist"        -- --typed-mode jev --typed-key-file "$work/nope" --typed-plan
expect "jev, empty file"        2 "is empty"              -- --typed-mode jev --typed-key-file "$work/empty" --typed-plan
expect "jev, whitespace file"   2 "is empty"              -- --typed-mode jev --typed-key-file "$work/blank" --typed-plan
expect "jev, a directory"       2 "not a readable file"   -- --typed-mode jev --typed-key-file "$work" --typed-plan
expect "jev, with a model URL"  2 "own-model"             -- --typed-mode jev --typed-key-file "$work/key" --typed-model-url http://h/v1 --typed-plan
expect "jev, good"              0 "backend: jev"          -- --typed-mode jev --typed-key-file "$work/key" --typed-plan
has "env: TYPRYX_BACKEND=jev"
has "env: TYPRYX_JEV_KEY_FILE=$work/key"
has "TypeSafe"
# A stale variable in the operator's shell must not be able to redirect the key.
has "env: -u TYPRYX_JEV_URL"
has "env: -u TYPRYX_JEV_MODEL"
lacks "openai-logprobs"
env_ordered

# 3. own-model
expect "own-model, no URL"      2 "--typed-model-url"     -- --typed-mode own-model --typed-model m --typed-plan
expect "own-model, no model"    2 "--typed-model"         -- --typed-mode own-model --typed-model-url http://127.0.0.1:11434/v1 --typed-plan
expect "own-model, URL not /v1" 2 "/v1"                   -- --typed-mode own-model --typed-model-url http://127.0.0.1:11434 --typed-model m --typed-plan
expect "own-model, userinfo"    2 "/v1"                   -- --typed-mode own-model --typed-model-url http://u:p@h:1/v1 --typed-model m --typed-plan
expect "own-model, query"       2 "/v1"                   -- --typed-mode own-model --typed-model-url "http://h:1/v1?k=v" --typed-model m --typed-plan
expect "own-model, not http"    2 "/v1"                   -- --typed-mode own-model --typed-model-url ftp://h/v1 --typed-model m --typed-plan
expect "own-model, empty key"   2 "is empty"              -- --typed-mode own-model --typed-model-url http://h:1/v1 --typed-model m --typed-key-file "$work/empty" --typed-plan
expect "own-model, good"        0 "backend: openai-logprobs" -- --typed-mode own-model --typed-model-url http://127.0.0.1:11434/v1 --typed-model qwen2.5:7b --typed-plan
has "env: TYPRYX_BACKEND=openai-logprobs"
has "env: TYPRYX_OPENAI_URL=http://127.0.0.1:11434/v1"
has "env: TYPRYX_OPENAI_MODEL=qwen2.5:7b"
has "env: -u TYPRYX_OPENAI_KEY_FILE"
lacks "TYPRYX_JEV_KEY_FILE="
has "env: -u TYPRYX_JEV_KEY_FILE"
env_ordered
expect "own-model, with key"    0 "backend: openai-logprobs" -- --typed-mode own-model --typed-model-url https://gpu.internal:8000/v1/ --typed-model m --typed-key-file "$work/key" --typed-plan
has "env: TYPRYX_OPENAI_KEY_FILE=$work/key"
lacks "env: -u TYPRYX_OPENAI_KEY_FILE"
env_ordered

# 4. contradictions are refused, never silently ignored
expect "off with --with-typed"  2 "contradict"            -- --with-typed --typed-mode off --typed-plan
expect "key file, no mode"      2 "--typed-mode"          -- --typed-key-file "$work/key" --typed-plan
expect "key file under off"     2 "--typed-mode"          -- --typed-mode off --typed-key-file "$work/key" --typed-plan
expect "unknown mode"           2 "jev, own-model or off" -- --typed-mode cloud --typed-plan

# 5 was folded into the has/lacks lines and expect()'s key-content check.

# 8. the local training log: off unless asked for, refused when it has nothing
# to attach to, and private once it exists.
expect "training off: plan with --with-typed"  0 "backend: stub" -- --with-typed --typed-plan
lacks "TYPRYX_TRAINING_DIR"
lacks "training"
expect "training off: own-model plan"          0 "backend: openai-logprobs" -- --typed-mode own-model --typed-model-url http://127.0.0.1:11434/v1 --typed-model m --typed-plan
lacks "TYPRYX_TRAINING_DIR"
lacks "training"
expect "training, no typryx to attach to"      2 "--with-typed" -- --typed-training --typed-plan
expect "training under --typed-mode off"       2 "--typed-training" -- --typed-mode off --typed-training --typed-plan
expect "training, stub"                        0 "training log: on" -- --with-typed --typed-training --typed-plan
has "env: TYPRYX_TRAINING_DIR=$STACK_UP_HOME/typryx/training"
has "training dir: $STACK_UP_HOME/typryx/training"
has "ledger dir: $STACK_UP_HOME/typryx/ledger"
has "typryx export --training --training-dir $STACK_UP_HOME/typryx/training --ledger $STACK_UP_HOME/typryx/ledger"
has "env: TYPRYX_BACKEND=stub"
env_ordered
expect "training, own-model"                   0 "training log: on" -- --typed-mode own-model --typed-model-url http://127.0.0.1:11434/v1 --typed-model qwen2.5:7b --typed-training --typed-plan
has "env: TYPRYX_TRAINING_DIR=$STACK_UP_HOME/typryx/training"
has "env: TYPRYX_OPENAI_URL=http://127.0.0.1:11434/v1"
has "env: -u TYPRYX_JEV_KEY_FILE"
env_ordered
expect "training, jev"                         0 "training log: on" -- --typed-mode jev --typed-key-file "$work/key" --typed-training --typed-plan
has "env: TYPRYX_TRAINING_DIR=$STACK_UP_HOME/typryx/training"
has "no backend answer"
env_ordered

# 6. refusals and plans never touch the state directory
n=$((n + 1))
if [ -e "$STACK_UP_HOME" ]; then
  fails=$((fails + 1)); printf 'FAIL: a refusal or a plan created %s\n' "$STACK_UP_HOME"
fi

# 7. static: the key file's bytes are never read by the launcher.
refs="$(grep -n 'TYPED_KEY_FILE' "$LAUNCHER" || true)"
n=$((n + 1))
if [ -z "$refs" ]; then
  echo "FAIL: $LAUNCHER never mentions TYPED_KEY_FILE, so the static half measured nothing."
  fails=$((fails + 1))
else
  reads="$(printf '%s\n' "$refs" | grep -E 'cat[[:space:]]|\$\(<|<[[:space:]]*"?\$\{?TYPED_KEY_FILE|\bread[[:space:]]|\bhead[[:space:]]|\bsed[[:space:]]|\bawk[[:space:]]' || true)"
  if [ -n "$reads" ]; then
    fails=$((fails + 1))
    printf 'FAIL: %s reads the key file instead of only naming it:\n%s\n' "$LAUNCHER" "$reads"
  fi
  # The one permitted touch is `grep -q`, which prints nothing.
  loud="$(printf '%s\n' "$refs" | grep -E 'grep[[:space:]]' | grep -vE 'grep[[:space:]]+-q' || true)"
  if [ -n "$loud" ]; then
    fails=$((fails + 1))
    printf 'FAIL: %s greps the key file without -q, which would print its content:\n%s\n' "$LAUNCHER" "$loud"
  fi
fi

# 8b. the two functions the launch itself runs for the training log, cut out of
# up.sh by name and run here. A copy would only prove the copy.
fn() { sed -n "/^$1() {/,/^}/p" "$LAUNCHER"; }
# GNU first: on Linux `stat -f` is the FILESYSTEM report and exits 0, so trying the
# BSD form first read a disk summary as a mode (found by CI on ubuntu-latest).
mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1" 2>/dev/null; }

n=$((n + 1))
mk="$(fn typed_make_training_dir)"
if [ -z "$mk" ]; then
  echo "FAIL: $LAUNCHER has no typed_make_training_dir, so the directory's privacy measured nothing."
  fails=$((fails + 1))
else
  eval "$mk"
  fresh="$work/fresh/typryx/training"
  ( typed_make_training_dir "$fresh" ) >/dev/null 2>&1
  if [ ! -d "$fresh" ]; then
    fails=$((fails + 1)); echo "FAIL: typed_make_training_dir did not create $fresh"
  elif [ "$(mode_of "$fresh")" != 700 ]; then
    fails=$((fails + 1)); echo "FAIL: a fresh training directory is $(mode_of "$fresh"), wanted 700"
  fi
  loose="$work/loose"
  mkdir -p "$loose" && chmod 755 "$loose"
  ( typed_make_training_dir "$loose" ) >/dev/null 2>&1
  n=$((n + 1))
  [ "$(mode_of "$loose")" = 700 ] || { fails=$((fails + 1)); echo "FAIL: a training directory that already existed at 755 is $(mode_of "$loose") afterwards, wanted 700"; }
fi

n=$((n + 1))
sup="$(fn typed_bin_has_training)"
if [ -z "$sup" ]; then
  echo "FAIL: $LAUNCHER has no typed_bin_has_training, so whether typryx can log measured nothing."
  fails=$((fails + 1))
else
  eval "$sup"
  printf '#!/bin/sh\necho "  -training-dir string"\nexit 2\n' > "$work/typryx-new"
  printf '#!/bin/sh\necho "typryx: unknown command export"\nexit 2\n' > "$work/typryx-old"
  chmod +x "$work/typryx-new" "$work/typryx-old"
  n=$((n + 1))
  typed_bin_has_training "$work/typryx-new" || { fails=$((fails + 1)); echo "FAIL: a typryx whose export has -training-dir was judged unable to log"; }
  n=$((n + 1))
  ! typed_bin_has_training "$work/typryx-old" || { fails=$((fails + 1)); echo "FAIL: a typryx with no training export was judged able to log, so the flag would be silently ignored"; }
  n=$((n + 1))
  ! typed_bin_has_training "$work/no-such-binary" || { fails=$((fails + 1)); echo "FAIL: a missing binary was judged able to log"; }
fi

if [ "$fails" -gt 0 ]; then
  printf 'FAIL: %d of %d typed-mode check(s) failed.\n' "$fails" "$n"
  exit 1
fi
printf 'OK: %d typed-mode checks: default off, refusals before any side effect, the key file is named never read, and the training log is opt-in and private.\n' "$n"
