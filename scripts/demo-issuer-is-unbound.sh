#!/usr/bin/env bash
# Enforces CLAUDE.md invariant 24: the demo issuer's trusted-issuer line ends in
# `|unbound`, and no other line carries the marker.
#
# WHY THIS SHAPE
#
# vouchryx v0.5.0 and later refuse a subject token with no cnf.jkt unless its
# issuer line ends in `|unbound` (vouchryx internal/config, loadTrusted). The
# demo IdP sends exactly such tokens, so without the marker the README's
# delegation loop fails at its first step, HTTP 400 invalid_grant, and nothing
# in this repository says why. Measured 2026-10-19, see invariant 24.
#
# WHAT IT LOOKS AT
#
# Every non-comment line of up.sh that names the demo issuer's host. There must
# be one, it must assign VOUCHRYX_TRUSTED_ISSUERS, and its quoted value must end
# in `|unbound`. No other non-comment line may carry the marker: it is the
# demo's alone, because an operator's own issuer with no cnf.jkt would be a
# bearer credential.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
# It does not prove vouchryx accepts the line. That is the measured run named in
# invariant 24, and it needs a built vouchryx.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

LAUNCHER="up.sh"
[ -f "$LAUNCHER" ] || { echo "demo-issuer-is-unbound: no $LAUNCHER, so nothing was measured"; exit 1; }

# A non-comment line that names the demo issuer's host.
demo="$(grep -nE '^[[:space:]]*[^#[:space:]].*https://idp\.stack-up\.local' "$LAUNCHER" || true)"
if [ -z "$demo" ]; then
  echo "FAIL: $LAUNCHER names no demo issuer (https://idp.stack-up.local), so nothing was measured."
  echo "      If the demo issuer moved, move this gate with it."
  exit 1
fi

problems=0
count=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  count=$((count + 1))
  lineno="${line%%:*}"
  text="${line#*:}"
  case "$text" in
    *VOUCHRYX_TRUSTED_ISSUERS=*) ;;
    *)
      echo "FAIL: $LAUNCHER:$lineno names the demo issuer but is not its VOUCHRYX_TRUSTED_ISSUERS line"
      problems=$((problems + 1))
      continue
      ;;
  esac
  if ! printf '%s' "$text" | grep -qE 'VOUCHRYX_TRUSTED_ISSUERS="[^"]*\|unbound"'; then
    echo "FAIL: $LAUNCHER:$lineno: the demo issuer's trusted line does not end in |unbound"
    echo "      vouchryx v0.5.0 and later refuse its tokens without the marker (invariant 24)"
    problems=$((problems + 1))
  fi
done <<< "$demo"

# The marker belongs to the demo's line only.
marked="$(grep -nE '^[[:space:]]*[^#[:space:]].*\|unbound' "$LAUNCHER" || true)"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  lineno="${line%%:*}"
  text="${line#*:}"
  if ! printf '%s' "$text" | grep -q 'idp\.stack-up\.local'; then
    echo "FAIL: $LAUNCHER:$lineno carries |unbound on a line that is not the demo issuer's"
    echo "      an operator's own issuer with no cnf.jkt is a bearer credential (invariant 24)"
    problems=$((problems + 1))
  fi
done <<< "$marked"

if [ "$problems" -ne 0 ]; then
  echo "demo-issuer-is-unbound: $problems problem(s) across $count demo line(s)"
  exit 1
fi
echo "OK: the demo issuer's trusted-issuer line ($count) ends in |unbound, and no other line carries the marker."
exit 0
