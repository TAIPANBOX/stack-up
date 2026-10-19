#!/usr/bin/env bash
# Enforces CLAUDE.md invariant 25: the bus directory is made by this user before
# any service writes to it, and nothing in the launcher hands a file in it to
# another owner.
#
# WHY THIS SHAPE
#
# agent-stack-go v2 (event/create.go) creates an event stream only in a
# directory its own uid owns, and makes the file 0640. Every writer this
# launcher starts runs as the operator, so the bus directory has to stay the
# operator's. A sudo, chown or chgrp on it would make the next writer refuse to
# create its stream, and that refusal shows only in that writer's own log.
#
# WHAT IT LOOKS AT
#
# In up.sh: a `mkdir -p` that makes $EVENTS_DIR must exist and come before the
# first supervised start (a `register` call). In up.sh, routines.sh and down.sh:
# no non-comment line runs sudo, su, doas, chown or chgrp, or an install with -o
# or -g.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
# It does not prove the stream mode is 0640 or that a writer refuses a directory
# it does not own. Those are agent-stack-go's own tests; invariant 25's marker
# names the one run measured here.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

for f in up.sh routines.sh down.sh; do
  [ -f "$f" ] || { echo "bus-is-operator-owned: no $f, so nothing was measured"; exit 1; }
done

mk_line="$(grep -nE '^mkdir -p "\$EVENTS_DIR"' up.sh | head -1 | cut -d: -f1)"
if [ -z "$mk_line" ]; then
  echo "FAIL: up.sh never makes \$EVENTS_DIR with mkdir -p, so nothing was measured."
  exit 1
fi

problems=0

start_line="$(grep -nE '^[[:space:]]*register[[:space:]]' up.sh | head -1 | cut -d: -f1)"
if [ -n "$start_line" ] && [ "$mk_line" -gt "$start_line" ]; then
  echo "FAIL: up.sh makes the bus directory at line $mk_line, after a service starts at line $start_line"
  problems=$((problems + 1))
fi

owners="$(grep -nE '(^|[[:space:];|&(])(sudo|su|doas|chown|chgrp)[[:space:]]|(^|[[:space:];|&(])install[[:space:]]+-[a-zA-Z]*[og]' up.sh routines.sh down.sh \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  echo "FAIL: $line"
  echo "      changes who owns a file the bus depends on; the bus directory stays this user's (invariant 25)"
  problems=$((problems + 1))
done <<< "$owners"

if [ "$problems" -ne 0 ]; then
  echo "bus-is-operator-owned: $problems problem(s)"
  exit 1
fi
echo "OK: up.sh makes the bus directory (line $mk_line) before the first service start (line ${start_line:-none}), and no launcher file changes its owner."
exit 0
