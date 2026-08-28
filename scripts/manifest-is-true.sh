#!/usr/bin/env bash
#
# Enforces: components.json says what this launcher actually installs.
#
# WHY A LAUNCHER HAS A MANIFEST AT ALL
#
# Sixteen repositories in this estate declare what they BUILD, and a check in
# each of them proves that declaration against its own toolchain. A launcher
# builds nothing. What it can say, and nothing else can, is what it INSTALLS.
#
# AND THERE IS ALREADY A SECOND OPINION
#
# estate-gates' C5 works the same list out by PARSING this repository from a
# central file: it greps `register <name>` out of up.sh, and equivalents out of
# stack-single's compose.yaml and stack-k8s's manifests, three different
# syntaxes read by one script that lives in neither. That parser is careful and
# it is still somebody else's reading of our source.
#
# So this is the other statement of the same fact, made where the fact lives.
# Two independent readings can catch each other drifting; one cannot.
#
# THE THREE LISTS ARE NOT ONE LIST
#
# A supervised service (`register`), a Python tool installed into a venv
# (`install_py_tool`) and a scheduled routine (ROUTINE_NAMES) are three
# different ways of installing something, and flattening them would lose the
# distinction an operator needs. Each is compared against its own source, both
# ways.
#
# AND IT REFUSES TO REPORT OK ON NOTHING
#
# Every list is checked for being empty first. `register` disappearing from
# up.sh, or the array being renamed, must read as "this measured nothing" and
# not as agreement.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - components.json up.sh routines.sh <<'PY'
import json
import re
import sys

manifest_path, up_path, routines_path = sys.argv[1:4]

manifest = json.load(open(manifest_path))
up = open(up_path).read()
routines = open(routines_path).read()

components = manifest.get("components") or []
if not components:
    print("FAIL: components.json declares no component, so this measured NOTHING.")
    sys.exit(1)
checked = components[0]["checked"]

problems = 0


def compare(label, declared, observed, empty_means):
    """Both ways, and an empty observation is a broken reader rather than news."""
    global problems
    if not observed:
        print(f"FAIL: {empty_means}")
        print("      This check measured NOTHING about that list, which is not the")
        print("      same as the list being empty.")
        problems += 1
        return
    missing = sorted(set(observed) - set(declared))
    extra = sorted(set(declared) - set(observed))
    for name in missing:
        print(f"FAIL: this launcher installs {name!r} ({label}) and components.json does not say so")
        problems += 1
    for name in extra:
        print(f"FAIL: components.json says this launcher installs {name!r} ({label}) and it does not")
        problems += 1


compare(
    "a supervised service",
    checked.get("installs_services", []),
    re.findall(r"^\s*register\s+([a-z][a-z0-9-]*)", up, re.M),
    "no `register <name>` call in up.sh, and that call is how it records a started process",
)

compare(
    "a Python tool",
    checked.get("installs_python_tools", []),
    re.findall(r"^\s*install_py_tool\s+\S+\s+([a-z][a-z0-9-]*)", up, re.M),
    "no `install_py_tool` call in up.sh",
)

names = re.search(r"ROUTINE_NAMES=\(([^)]*)\)", routines)
compare(
    "a scheduled routine",
    checked.get("schedules_routines", []),
    names.group(1).split() if names else [],
    "routines.sh no longer defines ROUTINE_NAMES",
)

defaults = re.search(r"DEFAULT_ROUTINES=\(([^)]*)\)", routines)
compare(
    "a routine that runs by default",
    checked.get("routines_by_default", []),
    defaults.group(1).split() if defaults else [],
    "routines.sh no longer defines DEFAULT_ROUTINES",
)

compare(
    "an opt-in profile",
    checked.get("profiles", []),
    sorted(set(re.findall(r"--with-([a-z]+)", up))),
    "no `--with-<profile>` flag in up.sh",
)

# The narrower list has to BE narrower, or the distinction it draws is decoration.
by_default = set(checked.get("routines_by_default", []))
all_routines = set(checked.get("schedules_routines", []))
if not by_default <= all_routines:
    print(f"FAIL: routines_by_default has {sorted(by_default - all_routines)}, which is not "
          f"among the routines this launcher schedules at all")
    problems += 1

if problems:
    print()
    print(f"{problems} problem(s). components.json and this launcher disagree.")
    sys.exit(1)

print(f"OK: {len(checked.get('installs_services', []))} service(s), "
      f"{len(checked.get('installs_python_tools', []))} Python tool(s), "
      f"{len(checked.get('schedules_routines', []))} routine(s) "
      f"({len(by_default)} by default) and {len(checked.get('profiles', []))} profile(s),")
print("    each compared with up.sh and routines.sh both ways.")
PY
