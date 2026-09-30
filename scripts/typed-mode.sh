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

# 1. default off, and --with-typed alone is exactly today's stub.
expect "no flags"               0 "typryx is not started" -- --typed-plan
expect "--typed-mode off"       0 "typryx is not started" -- --typed-mode off --typed-plan
expect "--with-typed alone"     0 "backend: stub"         -- --with-typed --typed-plan
has "env: TYPRYX_BACKEND=stub"
lacks "env: -u"
lacks "jev"
lacks "openai"

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
expect "own-model, with key"    0 "backend: openai-logprobs" -- --typed-mode own-model --typed-model-url https://gpu.internal:8000/v1/ --typed-model m --typed-key-file "$work/key" --typed-plan
has "env: TYPRYX_OPENAI_KEY_FILE=$work/key"
lacks "env: -u TYPRYX_OPENAI_KEY_FILE"

# 4. contradictions are refused, never silently ignored
expect "off with --with-typed"  2 "contradict"            -- --with-typed --typed-mode off --typed-plan
expect "key file, no mode"      2 "--typed-mode"          -- --typed-key-file "$work/key" --typed-plan
expect "key file under off"     2 "--typed-mode"          -- --typed-mode off --typed-key-file "$work/key" --typed-plan
expect "unknown mode"           2 "jev, own-model or off" -- --typed-mode cloud --typed-plan

# 5 was folded into the has/lacks lines and expect()'s key-content check.

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

if [ "$fails" -gt 0 ]; then
  printf 'FAIL: %d of %d typed-mode check(s) failed.\n' "$fails" "$n"
  exit 1
fi
printf 'OK: %d typed-mode checks: default off, refusals before any side effect, and the key file is named, never read.\n' "$n"
