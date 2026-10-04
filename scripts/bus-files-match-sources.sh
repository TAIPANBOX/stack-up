#!/usr/bin/env bash
# Every event stream file this launcher configures is a file its readers accept
# as the source its lines claim, and every idryx --load names the source its file
# may carry.
#
# WHY
#
# heraldyx v0.3.0 (heraldyx#85) and idryx v1.1.0 (idryx#91) refuse an event whose
# `source` is not allowed for the FILE it was read from. By default
# `<source>.ndjson` carries `<source>` for the registered sources, and
# `tokenfuse-cloud.ndjson` and `tokenfuse-mcp.ndjson` carry `tokenfuse`; anything
# else is an unknown stream, read only for lines that claim the file's own name,
# and a line claiming another source in it is refused. The cost of a launcher
# naming a file wrongly is silent: the plane writes, the bus fills, and the
# notifier mails nothing about those lines while the identity graph never sees
# them (the counter that says so is on stderr and in a state file nobody reads).
#
# WHAT IT HOLDS
#
# 1. Every stream file up.sh and routines.sh name under $EVENTS_DIR is on the
#    table below. A new writer, or a renamed file, fails here until somebody has
#    looked at what the readers will do with it.
# 2. Every `--load <source>:<path>` this launcher passes to idryx names, as its
#    source, one the file's stem may carry. `--load tokenfuse:$EVENTS_FILE` is
#    tokenfuse.ndjson carrying tokenfuse; `--load tokenfuse:...wardryx.ndjson`
#    would be refused line by line.
#
# THE TABLE IS A COPY, and says so: heraldyx and idryx each carry their own
# (internal/stream/stream.go in the first, internal/ingest/stream/stream.go in the
# second), and nothing holds the three equal. `@claude` 2026-10-04: read from both
# at their v0.3.0 and v1.1.0 tags. If a reader's table changes, this one is stale
# until somebody reads it again. The one thing this gate cannot see is what a
# producer actually writes INTO its file; that is read from each producer's
# source constant in the pull request that wired this, not measured here.
#
# AND IT REFUSES TO REPORT OK ON NOTHING
#
# No up.sh, no routines.sh, or no stream file found in either, and this says it
# measured nothing and fails: a launcher whose streams were renamed out from under
# the pattern would otherwise pass for having none.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

fail() { printf 'bus-files-match-sources: %s\n' "$*" >&2; exit 1; }

for f in up.sh routines.sh; do
  [ -f "$ROOT/$f" ] || fail "no $f at $ROOT/$f, so this measured nothing"
done

python3 - "$ROOT/up.sh" "$ROOT/routines.sh" <<'PY'
import re
import sys

# stem -> sources it may carry. The registered sources are single-source streams
# under stem == source; the two tokenfuse files are the measured exceptions.
SOURCES = ["agent-conform", "console", "costcrew", "engram", "heraldyx", "idryx",
           "mockryx", "qryx", "scopyx", "tokenfuse", "typryx", "vouchryx", "verdryx",
           "wardryx"]
ALLOWED = {s: {s} for s in SOURCES}
ALLOWED["tokenfuse-cloud"] = {"tokenfuse"}
ALLOWED["tokenfuse-mcp"] = {"tokenfuse"}

problems = 0
streams = {}   # stem -> sorted list of "file:line" it is configured at
loads = []     # (file, line, source, stem)


def live(text):
    """(lineno, text) for every line that is not a whole-line comment."""
    for i, line in enumerate(text.splitlines(), 1):
        if re.match(r"^\s*#", line):
            continue
        yield i, line


stream_re = re.compile(r"\$\{?EVENTS_DIR\}?/([A-Za-z0-9][A-Za-z0-9._-]*)\.ndjson")
events_file_re = re.compile(r"^\s*EVENTS_FILE=\"\$EVENTS_DIR/([A-Za-z0-9][A-Za-z0-9._-]*)\.ndjson\"")
load_re = re.compile(r"--load[ =]\"?([A-Za-z0-9._-]+):([^\s\"]+)\"?")

for path in sys.argv[1:]:
    name = path.rsplit("/", 1)[-1]
    text = open(path).read()
    events_file_stem = None
    for _, line in live(text):
        m = events_file_re.match(line)
        if m:
            events_file_stem = m.group(1)
    for i, line in live(text):
        for m in stream_re.finditer(line):
            streams.setdefault(m.group(1), []).append(f"{name}:{i}")
        for m in load_re.finditer(line):
            src, target = m.group(1), m.group(2)
            if "$EVENTS_FILE" in target or "${EVENTS_FILE}" in target:
                stem = events_file_stem
            else:
                mm = stream_re.search(target)
                stem = mm.group(1) if mm else None
            loads.append((name, i, src, stem))

if not streams:
    print("FAIL: no `$EVENTS_DIR/<name>.ndjson` found in up.sh or routines.sh, so this measured NOTHING.")
    print("      That is not the same as the launcher configuring no stream.")
    sys.exit(1)

print(f"{'stream file':<28} {'a reader accepts it as':<24} configured at")
for stem in sorted(streams):
    where = ", ".join(sorted(set(streams[stem]))[:3])
    if stem in ALLOWED:
        print(f"{stem + '.ndjson':<28} {'/'.join(sorted(ALLOWED[stem])):<24} {where}")
    else:
        print(f"{stem + '.ndjson':<28} {'UNKNOWN STREAM':<24} {where}")
        print(f"FAIL: {stem}.ndjson is not a stream heraldyx v0.3.0 and idryx v1.1.0 know. A line in it is read")
        print(f"      only if it claims `{stem}`, and a line claiming any other source is refused. Name the")
        print(f"      file for its source, or declare it (HERALDYX_STREAMS / IDRYX_STREAMS) and add it to this table.")
        problems += 1

for name, i, src, stem in loads:
    if stem is None:
        print(f"FAIL: {name}:{i}: --load {src}:<path> names a path this gate cannot resolve to an events file.")
        problems += 1
    elif stem not in ALLOWED:
        print(f"FAIL: {name}:{i}: --load {src}: reads {stem}.ndjson, which is not a known stream.")
        problems += 1
    elif src not in ALLOWED[stem]:
        print(f"FAIL: {name}:{i}: --load {src}: reads {stem}.ndjson, which may only carry "
              f"{'/'.join(sorted(ALLOWED[stem]))}; idryx would refuse every line.")
        problems += 1

if loads:
    print()
    for name, i, src, stem in loads:
        print(f"--load {src}:{stem}.ndjson  ({name}:{i})")

if problems:
    print()
    print(f"{problems} problem(s). See CLAUDE.md, the bus file names invariant.")
    sys.exit(1)

print()
print(f"OK: {len(streams)} stream file(s) and {len(loads)} --load pair(s), each one a file its readers accept as the source it carries.")
PY
