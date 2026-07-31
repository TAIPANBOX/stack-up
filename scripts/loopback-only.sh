#!/usr/bin/env bash
# Enforces invariant 1 of CLAUDE.md: loopback only.
#
# This is the first thing a stranger runs. It is a local demonstration on a
# fixed port map, and the README says plainly that it is NOT a supported
# deployment layout. That sentence is worth exactly as much as the code behind
# it.
#
# The way this gets lost is somebody wanting to reach the dashboard from another
# machine, changing one bind, and shipping a launcher that publishes a money
# plane to whatever network the laptop is on. Nobody is warned, because it works.
#
# WHAT IT LOOKS AT, and this took two attempts. The first version matched lines
# containing a URL and reported five failures, all of them wrong: the install
# hint in a `die` message pointing at rustup.rs, the Apple DTD identifier inside
# a launchd plist, and three `URL=""` defaults that are filled in later. None of
# those is an address this launcher connects to.
#
# So it resolves ASSIGNMENTS and judges their values: an empty value is a
# placeholder, a `$`-reference is not a literal, and a literal address must be
# loopback. Prose and identifiers are not assignments and are left alone. A
# matcher that cannot tell an address from a sentence should not be deciding.
#
# This file is the ONE copy of this check.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

python3 - <<'PY'
import pathlib
import re
import sys

LOOPBACK = re.compile(r"^(127\.0\.0\.1|localhost|\[::1\]|::1)$")
problems = []

# NAME=value, NAME="value", NAME='value' at the start of a line.
ASSIGN = re.compile(r'^\s*(?:export\s+)?([A-Z][A-Z0-9_]*)=(?:"([^"]*)"|\'([^\']*)\'|(\S*))\s*$')

for name in ("up.sh", "down.sh", "routines.sh"):
    p = pathlib.Path(name)
    if not p.exists():
        continue
    for lineno, line in enumerate(p.read_text().splitlines(), 1):
        if line.lstrip().startswith("#"):
            continue

        m = ASSIGN.match(line)
        if m:
            var = m.group(1)
            val = next((g for g in m.groups()[1:] if g is not None), "")
            if not val or "$" in val:
                continue  # a placeholder, or a reference resolved elsewhere
            if var.endswith(("_URL", "_ADDR", "_HOST", "_BIND")) or "BIND" in var:
                host = val
                mu = re.match(r"^https?://([^/:]+)", val)
                if mu:
                    host = mu.group(1)
                else:
                    host = val.split(":")[0]
                if not LOOPBACK.match(host):
                    problems.append(
                        f"{name}:{lineno} {var}={val} is not loopback"
                    )
            continue

        # An address actually being connected to, rather than mentioned.
        for mu in re.finditer(r'(curl|wget|nc)\s[^\n]*?https?://([^/\s"\']+)', line):
            host = mu.group(2).split(":")[0]
            if not LOOPBACK.match(host):
                problems.append(
                    f"{name}:{lineno} reaches {mu.group(2)}, which is not loopback"
                )

        for mu in re.finditer(r'--(?:host|bind|address)[= ]+["\']?([^\s"\']+)', line):
            host = mu.group(1).split(":")[0]
            if "$" in host:
                continue
            if not LOOPBACK.match(host):
                problems.append(f"{name}:{lineno} binds to {mu.group(1)}")

if problems:
    for x in problems:
        print(f"FAIL: {x}")
    print()
    print("This is a local demonstration, and the README says so. A launcher that")
    print("publishes the money plane to whatever network the laptop is on warns")
    print("nobody, because it works. See CLAUDE.md invariant 1.")
    sys.exit(1)

print("OK: every resolved address, bind and connection in the launcher is loopback.")
PY
