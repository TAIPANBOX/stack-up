#!/usr/bin/env bash
# shellcheck disable=SC2016 # the patterns here are literal text from up.sh, not expansions
# The keyryx witness's findings reach heraldyx, and a console the operator starts, and
# the witness never writes the bus it witnesses. Invariant 32.
#
# WHY
#
# The witness reads every stream on the bus and notices when one was rewritten, cut
# short or restarted after it was seen. If it wrote the bus, a witness gone wrong could
# add lines to the record it vouches for. So its findings are a file of their own,
# keyryx.ndjson, in a directory of their own, and heraldyx reads that file beside the
# bus. Until this, the file sat in the witness's data directory, beside its keys and its
# log, and nothing read it.
#
# WHAT IT HOLDS (over up.sh's code, comments dropped, continuations joined)
#
# 1. KEYRYX_ALERTS_DIR is a directory under $KEYRYX_DIR that is neither the bus
#    ($EVENTS_DIR) nor the witness's or custody's data directory, and
#    KEYRYX_ALERTS_FILE is keyryx.ndjson in it (the stem heraldyx reads as keyryx).
# 2. The directory is made before the witness starts.
# 3. The witness start reads the bus (KEYRYX_WITNESS_EVENTS="$EVENTS_DIR") and writes
#    its findings to KEYRYX_WITNESS_ALERTS="$KEYRYX_ALERTS_FILE".
# 4. The heraldyx start reads the bus and the findings file: HERALDYX_EVENTS names
#    "$EVENTS_DIR" and "$KEYRYX_ALERTS_FILE" as two of its comma separated entries.
# 5. The closing summary names GENARYX_EVENTS_EXTRA with the file, for a console the
#    operator starts by hand (this launcher starts none).
# 6. Nothing else names the file: no line of up.sh, routines.sh or down.sh but the
#    assignment, the two starts and the summary, so no other process is pointed at it
#    and nothing redirects into it or removes it.
#
# WHAT IT DOES NOT HOLD
#
# That a running witness writes a finding there and heraldyx mails it: that needs
# built binaries. And read-only access is by process here, not by uid: the launcher
# runs as one OS user (invariant 23 names the same limit).
#
# It refuses to report OK when it measured nothing: no up.sh, no witness start or no
# heraldyx start is "measured nothing", not a pass.
#
# No pipefail: several checks below are `code | grep -q`, and grep -q exits on its
# first match, so awk takes a SIGPIPE that is not a failure of the check.
set -u
cd "$(dirname "$0")/.." || exit 2
if [ ! -f up.sh ]; then
  echo "keyryx-alerts: no up.sh to read: measured nothing"
  exit 1
fi
problems=0
problem() { echo "keyryx-alerts: $1"; problems=$((problems + 1)); }

code() {
  awk 'BEGIN { buf = "" }
       /^[[:space:]]*#/ { next }
       /\\[[:space:]]*$/ { sub(/\\[[:space:]]*$/, ""); buf = buf $0 " "; next }
       { print buf $0; buf = "" }' "$1"
}

witness_lines="$(code up.sh | grep -F '"$KEYRYX_BIN" witness' || true)"
heraldyx_lines="$(code up.sh | grep -F '"$HERALDYX_BIN"' || true)"
[ -n "$witness_lines" ] || problem "no keyryx witness start in up.sh: measured nothing"
[ -n "$heraldyx_lines" ] || problem "no heraldyx start in up.sh: measured nothing"
if [ -z "$witness_lines" ] || [ -z "$heraldyx_lines" ]; then
  echo "keyryx-alerts: $problems problem(s); see CLAUDE.md invariant 32"
  exit 1
fi

# 1. Where the findings live.
dir_value="$(grep -E '^KEYRYX_ALERTS_DIR=' up.sh | head -1 | cut -d= -f2-)"
file_value="$(grep -E '^KEYRYX_ALERTS_FILE=' up.sh | head -1 | cut -d= -f2-)"
case "$dir_value" in
  '"$KEYRYX_DIR/'*'"') ;;
  '') problem "up.sh assigns no KEYRYX_ALERTS_DIR" ;;
  *) problem "KEYRYX_ALERTS_DIR is $dir_value, not a directory of its own under \$KEYRYX_DIR" ;;
esac
for other in EVENTS_DIR KEYRYX_WITNESS_DIR KEYRYX_CUSTODY_DIR; do
  ov="$(grep -E "^$other=" up.sh | head -1 | cut -d= -f2-)"
  if [ "$dir_value" = "\"\$$other\"" ] || { [ -n "$ov" ] && [ "$dir_value" = "$ov" ]; }; then
    case "$other" in
      EVENTS_DIR) problem "the witness's findings directory is the bus it witnesses (\$EVENTS_DIR)" ;;
      *) problem "the witness's findings directory is a data directory (\$$other), which holds keys no reader may see" ;;
    esac
  fi
done
[ "$file_value" = '"$KEYRYX_ALERTS_DIR/keyryx.ndjson"' ] \
  || problem "KEYRYX_ALERTS_FILE is ${file_value:-unset}, not \"\$KEYRYX_ALERTS_DIR/keyryx.ndjson\" (the stem heraldyx reads as keyryx)"

# 2. The directory exists before the witness starts.
mk_line="$(grep -nE '^[[:space:]]*mkdir -p .*"\$KEYRYX_ALERTS_DIR"' up.sh | head -1 | cut -d: -f1)"
start_line="$(grep -nF '"$KEYRYX_BIN" witness' up.sh | head -1 | cut -d: -f1)"
if [ -z "$mk_line" ]; then
  problem "up.sh never makes \$KEYRYX_ALERTS_DIR, so the witness has nowhere it owns to write its findings"
elif [ "$mk_line" -gt "$start_line" ]; then
  problem "\$KEYRYX_ALERTS_DIR is made after the witness starts"
fi

# 3. The witness reads the bus and writes its findings there.
printf '%s\n' "$witness_lines" | grep -qF 'KEYRYX_WITNESS_EVENTS="$EVENTS_DIR"' \
  || problem "the witness start does not read the bus (KEYRYX_WITNESS_EVENTS=\"\$EVENTS_DIR\")"
printf '%s\n' "$witness_lines" | grep -qF 'KEYRYX_WITNESS_ALERTS="$KEYRYX_ALERTS_FILE"' \
  || problem "the witness start does not write its findings to KEYRYX_WITNESS_ALERTS=\"\$KEYRYX_ALERTS_FILE\""

# 4. heraldyx reads both.
hv="$(printf '%s\n' "$heraldyx_lines" | grep -oE 'HERALDYX_EVENTS="[^"]*"' | head -1 | sed -e 's/^HERALDYX_EVENTS="//' -e 's/"$//')"
has_entry() { printf '%s\n' "$hv" | tr ',' '\n' | grep -qxF -- "$1"; }
has_entry '$EVENTS_DIR' || problem "heraldyx does not read the bus (HERALDYX_EVENTS is \"$hv\")"
has_entry '$KEYRYX_ALERTS_FILE' || problem "heraldyx does not read the witness's findings (HERALDYX_EVENTS is \"$hv\")"

# 5. A console started by hand is told where they are.
code up.sh | grep -F 'GENARYX_EVENTS_EXTRA' | grep -qF '$KEYRYX_ALERTS_FILE' \
  || problem "the summary does not tell a console GENARYX_EVENTS_EXTRA=\$KEYRYX_ALERTS_FILE"

# 6. Nothing else names the file.
for f in up.sh routines.sh down.sh; do
  [ -f "$f" ] || continue
  code "$f" | grep -nE '[$][{]?KEYRYX_ALERTS_(FILE|DIR)\b' | while IFS= read -r hit; do
    line="${hit#*:}"
    case "$line" in
      KEYRYX_ALERTS_FILE=*) continue ;;
      *'"$KEYRYX_BIN" witness'*) continue ;;
      *'"$HERALDYX_BIN"'*) continue ;;
      *'mkdir -p '*'"$KEYRYX_ALERTS_DIR"'*|*'chmod 700 '*'"$KEYRYX_ALERTS_DIR"'*) continue ;;
      *'log "witness: its findings are $KEYRYX_ALERTS_FILE'*|*"printf '  GENARYX_EVENTS_EXTRA=%s"*) continue ;;
    esac
    echo "keyryx-alerts: $f names the witness's findings outside the witness, heraldyx and the summary: $line"
  done
done | tee /dev/stderr | grep -q . && problems=$((problems + 1))

if [ "$problems" -gt 0 ]; then
  echo "keyryx-alerts: $problems problem(s); see CLAUDE.md invariant 32"
  exit 1
fi
echo "OK: the witness writes its findings to \$KEYRYX_ALERTS_FILE (keyryx.ndjson, off the bus and outside its data); heraldyx reads it beside the bus; the summary names it for a console; nothing else names it."
