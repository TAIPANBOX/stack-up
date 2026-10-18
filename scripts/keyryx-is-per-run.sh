#!/usr/bin/env bash
# shellcheck disable=SC2016 # the patterns here are literal text from up.sh, not expansions
# keyryx in this launcher: the custody role and the witness run per run, from
# separate data directories and separate root keys, and wardryx signs its
# approvals through custody. Invariant 23.
#
# WHY
#
# wardryx v2.2.0 signs an approval with a key keyryx holds, but only when it is
# told to (WARDRYX_APPROVAL_SIGNER=keyryx). A launcher that did not say so would
# sign with the HMAC secret it still mints, and nothing would report the
# difference. The witness reads the same event streams from a process of its
# own, so a rewrite made by a plane is seen by something that did not write it.
# Both only mean something if custody and the witness hold different keys and
# different data, and if no root key reaches a terminal, a log or an argv.
#
# WHAT IT HOLDS
#
# 1. keyryx is pinned to a tag and to a 40-hex commit, and the launcher builds
#    that commit.
# 2. The custody start and the witness start take their data directory and their
#    root key file from run variables, and the two data directories differ.
# 3. Each root key is minted with rand_hex above the first custody start, and
#    refused when empty.
# 4. Each key file is written under umask 077 and made 0600 with chmod.
# 5. wardryx starts with WARDRYX_APPROVAL_SIGNER=keyryx, the custody URL and its
#    key file, and without WARDRYX_APPROVAL_SECRET. The launcher checks that the
#    wardryx binary names WARDRYX_APPROVAL_SIGNER before it starts it.
# 6. No key value reaches a log, warn, die or echo line, a printf that is not a
#    file write, or the command line of a keyryx or wardryx process.
# 7. The witness writes its alerts beside its own data, not into the shared bus.
#
# WHAT IT DOES NOT HOLD
#
# That a running custody refuses a consumer it does not know, that the witness
# finds a real rewrite, and that a process keeps its secrets from its own user.
# Those are keyryx's own tests and need built binaries.
#
# It refuses to report OK when it measured nothing: no custody, witness or wardryx
# start in up.sh is "measured nothing", not a pass.

# No pipefail: several checks below are `code | grep -q`, and grep -q exits on its
# first match, so awk takes a SIGPIPE that is not a failure of the check.
set -u
cd "$(dirname "$0")/.." || exit 2

if [ ! -f up.sh ]; then
  echo "keyryx-is-per-run: no up.sh to read: measured nothing"
  exit 1
fi

problems=0
problem() { echo "keyryx-is-per-run: $1"; problems=$((problems + 1)); }

# The launcher's code, one line per logical line: comments dropped, backslash
# continuations joined onto the line that starts them.
code() {
  awk 'BEGIN { buf = "" }
       /^[[:space:]]*#/ { next }
       /\\[[:space:]]*$/ { sub(/\\[[:space:]]*$/, ""); buf = buf $0 " "; next }
       { print buf $0; buf = "" }' up.sh
}

# need <what> <lines> <text>... : some line in <lines> carries every <text>.
need() {
  local what="$1" lines="$2" text
  shift 2
  for text in "$@"; do
    printf '%s\n' "$lines" | grep -qF -- "$text" || problem "$what does not carry $text"
  done
}

custody_lines="$(code | grep -F '"$KEYRYX_BIN" custody' || true)"
witness_lines="$(code | grep -F '"$KEYRYX_BIN" witness' || true)"
wardryx_lines="$(code | grep -F '"$WARDRYX_BIN" serve' || true)"

# 1. The pin.
grep -qE '^KEYRYX_COMMIT="[0-9a-f]{40}"$' up.sh || problem "keyryx is not pinned to a commit (KEYRYX_COMMIT must be a full 40-hex SHA)"
grep -qE '^KEYRYX_TAG="v[0-9]+[.][0-9]+[.][0-9]+"$' up.sh || problem "keyryx is not pinned to a tag (KEYRYX_TAG)"

# 2. The subjects. Zero of any of them is measured nothing.
[ -n "$custody_lines" ] || problem "no keyryx custody start in up.sh: measured nothing"
[ -n "$witness_lines" ] || problem "no keyryx witness start in up.sh: measured nothing"
[ -n "$wardryx_lines" ] || problem "no wardryx start in up.sh: measured nothing"

need "keyryx custody start" "$custody_lines" \
  'KEYRYX_ADDR=' \
  'KEYRYX_DATA="$KEYRYX_CUSTODY_DIR"' \
  'KEYRYX_ROOT_KEY_FILE="$KEYRYX_CUSTODY_ROOT_KEY_PATH"' \
  'KEYRYX_POLICY="$KEYRYX_POLICY_PATH"'

need "keyryx witness start" "$witness_lines" \
  'KEYRYX_WITNESS_DATA="$KEYRYX_WITNESS_DIR"' \
  'KEYRYX_WITNESS_ROOT_KEY_FILE="$KEYRYX_WITNESS_ROOT_KEY_PATH"' \
  'KEYRYX_WITNESS_ALERTS="$KEYRYX_WITNESS_DIR/'

# The two data directories are different values, not one directory named twice.
custody_dir="$(grep -E '^KEYRYX_CUSTODY_DIR=' up.sh | head -1 | cut -d= -f2-)"
witness_dir="$(grep -E '^KEYRYX_WITNESS_DIR=' up.sh | head -1 | cut -d= -f2-)"
if [ -z "$custody_dir" ] || [ -z "$witness_dir" ] || [ "$custody_dir" = "$witness_dir" ]; then
  problem "the custody and the witness share a data directory"
fi

# 3. The root keys are minted per run, before custody starts, and refused when empty.
custody_start_line="$(grep -nF '"$KEYRYX_BIN" custody' up.sh | head -1 | cut -d: -f1)"
for v in KEYRYX_CUSTODY_ROOT_KEY KEYRYX_WITNESS_ROOT_KEY KEYRYX_WARDRYX_KEY; do
  grep -qF "$v=\"\$(rand_hex " up.sh || problem "$v is not minted with rand_hex"
  grep -qF "[ -n \"\$$v\" ]" up.sh || problem "no refusal on an empty $v"
done
mint_line="$(grep -nF 'KEYRYX_CUSTODY_ROOT_KEY="$(rand_hex ' up.sh | head -1 | cut -d: -f1)"
if [ -n "$mint_line" ] && [ -n "$custody_start_line" ] && [ "$mint_line" -gt "$custody_start_line" ]; then
  problem "the custody root key is minted after the custody starts"
fi

# 4. The key files are written under umask 077 and made 0600.
grep -qE '^[[:space:]]*if ! [(] umask 077$' up.sh || problem "the keyryx key files are not written under umask 077"
for p in KEYRYX_CUSTODY_ROOT_KEY_PATH KEYRYX_WITNESS_ROOT_KEY_PATH KEYRYX_WARDRYX_KEY_PATH; do
  grep -qF "chmod 600 \"\$$p\"" up.sh || problem "$p is not made 0600"
done

# 5. wardryx signs through custody, and holds no HMAC secret for it.
need "wardryx start" "$wardryx_lines" \
  'WARDRYX_APPROVAL_SIGNER=keyryx' \
  'WARDRYX_KEYRYX_URL=' \
  'WARDRYX_KEYRYX_CREDENTIAL_FILE="$KEYRYX_WARDRYX_KEY_PATH"'
if printf '%s\n' "$wardryx_lines" | grep -qF 'WARDRYX_APPROVAL_SECRET='; then
  problem "the wardryx start still takes WARDRYX_APPROVAL_SECRET"
fi
code | grep -qF 'bin_reads_setting "$WARDRYX_BIN" WARDRYX_APPROVAL_SIGNER' \
  || problem "the wardryx binary is not checked for WARDRYX_APPROVAL_SIGNER before it starts"

# 6. No key value is logged, printed outside a file write, or put on a command line.
for s in KEYRYX_CUSTODY_ROOT_KEY KEYRYX_WITNESS_ROOT_KEY KEYRYX_WARDRYX_KEY; do
  hits="$(code | grep -E "[$]${s}([^A-Za-z0-9_]|\$)" | grep -vF "[ -n \"\$$s\" ]" || true)"
  [ -z "$hits" ] && continue
  if printf '%s\n' "$hits" | grep -qE '(^|[^A-Za-z0-9_])(log|warn|die|echo)([[:space:]]|$)'; then
    problem "$s reaches a log, warn, die or echo line"
  fi
  if printf '%s\n' "$hits" | grep -E 'printf' | grep -qvF '> "'; then
    problem "$s is printed outside a file write"
  fi
  if printf '%s\n' "$hits" | grep -qE '"\$KEYRYX_BIN"|"\$WARDRYX_BIN" serve'; then
    problem "$s is on the command line of a keyryx or wardryx process"
  fi
done

if [ "$problems" -ne 0 ]; then
  exit 1
fi
echo "keyryx-is-per-run: custody and witness start from per-run keys and separate data directories, the pin is a commit, and wardryx signs its approvals through keyryx ($(printf '%s\n' "$custody_lines" | grep -c .) custody, $(printf '%s\n' "$witness_lines" | grep -c .) witness, $(printf '%s\n' "$wardryx_lines" | grep -c .) wardryx start)"
