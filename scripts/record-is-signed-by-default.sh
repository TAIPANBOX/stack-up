#!/usr/bin/env bash
# shellcheck disable=SC2016 # the patterns here are literal text from up.sh and routines.sh, not expansions
# The record is signed through keyryx by default, and the opt-out says what it leaves. Invariant 30.
#
# WHY
#
# A sealed record that nothing signs proves only that this launcher said so. keyryx
# custody signs each sealed root under a key it holds (trailryx's signer,
# TRAILRYX_SIGNER=keyryx), and the witness reads the record from a process of its own.
# Both are the default. The one flag that turns them off is --without-keyryx, and it
# must say that the record pack is then unsigned, because a reader of the pack cannot
# tell an unsigned pack from a signed one by looking at it.
#
# WHAT IT HOLDS
#
# 1. keyryx is on by default: WITHOUT_KEYRYX=0, WANT_KEYRYX=1, and --without-keyryx
#    is the flag that sets WITHOUT_KEYRYX=1 and so switches WANT_KEYRYX off.
# 2. Custody starts only inside the WANT_KEYRYX block, and the witness reads the seal's
#    records: KEYRYX_WITNESS_RECORDS names the tenant the seal writes and its directory.
# 3. Every trailryx-node call goes through one function, seal_node (up.sh) or
#    trailryx_node (routines.sh). When signing, the call carries TRAILRYX_SIGNER=keyryx,
#    custody's URL, the record-seal credential file and the witness attestations folder;
#    when not, it runs with those variables removed. Nothing calls the node binary bare.
#    Every seal call names the tenant the witness reads.
# 4. The policy declares trailryx-root as an ES384 key and names record-seal as the one
#    consumer granted sign on it, by the SHA-256 of the credential file, which is minted
#    once and kept.
# 5. The closing output and the launch plan say what the record is. Under the opt-out it
#    says the record pack is unsigned and that the opt-out is the weaker setting.
# 6. The scheduled seal (routines.sh) signs the same way, from the state up.sh writes.
#
# WHAT IT DOES NOT HOLD
#
# That custody signs under trailryx-root for a real trailryx seal, that the witness
# attests a real root. The pin the signer needs (TRAILRYX_KEYRYX_KID) is checked by
# scripts/record-key-is-pinned.sh, not here. Those need built binaries.
#
# It refuses to report OK when it measured nothing: no up.sh, no routines.sh, no seal_node
# or trailryx_node function, and no trailryx-node call to judge, is "measured nothing".

set -u
cd "$(dirname "$0")/.." || exit 2

if [ ! -f up.sh ] || [ ! -f routines.sh ]; then
  echo "record-is-signed-by-default: no up.sh or routines.sh to read: measured nothing"
  exit 1
fi

problems=0
problem() { echo "record-is-signed-by-default: $1"; problems=$((problems + 1)); }

# The launcher's code, one line per logical line: comments dropped, backslash
# continuations joined onto the line that starts them.
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

# 1. keyryx is on by default, and the flag is the only way off.
grep -qE '^WITHOUT_KEYRYX=0$' up.sh || problem "--without-keyryx is not off by default (WITHOUT_KEYRYX=0 is not set)"
grep -qE -- '--without-keyryx\) WITHOUT_KEYRYX=1 ;;' up.sh || problem "--without-keyryx is not a flag that sets WITHOUT_KEYRYX=1"
grep -qE '^WANT_KEYRYX=1$' up.sh || problem "keyryx is not on by default (WANT_KEYRYX=1 is not set)"
grep -qE '\[ "\$WITHOUT_KEYRYX" -eq 1 \] && WANT_KEYRYX=0' up.sh || problem "--without-keyryx does not switch WANT_KEYRYX off"

# 2. custody starts inside the WANT_KEYRYX block, and the witness reads the seal's records.
# The start block is the one that follows the KEYRYX_SIGNING reset (the build above it is
# under WANT_KEYRYX too, and is not the block that starts custody).
state_at="$(grep -n -E '^KEYRYX_SIGNING=0$' up.sh | head -1 | cut -d: -f1)"
block_at=""
if [ -n "$state_at" ] && sed -n "$((state_at + 1))p" up.sh | grep -qE '^if \[ "\$WANT_KEYRYX" -eq 1 \]; then$'; then
  block_at=$((state_at + 1))
fi
custody_at="$(grep -n -F '"$KEYRYX_BIN" custody' up.sh | head -1 | cut -d: -f1)"
if [ -z "$block_at" ]; then
  problem "the keyryx block does not start under WANT_KEYRYX"
elif [ -z "$custody_at" ] || [ "$custody_at" -lt "$block_at" ]; then
  problem "custody does not start inside the WANT_KEYRYX block"
fi
grep -qE '^RECORDS_TENANT="acme"$' up.sh || problem "RECORDS_TENANT is not set to the tenant the seal writes"
witness_lines="$(code up.sh | grep -F '"$KEYRYX_BIN" witness' || true)"
if [ -z "$witness_lines" ]; then
  problem "no keyryx witness start in up.sh: measured nothing"
elif ! printf '%s\n' "$witness_lines" | grep -qF 'KEYRYX_WITNESS_RECORDS="$RECORDS_TENANT|$RECORDS_DIR"'; then
  problem "the witness start does not read the seal's records (KEYRYX_WITNESS_RECORDS=\"\$RECORDS_TENANT|\$RECORDS_DIR\")"
fi

# 3. one function carries every trailryx-node call, with the signer when signing.
seal_body="$(fn_code up.sh seal_node)"
if [ -z "$seal_body" ]; then
  problem "up.sh defines no seal_node: measured nothing"
else
  printf '%s\n' "$seal_body" | grep -qF 'if [ "$KEYRYX_SIGNING" -eq 1 ]; then' || problem "seal_node does not branch on KEYRYX_SIGNING"
  for want in 'TRAILRYX_SIGNER=keyryx' 'TRAILRYX_KEYRYX_URL="http://127.0.0.1:$KEYRYX_PORT"' \
              'TRAILRYX_KEYRYX_CREDENTIAL_FILE="$KEYRYX_TRAILRYX_KEY_PATH"' \
              'TRAILRYX_WITNESS_ATTESTATIONS="$KEYRYX_WITNESS_DIR/attestations"'; do
    printf '%s\n' "$seal_body" | grep -qF -- "$want" || problem "seal_node does not set $want when signing"
  done
  env_line="$(printf '%s\n' "$seal_body" | grep -E 'env( -u [A-Z_]+)+' || true)"
  for name in TRAILRYX_SIGNER TRAILRYX_KEYRYX_URL TRAILRYX_KEYRYX_CREDENTIAL_FILE TRAILRYX_WITNESS_ATTESTATIONS; do
    printf '%s\n' "$env_line" | grep -qF -- "-u $name" || problem "seal_node does not remove $name when not signing (env -u $name)"
  done
fi
bare="$(code up.sh | grep -E '"\$NODE_BIN" (events|read)' | grep -v -F 'seal_node' || true)"
[ -z "$bare" ] || problem "a trailryx-node call names the node binary bare, not through seal_node: $(printf '%s' "$bare" | head -1 | sed -E 's/^[[:space:]]+//')"
seal_calls="$(code up.sh | grep -E 'seal_node (events|read)' || true)"
if [ -z "$seal_calls" ]; then
  problem "no seal_node call in up.sh: measured nothing"
elif printf '%s\n' "$seal_calls" | grep -qv -- '--tenant "$RECORDS_TENANT"'; then
  problem "a seal_node call does not name the tenant the witness reads (--tenant \"\$RECORDS_TENANT\")"
fi

# 4. the policy: trailryx-root is ES384, record-seal is the one consumer granted sign on it, minted once.
grep -qF '{"name": "trailryx-root", "alg": "ES384"}' up.sh || problem "the policy does not declare trailryx-root as an ES384 key"
grep -qF '{"name": "record-seal", "auth": {"key_digest": "sha256:$KEYRYX_TRAILRYX_DIGEST"},' up.sh \
  || problem "the policy does not name record-seal by the digest of the credential file"
grep -qF '"grants": {"trailryx-root": ["sign"]}}' up.sh || problem "record-seal is not granted sign on trailryx-root alone"
grep -qE 'KEYRYX_TRAILRYX_DIGEST="\$\(file_sha "\$KEYRYX_TRAILRYX_KEY_PATH"\)"' up.sh || problem "the record-seal digest is not taken from the credential file"
grep -qE '^KEYRYX_TRAILRYX_KEY_PATH="\$KEYRYX_DIR/trailryx.key"$' up.sh || problem "the record-seal credential file is not under \$KEYRYX_DIR/trailryx.key"
grep -qF 'chmod 600 "$KEYRYX_TRAILRYX_KEY_PATH"' up.sh || problem "the record-seal credential file is not made 0600"
grep -qF -- 'rm -rf "$KEYRYX_DIR"' up.sh && problem "up.sh wipes \$KEYRYX_DIR every run, so the root keys are not kept (they are minted once)"
for kp in KEYRYX_CUSTODY_ROOT_KEY_PATH KEYRYX_WITNESS_ROOT_KEY_PATH KEYRYX_TRAILRYX_KEY_PATH; do
  grep -qF "if [ -s \"\$$kp\" ]; then" up.sh || problem "\$$kp is not minted once (no 'if [ -s' guard before the mint)"
done

# 5. the closing output and the launch plan say what the record is.
grep -qF -- '--without-keyryx is the weaker setting: the record pack is unsigned' up.sh \
  || problem "the closing output does not say, under --without-keyryx, that the record pack is unsigned and the setting is the weaker one"
grep -qF 'the record pack is unsigned' up.sh || problem "the closing output does not say the record pack is unsigned when keyryx did not come up"
grep -qF 'launch: record signing:' up.sh || problem "the launch plan does not name the record signing mode"

# 6. the scheduled seal signs the same way, from the state up.sh writes.
rnode="$(fn_code routines.sh trailryx_node)"
if [ -z "$rnode" ]; then
  problem "routines.sh defines no trailryx_node: measured nothing"
else
  printf '%s\n' "$rnode" | grep -qF 'TRAILRYX_SIGNER=keyryx' || problem "trailryx_node does not set TRAILRYX_SIGNER=keyryx when signing"
  printf '%s\n' "$rnode" | grep -qF 'env -u TRAILRYX_SIGNER' || problem "trailryx_node does not remove TRAILRYX_SIGNER when not signing"
fi
code routines.sh | grep -qF 'record-signing' || problem "routines.sh does not read the record signing state up.sh writes"
rbare="$(code routines.sh | grep -E '"\$node" (events|read)' | grep -v -F 'trailryx_node' || true)"
[ -z "$rbare" ] || problem "routines.sh runs the node binary bare for a seal call, not through trailryx_node"
grep -qF '> "$KEYRYX_DIR/record-signing"' up.sh || problem "up.sh does not write the record signing state routines.sh reads"

if [ "$problems" -ne 0 ]; then
  exit 1
fi
echo "record-is-signed-by-default: keyryx is on by default and --without-keyryx turns it off and says the record is unsigned; every trailryx-node call in up.sh and routines.sh goes through one function that signs when keyryx is on; the witness reads the seal's records; the record-seal credential is minted once"
