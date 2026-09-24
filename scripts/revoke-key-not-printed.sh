#!/usr/bin/env bash
# Enforces half of CLAUDE.md invariant 8: the revocation key's CONTENT never
# reaches a log line. The other half (a revocation survives a restart) is not
# enforced by this script; see the invariant's own marker for why.
#
# WHY THIS SHAPE
#
# The key's PATH is fine to print: the bring-up summary names
# $STACK_UP_HOME/delegation/revoke.key on purpose, so an operator can find it.
# It is the BYTES that must never reach a terminal or a log file. A plain grep
# for the word "revoke.key" would flag that summary line as a false positive,
# so this looks specifically for a `cat` of the file's content, which up.sh
# does in exactly one place: the assignment that hands the key straight to
# vouchryx's own environment.
#
# WHAT IT LOOKS AT
#
# Every line matching `cat <path ending in revoke.key>`, in any quoting. Each
# one must be the VOUCHRYX_REVOKE_KEYS assignment; anything else is a read of
# the key's bytes this script cannot account for.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
# It does not prove the key is never logged by some OTHER means (a stray
# `env`, a core dump, a shell trace). It proves the one thing up.sh's own
# source can be checked for: no `log`/`warn`/`echo`/`printf` call in this
# script ever receives the key's content as an argument.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

LAUNCHER="up.sh"
[ -f "$LAUNCHER" ] || { echo "revoke-key-not-printed: no $LAUNCHER, so nothing was measured"; exit 1; }

# "cat", then a path (no space or quote inside it) ending in revoke.key. A
# plain `grep -n revoke.key` would also match the bring-up summary's line
# naming the PATH, which must not be flagged: it never calls `cat`.
reads="$(grep -nE 'cat[[:space:]]+"?[^"[:space:]]*revoke\.key"?' "$LAUNCHER" || true)"

if [ -z "$reads" ]; then
  echo "FAIL: $LAUNCHER never reads revoke.key's content at all, so this measured nothing."
  echo "      If the key is now read a different way (e.g. \"\$(<file)\"), update this gate."
  exit 1
fi

problems=0
count=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  count=$((count + 1))
  lineno="${line%%:*}"
  content="${line#*:}"
  case "$content" in
    *VOUCHRYX_REVOKE_KEYS=*) ;;  # the one legitimate read: straight into vouchryx's own environment
    *)
      printf '%s:%s reads the revocation key outside the VOUCHRYX_REVOKE_KEYS assignment:\n  %s\n' \
        "$LAUNCHER" "$lineno" "$content"
      problems=$((problems + 1))
      ;;
  esac
done <<EOF
$reads
EOF

if [ "$problems" -gt 0 ]; then
  echo "FAIL: $problems read(s) of the revocation key's content are not the one that feeds vouchryx."
  exit 1
fi

printf 'OK: the revocation key content is read once in %s, straight into VOUCHRYX_REVOKE_KEYS (%d line checked).\n' \
  "$LAUNCHER" "$count"
