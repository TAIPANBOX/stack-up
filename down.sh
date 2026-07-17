#!/usr/bin/env bash
#
# stack-up down: stop a stack that was started with `up.sh` in the background
# (up.sh in the foreground already stops everything on Ctrl-C). Only ever
# signals the PIDs up.sh recorded when it launched each service, never a PID
# discovered by scanning ps/lsof.
#
# Apache-2.0. Part of https://github.com/TAIPANBOX

set -uo pipefail

STACK_UP_HOME="${STACK_UP_HOME:-$HOME/.stack-up}"
PIDS_DIR="$STACK_UP_HOME/pids"

log()  { printf '\033[1;36m[stack-up]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[stack-up]\033[0m %s\n' "$*" >&2; }

shopt -s nullglob
pidfiles=("$PIDS_DIR"/*.pid)
if [ "${#pidfiles[@]}" -eq 0 ]; then
  log "nothing to stop (no recorded processes in $PIDS_DIR)."
  exit 0
fi

# Signal each recorded process with the stop signal up.sh chose for it.
for f in "${pidfiles[@]}"; do
  name="$(basename "$f" .pid)"
  read -r pid sig < "$f" || continue
  [ -n "${pid:-}" ] || continue
  sig="${sig:-TERM}"
  if kill -0 "$pid" 2>/dev/null; then
    log "stopping $name (pid $pid, SIG$sig)"
    kill "-$sig" "$pid" 2>/dev/null
  else
    rm -f "$f"
  fi
done

# Wait, then escalate anything still alive to SIGKILL.
waited=0
while [ "$waited" -lt 10 ]; do
  alive=0
  for f in "${pidfiles[@]}"; do
    [ -f "$f" ] || continue
    read -r pid _ < "$f" || continue
    kill -0 "${pid:-}" 2>/dev/null && alive=1
  done
  [ "$alive" -eq 0 ] && break
  sleep 1; waited=$((waited+1))
done

for f in "${pidfiles[@]}"; do
  [ -f "$f" ] || continue
  name="$(basename "$f" .pid)"
  read -r pid _ < "$f" || continue
  if kill -0 "${pid:-}" 2>/dev/null; then
    warn "$name (pid $pid) ignored the stop signal; sending SIGKILL"
    kill -KILL "$pid" 2>/dev/null
  fi
  rm -f "$f"
done

log "stopped."
