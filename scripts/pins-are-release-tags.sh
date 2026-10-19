#!/usr/bin/env bash
# shellcheck disable=SC2016 # the patterns here are literal text from up.sh, not expansions
# Every component this launcher builds is checked out at a release tag and at the
# commit that tag names. Invariant 29.
#
# WHY
#
# Until this, the launcher built whatever a sibling checkout held, or whatever main
# a fresh clone had that morning. A branch moves under the launcher without telling
# it, so the binary a stranger ran on one day was not the one anybody reviewed the
# day before. Finding F-016 of the 2026-10-17 security review. A release is a commit
# a maintainer named and tested; the pin is that name, and the clone is refused
# unless it is that commit.
#
# WHAT IT HOLDS
#
# 1. pin_of is the one place a component's tag and commit are written. Every entry
#    is a release tag (vMAJOR.MINOR.PATCH) and a full 40-hex commit, except verdryx,
#    which publishes no release tag and so has an empty entry: it is built only with
#    --from-main, and says so.
# 2. Every component the launcher builds has an entry, and every pinned_repo call
#    that names a component literally names one that has an entry.
# 3. locate_repo, the sibling-or-main lookup, is called from nowhere but pinned_repo.
#    pinned_repo reaches it only under --from-main.
# 4. git clone runs only inside pinned_repo and locate_repo. pinned_repo clones the
#    release tag with --branch, and refuses a checkout whose HEAD is not the pinned
#    commit.
# 5. --from-main is a flag, and its warning says the build is not the pinned release.

set -uo pipefail

problems=0
problem() { printf 'pins-are-release-tags: %s\n' "$1" >&2; problems=$((problems + 1)); }

if [ ! -f up.sh ]; then
  printf 'pins-are-release-tags: measured nothing: up.sh is not here (run from the repository root)\n' >&2
  exit 1
fi

# fn_span <function> -> "start end" line numbers of its definition, or nothing.
fn_span() {
  awk -v fn="$1" 'index($0, fn "() {") == 1 { s = NR } s && NR > s && /^}/ { print s, NR; exit }' up.sh
}

# call_lines <text> -> line numbers where <text> appears outside a comment and
# outside its own definition line.
call_lines() {
  grep -n -F -- "$1" up.sh | grep -v -E '^[0-9]+:[[:space:]]*#' | grep -v -E "^[0-9]+:[A-Za-z_]+\(\) \{" | cut -d: -f1
}

# inside <line> <start> <end> -> 0 when the line number falls in the span.
inside() { [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]; }

pin_span="$(fn_span pin_of)"
if [ -z "$pin_span" ]; then
  printf 'pins-are-release-tags: measured nothing: up.sh defines no pin_of table\n' >&2
  exit 1
fi
read -r pin_start pin_end <<<"$pin_span"

pinned_span="$(fn_span pinned_repo)"
if [ -z "$pinned_span" ]; then
  printf 'pins-are-release-tags: measured nothing: up.sh defines no pinned_repo\n' >&2
  exit 1
fi
read -r pr_start pr_end <<<"$pinned_span"

locate_span="$(fn_span locate_repo)"
read -r lr_start lr_end <<<"${locate_span:-0 0}"

# 1. the table: one entry per component, each a release tag and a full commit.
required="keyryx tokenfuse wardryx vouchryx idryx heraldyx scopyx costcrew typryx trailryx qryx mockryx agent-stack-go engram verdryx"
entries=0
labels=""
while IFS= read -r line; do
  label="$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]+([a-z*-]+)\).*/\1/')"
  case "$label" in
    '*') continue ;;
  esac
  labels="$labels $label"
  if [ "$label" = verdryx ]; then
    printf '%s\n' "$line" | grep -qE '^[[:space:]]+verdryx\)[[:space:]]*;;[[:space:]]*$' \
      || problem "pin_of entry for verdryx names a release, and verdryx publishes none (it is built only with --from-main)"
    continue
  fi
  if printf '%s\n' "$line" | grep -qE '^[[:space:]]+[a-z-]+\)[[:space:]]+echo "v[0-9]+[.][0-9]+[.][0-9]+ [0-9a-f]{40}" ;;[[:space:]]*$'; then
    entries=$((entries + 1))
  else
    problem "pin_of entry for $label is not a release tag and a full commit: $(printf '%s' "$line" | sed -E 's/^[[:space:]]+//')"
  fi
done <<EOF
$(sed -n "$((pin_start + 1)),$((pin_end - 1))p" up.sh | grep -E '^[[:space:]]+[a-z*-]+\)')
EOF

for need in $required; do
  case " $labels " in
    *" $need "*) ;;
    *) problem "pin_of has no entry for $need, which the launcher builds" ;;
  esac
done

# 2. every literal pinned_repo call names a component the table knows.
while IFS= read -r name; do
  case " $labels " in
    *" $name "*) ;;
    *) problem "pinned_repo names $name, which has no pin_of entry" ;;
  esac
done <<NAMES
$(grep -v -E '^[[:space:]]*#' up.sh | grep -o -E 'pinned_repo [a-z][a-z-]*' | awk '{print $2}' | sort -u)
NAMES

# 3. locate_repo is called only from pinned_repo.
for n in $(call_lines 'locate_repo'); do
  if ! inside "$n" "$pr_start" "$pr_end"; then
    problem "locate_repo is called outside pinned_repo (up.sh:$n); a build would take a sibling checkout whatever it holds"
  fi
done

# 4. git clone runs only inside pinned_repo or locate_repo (which only --from-main reaches).
for n in $(call_lines 'git clone'); do
  if ! inside "$n" "$pr_start" "$pr_end" && ! inside "$n" "$lr_start" "$lr_end"; then
    problem "git clone runs outside pinned_repo and locate_repo (up.sh:$n)"
  fi
done

pinned_body="$(sed -n "${pr_start},${pr_end}p" up.sh)"
printf '%s\n' "$pinned_body" | grep -qF -- '--branch "$tag"' \
  || problem "pinned_repo does not clone the release tag (--branch \"\$tag\")"
printf '%s\n' "$pinned_body" | grep -qF -- 'rev-parse HEAD' \
  || problem "pinned_repo does not read the HEAD of the checkout it is about to build"
printf '%s\n' "$pinned_body" | grep -F -- '= "$commit" ] ||' | grep -q 'return 1' \
  || problem "pinned_repo does not refuse a checkout that is not the pinned commit"

# 5. --from-main is a flag, and it says the build is not the pinned release.
grep -qF -- '--from-main) FROM_MAIN=1 ;;' up.sh \
  || problem "--from-main is not a flag (--from-main) FROM_MAIN=1 ;;)"
grep -qF -- 'checkouts, NOT the pinned release' up.sh \
  || problem "--from-main does not say it is not the pinned release"

if [ "$problems" -ne 0 ]; then
  exit 1
fi
echo "pins-are-release-tags: $entries components pinned to a release tag and a full commit; verdryx publishes no release tag and is built only with --from-main; every clone goes through pinned_repo, which refuses any checkout that is not the pinned commit"
