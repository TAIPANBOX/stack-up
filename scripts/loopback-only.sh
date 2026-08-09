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

# A file that is not there is skipped, and until 2026-08-09 skipping ALL of
# them was a pass: this printed "every resolved address, bind and connection in
# the launcher is loopback" and exited 0 on a tree where none of the three
# existed. Renaming them, or moving the launcher into a subdirectory, is
# ordinary housekeeping, and either one turned the check that holds invariant 1
# into a check on nothing while printing a sentence that asserts the opposite.
seen = 0

for name in ("up.sh", "down.sh", "routines.sh"):
    p = pathlib.Path(name)
    if not p.exists():
        continue
    seen += 1
    for lineno, line in enumerate(p.read_text().splitlines(), 1):
        if line.lstrip().startswith("#"):
            continue

        m = ASSIGN.match(line)
        if m:
            var = m.group(1)
            val = next((g for g in m.groups()[1:] if g is not None), "")
            if not val:
                continue  # a placeholder filled in later
            if var.endswith(("_URL", "_ADDR", "_HOST", "_BIND")) or "BIND" in var:
                # A `$` in the VALUE is not a reason to skip: every real URL in
                # this launcher is `http://127.0.0.1:$SOMETHING_PORT`, so
                # skipping on that judged exactly zero assignments and the
                # branch was decorative. Measured 2026-08-09: two address-shaped
                # assignments, both skipped, none judged. Changing 127.0.0.1 to
                # 0.0.0.0 on either line passed cleanly.
                #
                # What genuinely cannot be judged is a `$` in the HOST, so that
                # is what is skipped now, and only that.
                hosts = re.findall(r"https?://([^/:\s\"']+)", val)
                if not hosts:
                    hosts = [val.split(":")[0]]
                for host in hosts:
                    if "$" in host:
                        continue  # the host itself is resolved elsewhere
                    if not LOOPBACK.match(host):
                        problems.append(
                            f"{name}:{lineno} {var}={val} is not loopback ({host})"
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

if seen == 0:
    print("FAIL: none of up.sh, down.sh or routines.sh is here, so this measured nothing.")
    print("      It cannot say every address is loopback if it read no address at all.")
    print("      If the launcher moved or was renamed, this check has to move with it.")
    raise SystemExit(1)

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
