#!/usr/bin/env bash
# shellcheck disable=SC2016 # the patterns here are literal text from up.sh and routines.sh, not expansions
# The record seal is pinned to the one key custody signs with, and the pin is checked against
# custody's own key set before anything is signed under it. Invariant 31.
#
# WHY
#
# trailryx v1.5.0 refuses to start a seal that signs through keyryx without TRAILRYX_KEYRYX_KID,
# and it signs only under the key that pin names. A launcher that pinned whatever key it found,
# or kept a pin after custody moved to another key, would seal records that nothing signs under
# the key the record claims: every signature refused, or every root queued forever. So the pin is
# read from custody's trailryx-root key set and its active_kid, refused with a reason when they do
# not agree, and changed only by the operator, on purpose.
#
# WHAT IT HOLDS
#
# 1. The pins: trailryx v1.5.0 (the first release that reads TRAILRYX_KEYRYX_KID) and keyryx v0.1.2
#    (attestations 0640, so the record plane can read them) are the pin table's entries, at their
#    tags' commits.
# 2. The launcher reads custody's key set (/v1/jwks/trailryx-root) and its state (/v1/state) once
#    custody answers, and takes the pin only from a P-384 key whose kid is its RFC 7638 thumbprint.
# 3. The refusals name their reasons: no ES384 key; more than one at install time; a pin that is not
#    the active key; the active key missing from the set; a malformed pin on disk.
# 4. The pin is kept in $KEYRYX_DIR/trailryx.kid, written under umask 077 and made 0600, and moved only
#    by --repin-record-key, which the launcher refuses without keyryx.
# 5. seal_node and trailryx_node pass TRAILRYX_KEYRYX_KID when they sign, and remove it when they do not.
# 6. The signing branch is reached only after the pin is taken: KEYRYX_SIGNING is set to 1 after
#    record_key_pin has accepted the key.
# 7. No line that logs, warns, dies or echoes names the key set or the state document.
# 8. The one TODO(trailryx#112) that waited for the release is gone.
#
# WHAT IT DOES NOT HOLD
#
# That custody's active key is the key trailryx v1.5.0 verifies a live signature against, and that a
# rotation leaves the record signing after the operator repins. Those need a running custody and trailryx.
#
# It refuses to report OK when it measured nothing: no up.sh, no routines.sh, no record_key_pin, no
# seal_node and no trailryx_node is "measured nothing", not a pass.

set -u
cd "$(dirname "$0")/.." || exit 2

if [ ! -f up.sh ] || [ ! -f routines.sh ]; then
  echo "record-key-is-pinned: no up.sh or routines.sh to read: measured nothing"
  exit 1
fi

problems=0
problem() { echo "record-key-is-pinned: $1"; problems=$((problems + 1)); }

# The launcher's code, one line per logical line: comments dropped, backslash continuations joined.
code() {
  awk 'BEGIN { buf = "" }
       /^[[:space:]]*#/ { next }
       /\\[[:space:]]*$/ { sub(/\\[[:space:]]*$/, ""); buf = buf $0 " "; next }
       { print buf $0; buf = "" }' "$1"
}

# fn_code <file> <name>: the joined lines of one function, from its definition to its closing brace.
fn_code() {
  code "$1" | awk -v fn="$2" 'index($0, fn "() {") == 1 { p = 1 } p { print } p && /^}/ { exit }'
}

# 1. the pins.
grep -qE '^[[:space:]]+trailryx\)[[:space:]]+echo "v1\.5\.0 cf2439de8dc4b65ebad589e92ae4b9dd6dcac536" ;;' up.sh \
  || problem "the trailryx pin is not v1.5.0 at cf2439de8dc4b65ebad589e92ae4b9dd6dcac536 (the first release that reads TRAILRYX_KEYRYX_KID)"
grep -qE '^[[:space:]]+keyryx\)[[:space:]]+echo "v0\.1\.2 21edb5c6744416cc0705434e9d0dc3489cc0c61e" ;;' up.sh \
  || problem "the keyryx pin is not v0.1.2 at 21edb5c6744416cc0705434e9d0dc3489cc0c61e (attestations 0640)"

# 2 and 3. the pin is taken from custody's key set and active key, and the refusals say why.
pin_fn="$(fn_code up.sh record_key_pin)"
if [ -z "$pin_fn" ]; then
  problem "up.sh defines no record_key_pin: measured nothing"
else
  printf '%s\n' "$pin_fn" | grep -qF '/v1/jwks/trailryx-root' || problem "record_key_pin does not read custody's trailryx-root key set (/v1/jwks/trailryx-root)"
  printf '%s\n' "$pin_fn" | grep -qF '/v1/state' || problem "record_key_pin does not read custody's state (/v1/state), for the active key"
  printf '%s\n' "$pin_fn" | grep -qF 'active_kid' || problem "record_key_pin does not take the active key (active_kid) from custody's state"
  for why in 'holds no ES384 key' 'takes exactly one' 'is not its RFC 7638 thumbprint' \
             'is not the active key' 'is not in custody' 'is not a 43-character thumbprint' \
             'rotate on purpose with --repin-record-key'; do
    grep -qF -- "$why" up.sh || problem "no refusal reason says: $why"
  done
  printf '%s\n' "$pin_fn" | grep -qF 'key.get("kid") != thumbprint(key)' || problem "record_key_pin does not check the kid against its RFC 7638 thumbprint"
  printf '%s\n' "$pin_fn" | grep -qF 'if pinned != active:' || problem "record_key_pin does not check a kept pin against the active key"
  printf '%s\n' "$pin_fn" | grep -qF 'if es384[0] != active:' || problem "record_key_pin does not check the install pin against the active key"
  printf '%s\n' "$pin_fn" | grep -qF 'if active not in es384:' || problem "record_key_pin does not check a repin against the key set"
  printf '%s\n' "$pin_fn" | grep -qF 'chmod 600 "$KEYRYX_RECORD_KID_FILE"' || problem "record_key_pin does not keep the pin file private (chmod 600)"
  printf '%s\n' "$pin_fn" | grep -qF 'umask 077' || problem "record_key_pin does not write the pin under umask 077"
fi
grep -qF '"$KEYRYX_DIR/trailryx.kid"' up.sh || problem "the pin is not kept in \$KEYRYX_DIR/trailryx.kid"

# 4. the rotation is explicit, and it needs keyryx.
grep -qE -- '--repin-record-key\) REPIN_RECORD_KEY=1 ;;' up.sh || problem "--repin-record-key is not a flag that sets REPIN_RECORD_KEY=1"
grep -qF -- '--repin-record-key needs keyryx' up.sh || problem "--repin-record-key is not refused without keyryx"

# 5. the signer and the pin travel together.
seal_body="$(fn_code up.sh seal_node)"
if [ -z "$seal_body" ]; then
  problem "up.sh defines no seal_node: measured nothing"
else
  printf '%s\n' "$seal_body" | grep -qF 'TRAILRYX_KEYRYX_KID="$KEYRYX_RECORD_KID"' \
    || problem "seal_node does not pass the pinned kid (TRAILRYX_KEYRYX_KID=\"\$KEYRYX_RECORD_KID\") when signing"
  printf '%s\n' "$seal_body" | grep -E 'env( -u [A-Z_]+)+' | grep -qF -- '-u TRAILRYX_KEYRYX_KID' \
    || problem "seal_node does not remove TRAILRYX_KEYRYX_KID when not signing"
fi
rnode="$(fn_code routines.sh trailryx_node)"
if [ -z "$rnode" ]; then
  problem "routines.sh defines no trailryx_node: measured nothing"
else
  printf '%s\n' "$rnode" | grep -qF 'TRAILRYX_KEYRYX_KID=' || problem "trailryx_node does not pass the pinned kid when signing"
  printf '%s\n' "$rnode" | grep -qF 'cat "$keyryx_dir/trailryx.kid"' || problem "trailryx_node does not read the pin file (trailryx.kid)"
  printf '%s\n' "$rnode" | grep -E 'env( -u [A-Z_]+)+' | grep -qF -- '-u TRAILRYX_KEYRYX_KID' \
    || problem "trailryx_node does not remove TRAILRYX_KEYRYX_KID when not signing"
fi

# 6. signing is reached only after the pin is accepted.
pin_call="$(code up.sh | grep -n -F 'record_key_pin' | grep -v -F 'record_key_pin()' | head -1 | cut -d: -f1)"
signed_at="$(code up.sh | grep -n -E '^[[:space:]]*KEYRYX_SIGNING=1$' | head -1 | cut -d: -f1)"
if [ -z "$pin_call" ]; then
  problem "record_key_pin is never called, so the record is never pinned: measured nothing"
elif [ -z "$signed_at" ] || [ "$signed_at" -lt "$pin_call" ]; then
  problem "KEYRYX_SIGNING=1 is set before the record's key is pinned"
fi

# 7. the key set and the state never reach a log line.
if code up.sh | grep -E '(^|[^A-Za-z0-9_])(log|warn|die|echo|printf)[[:space:]]' | grep -qE '[$](keyset_json|state_json)'; then
  problem "a log, warn, die, echo or printf line names the key set or the state document"
fi

# 8. the TODO that waited for the release is gone.
grep -qF 'TODO(trailryx#112)' up.sh && problem "TODO(trailryx#112) is still in up.sh: the pin is released now"

if [ "$problems" -ne 0 ]; then
  exit 1
fi
echo "record-key-is-pinned: the record seal is pinned to custody's active trailryx-root key, taken from its key set and state, kept across runs, moved only by --repin-record-key; seal_node and trailryx_node pass the pin with the signer; trailryx v1.5.0 and keyryx v0.1.2 are pinned"
