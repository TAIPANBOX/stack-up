#!/usr/bin/env bash
# The Cloud key of this run is held in files and printed nowhere. Enforces
# CLAUDE.md invariant 26 (F-028 of the 2026-10-17 security review).
#
# WHY
#
# The dashboard link used to carry the key in its query string
# (`?base=...&key=$CLOUD_KEY`). A query string is written to the dashboard
# server's access log, to the browser history, and to the Referer of every
# request the page makes. The summary also printed the key on three lines, so
# anything that captured the terminal kept it. tokenfuse's dashboard reads the
# key from the URL fragment first (`#key=`, tokenfuse#469), and a browser never
# sends a fragment to a server, so the link now carries the key there, and the
# key reaches the operator through a 0600 file instead of the terminal.
#
# WHAT IT HOLDS
#
# 1. No URL up.sh builds carries the key in a query string (`?key=` or `&key=`).
# 2. No command up.sh runs to print (log, warn, die, echo, or printf with no file
#    redirect) names the Cloud key, or a variable derived from it. A variable
#    assigned from a value that names $CLOUD_KEY is tainted, and so is a variable
#    assigned from a tainted one. Writing the key to a file is not printing it.
# 3. The link that carries the key carries it after `#key=`.
# 4. Every statement that writes the key, or a tainted value, to a file makes the
#    file under umask 077 and chmod 600 in that same statement, the way the admin
#    key's file is made (invariant 21).
#
# WHAT IT DOES NOT HOLD
#
# That the key is private inside a process. It sits in the environment of the
# cloud and the gateway (/proc/<pid>/environ on Linux, ps eww on macOS), and the
# launcher's own curl calls carry it on their command line while they run. Those
# are stated in invariant 26 and are not something a text gate can see.
#
# AND IT REFUSES TO REPORT OK ON NOTHING
#
# No mint of CLOUD_KEY, fewer than two writes of the key to a file, or no link
# carrying it after #key=: it says it measured nothing and fails.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$ROOT/up.sh"

fail() { printf 'cloud-key-is-not-printed: %s\n' "$*" >&2; exit 1; }
[[ -f "$LAUNCHER" ]] || fail "no up.sh at $LAUNCHER, so this measured nothing"

problems=0
# problem <line|-> <text>: a finding. "-" is for a finding about no one line.
problem() {
  if [ "$1" = "-" ]; then printf 'up.sh: %s\n' "$2" >&2
  else printf 'up.sh:%s: %s\n' "$1" "$2" >&2
  fi
  problems=$(( problems + 1 ))
}

# "FIRST:TEXT" for each logical line: continuations joined, comment lines dropped.
logical="$(awk '
  /^[[:space:]]*#/ { next }
  {
    if (buf == "") first = NR
    line = $0
    if (line ~ /\\$/) { sub(/\\$/, "", line); buf = buf line " "; next }
    print first ":" buf line
    buf = ""
  }' "$LAUNCHER")"

# refs <text> <name>: the text names $NAME or ${NAME} as a whole word.
refs() {
  local pat="[$][{]?${2}[}]?([^A-Za-z0-9_]|\$)"
  grep -qE "$pat" <<<"$1"
}

# writes_file <text>: a redirect to a file, not to a descriptor and not to /dev/null.
writes_file() {
  local t="$1"
  t="${t//>&[0-9]/}"
  t="${t//\/dev\/null/}"
  [[ "$t" == *">"* ]]
}

# split_commands <text>: one command per output line. Splits on && || and ;
# only OUTSIDE quotes, so a ; inside a printf format string does not cut it.
split_commands() {
  local s="$1" out="" q="" c next i=0 n=${#1}
  while [ "$i" -lt "$n" ]; do
    c="${s:$i:1}"
    if [ "$c" = "\\" ] && [ "$q" != "'" ]; then
      # An escaped character (\" or \;) is text, whatever it is.
      out="$out$c${s:$((i + 1)):1}"
      i=$(( i + 2 ))
      continue
    fi
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then q=""; fi
      out="$out$c"
    else
      case "$c" in
        "'"|'"') q="$c"; out="$out$c" ;;
        ';') out="$out"$'\n' ;;
        '&'|'|')
          next="${s:$((i + 1)):1}"
          if [ "$next" = "$c" ]; then out="$out"$'\n'; i=$(( i + 1 )); else out="$out$c"; fi
          ;;
        *) out="$out$c" ;;
      esac
    fi
    i=$(( i + 1 ))
  done
  printf '%s\n' "$out"
}

# assignments <text>: the NAME and VALUE of each leading NAME=VALUE in a command
# line, as "NAME<TAB>VALUE" lines (a prefix such as PORT=1 X="$KEY" env ...).
assignments() {
  local rest="$1" re='^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]*)(.*)$'
  while [[ "$rest" =~ $re ]]; do
    printf '%s\t%s\n' "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    rest="${BASH_REMATCH[4]}"
  done
}

# 1. The mint: without it there is no key to judge.
grep -qE '^[0-9]+:CLOUD_KEY=' <<<"$logical" \
  || fail "up.sh mints no CLOUD_KEY, so this measured nothing"

# 2. Taint: CLOUD_KEY, and every variable assigned from a value that names one.
tainted=" CLOUD_KEY "
changed=1
passes=0
while [ "$changed" -eq 1 ] && [ "$passes" -lt 6 ]; do
  changed=0
  passes=$(( passes + 1 ))
  while IFS= read -r ll; do
    [ -n "$ll" ] || continue
    while IFS=$'\t' read -r name value; do
      [ -n "$name" ] || continue
      [[ "$tainted" == *" $name "* ]] && continue
      for t in $tainted; do
        if refs "$value" "$t"; then
          tainted="$tainted$name "
          changed=1
          break
        fi
      done
    done < <(assignments "${ll#*:}")
  done <<<"$logical"
done

# 3. Nothing printed names a tainted variable. Each command is judged alone, so a
# test that shares a line with a die or a log does not make the test a print.
while IFS= read -r ll; do
  [ -n "$ll" ] || continue
  ln="${ll%%:*}"
  while IFS= read -r cmd; do
    s="${cmd#"${cmd%%[![:space:]]*}"}"
    for kw in 'then ' 'else ' 'do ' '{ ' '( ' '! '; do
      if [[ "$s" == "$kw"* ]]; then
        s="${s#"$kw"}"
        s="${s#"${s%%[![:space:]]*}"}"
      fi
    done
    [[ "$s" =~ ^(log|warn|die|echo|printf)([[:space:]]|$) ]] || continue
    writes_file "$cmd" && continue
    for t in $tainted; do
      if refs "$cmd" "$t"; then
        problem "$ln" "prints \$$t, which holds the Cloud key, to the terminal. The key goes to its 0600 file only."
        break
      fi
    done
  done < <(split_commands "${ll#*:}")
done <<<"$logical"

# 4. No query string carries the key.
while IFS= read -r ll; do
  [ -n "$ll" ] || continue
  problem "${ll%%:*}" "builds a URL with the key in its query string (?key= or &key=). A query string reaches the server's access log, the browser history and the Referer. The key goes after # instead."
done < <(grep -E '[?&][A-Za-z_]*key=' <<<"$logical" || true)

# 5. A link carries the key after #key=, the place the dashboard reads it from.
grep -qE '#key=[$][{]?CLOUD_KEY[}]?([^A-Za-z0-9_]|$)' <<<"$logical" \
  || problem "-" "no link carries the Cloud key after #key=, so the dashboard has nowhere to read it from"

# 6. Every write of the key, or of a value holding it, to a file is made 0600. A
# write is a printf or echo whose redirect goes to a file. A launch line that
# carries the key as an environment prefix and sends its log to a file is not a
# write of the key, and is not judged here.
writes=0
while IFS= read -r ll; do
  [ -n "$ll" ] || continue
  ln="${ll%%:*}"
  text="${ll#*:}"
  while IFS= read -r cmd; do
    s="${cmd#"${cmd%%[![:space:]]*}"}"
    for kw in 'then ' 'else ' 'do ' '{ ' '( ' '! '; do
      if [[ "$s" == "$kw"* ]]; then
        s="${s#"$kw"}"
        s="${s#"${s%%[![:space:]]*}"}"
      fi
    done
    [[ "$s" =~ ^(printf|echo)([[:space:]]|$) ]] || continue
    writes_file "$cmd" || continue
    for t in $tainted; do
      if refs "$cmd" "$t"; then
        writes=$(( writes + 1 ))
        if ! { grep -qE 'umask 077' <<<"$text" && grep -qE 'chmod 600' <<<"$text"; }; then
          problem "$ln" "writes \$$t to a file without umask 077 and chmod 600 in the same statement (invariant 21's rule for key files)."
        fi
        break
      fi
    done
  done < <(split_commands "$text")
done <<<"$logical"
[ "$writes" -ge 2 ] \
  || fail "fewer than two files receive the Cloud key ($writes found; the key file and the dashboard link file), so this measured nothing"

if [ "$problems" -gt 0 ]; then
  fail "$problems problem(s). See CLAUDE.md, invariant 26."
fi

printf 'OK: the Cloud key is in no query string and on no line up.sh prints; %d write(s) of it or of its link to a file are 0600 under umask 077.\n' "$writes"
