# CLAUDE.md, working instructions for stack-up

These instructions apply to any model working in this repo. Read this file
before changing anything. It holds process and invariants only: **no status.**

## Read before you change anything

1. `README.md`, for what `up.sh` promises.
2. `up.sh` and `down.sh` together. They are a pair, and a change to one that
   is not matched in the other leaves a machine with something still running.

## What this is

The free, minimal, public launcher: one bash `up.sh` that runs the open stack
locally on a fixed loopback port map, seeds a short demo dataset, prints a
dashboard link, and tears down cleanly. It is the neutral adoption channel
surfaced on the it-rat Platform page.

## Blast radius

This is the first thing a stranger runs. If it fails, they do not file an issue,
they close the tab. If it leaves something listening after `down.sh`, they find
out weeks later and trust nothing else we ship.

## Gates

```sh
shellcheck up.sh down.sh routines.sh
bash -n up.sh && bash -n down.sh && bash -n routines.sh
./scripts/loopback-only.sh
./scripts/gates-have-teeth.sh   # invariant 6; needs a clean tree
```

Two callers, one copy of each check: `.github/workflows/gates.yml` and
`.githooks/pre-push`. Never inline a check into either.

**Until 2026-08-01 the hook was the only caller, and that was a hole.**
`core.hooksPath` is local configuration: it is not committed and does not travel
with a clone, so these gates enforced nothing for anybody who cloned this repo.
`.github/workflows/gates.yml` calls the same scripts, one copy each, and is what
makes them travel. This repo is public, so standard runners cost nothing.
`git push --no-verify` still skips the local half.

## Hard invariants

Each one carries how it is held today. Use `(gate: ...)`, `(test: ...)`,
`(partly gated: ...)` or `(not enforced)`, and use the weakest one that is
true. An invariant with no check, written as though it had one, is worse than
an absent invariant.

1. **Loopback only.** The port map (gateway 4100, cloud 8080, dashboard 3000,
   wardryx 8090, idryx 8081) is fixed and bound to loopback. This is a local
   demonstration, and the README says so; it is explicitly **not a supported
   deployment layout**. Never make it easy to bind elsewhere.
   *(gate: `scripts/loopback-only.sh`, and read the next paragraph before
   trusting the marker's history. Two faults were found in it on 2026-08-09 by
   invariant 6's harness, and one of them meant this gate had never judged a
   single address through its main branch.)*

   **What was wrong with it, because a gate's own record is worth having.**
   The assignment branch skipped any value containing `$`, reasoning that a
   reference is not a literal. Every real URL in this launcher is
   `http://127.0.0.1:$SOMETHING_PORT`, so that skip covered all of them:
   measured, two address-shaped assignments, both skipped, zero judged.
   Changing `127.0.0.1` to `0.0.0.0` on either line passed cleanly, and that is
   exactly the edit somebody makes to reach the dashboard from another machine.
   A `$` in the HOST is what genuinely cannot be judged, and that is now the
   only thing skipped.

   Separately, a launcher file that is not there was skipped, and skipping all
   three was a pass: it reported every address loopback having read none.
2. **`down.sh` leaves nothing behind.** No listener, no stale pidfile, no
   container, no seeded data pretending to be real. Every service `up.sh`
   starts, `down.sh` stops. *(not enforced)*
3. **`up.sh` is idempotent.** Running it twice must not start a second copy or
   half-configure the first. The second run is the real test.
   *(not enforced)*
4. **The demo data is visibly demo data.** A number a newcomer might screenshot
   must not look like production telemetry. *(not enforced)*
5. **Reuse rather than rebuild.** If a binary is already built, use it. A first
   run that takes twenty minutes loses the reader.
   *(not enforced)*

6. **A check must be able to tell "did not fail" from "did not run", and the
   gate here has been made to fail on purpose to prove it can.** This
   repository is the sharpest case in the estate for that rule, because the
   gate it applies to was holding invariant 1, the one property this repo
   promises a stranger, and it was holding nothing at all.

   Both faults are recorded under invariant 1 above rather than here, because
   a gate's own history belongs beside the gate.
   *(gate: `scripts/gates-have-teeth.sh`, 3 cases: one real fault, one
   non-fault, and one subject taken away. The non-fault carries the three
   shapes the first version of `loopback-only.sh` got wrong, reporting five
   failures on a correct tree: a placeholder filled in later, a value that is a
   reference rather than a literal, and an address inside prose. A gate that
   flags any of those gets deleted by whoever hits it, and then the real fault
   goes through.)*

   **What it does not cover.** It cannot test itself. It proves the gate
   catches the faults named in it, not every fault of that kind. The `curl`,
   `wget`, `nc` and `--host` branches of the gate have no case here; they were
   read rather than mutated, and that is a weaker check, stated rather than
   glossed.

## Decisions that have no gate yet

**Held by this file alone: invariants 2, 3, 4 and 5.**

Invariant 1 is now `scripts/loopback-only.sh`, and it is not the grep the
previous version of this paragraph imagined. That grep was written, reported
five failures, and all five were wrong: an install hint in a `die` message
pointing at rustup.rs, the Apple DTD identifier inside a launchd plist, and
three `URL=""` defaults filled in later. None is an address this launcher
connects to.

So it resolves ASSIGNMENTS and judges their values. An empty value is a
placeholder, a `$`-reference is not a literal, and a literal address must be
loopback; a `curl` or a `--bind` is judged by its target. Prose and identifiers
are not assignments and are left alone. A matcher that cannot tell an address
from a sentence should not be deciding. Invariants 2 and
3 need a real run-twice-then-teardown test, which is the thing most worth
building here and the thing that most often gets skipped.

## Standing rule

7. **The trust domain the record plane is given comes from the deployment, and
   the seal refuses BEFORE it consumes.**

   The plane accepts an event only if its agent id begins `agent://<domain>/`,
   matched as one byte prefix against exactly one value. A domain matching
   nothing is not an error there: every line is counted under
   `foreign_trust_domain` and the process exits 0.

   Measured 2026-08-27 on this launcher's own bus: the seal was given
   `demo.local` while every line was minted under `local.invalid`,
   `mockryx.local` or `acme`. It wrote 0 records across 52 lines, recorded
   status `ok`, and printed "0 record(s) sealed" under a banner calling it
   expected. All 35 records in the seven segments that did exist were the
   synthetic demo fleet. Not one event any real plane had ever emitted was in
   the record.

   **The ordering is the invariant, not the message.** The plane commits its
   cursor for a run that wrote zero records, so a check after the import loop
   reports a loss it could have prevented: the next pass, with the domain
   corrected, answers "nothing new. The cursor is at byte N of N (40 line(s),
   0 record(s) so far)", and the only way back is deleting a cursor file by
   hand, which nothing tells an operator to do.

   **Partial refusal is the designed state and must not be an error.** This
   launcher mints under several domains on purpose: scopyx uses `local.invalid`
   because RFC 2606 reserves `.invalid`, so a sandbox identity cannot be
   mistaken for a real one in somebody's trail. `--trust-domain` takes one
   value, so only a total refusal is a fault.

   The default is named once and the two launchers are held equal, because
   before this they were two literals joined by the comment `# keep in sync
   with up.sh` and nothing checked the pair. `up.sh` writes the domain it
   actually used to `$STACK_UP_HOME/trust-domain`, because neither generated
   unit passes environment through, so an exported variable reaches a run by
   hand and never reaches the timer.
   *(gate: `scripts/one-trust-domain.sh`, with four cases in
   `gates-have-teeth.sh`: the two launchers disagreeing, the backstop removed,
   the check moved after the import loop, and both subjects renamed away)*

An approved architecture decision is **not finished** until it is two things: a
numbered invariant in this file, and a gate in a script if it can be checked
structurally. Until then it is a document, and documents do not stop code.

## Conventions

- **No long dashes** anywhere: not in code, docs, commit messages, or PR
  bodies. Use a comma, a colon, parentheses, or a short hyphen.
- Nothing paid or metered gets enabled without telling the user first and
  getting agreement.
- Do not delete or revoke keys, tokens, or certificates on your own initiative.
