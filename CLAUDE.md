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
```

There is no CI in this repo, so the local gates are the only gates.

## Hard invariants

Each one carries how it is held today. Use `(gate: ...)`, `(test: ...)`,
`(partly gated: ...)` or `(not enforced)`, and use the weakest one that is
true. An invariant with no check, written as though it had one, is worse than
an absent invariant.

1. **Loopback only.** The port map (gateway 4100, cloud 8080, dashboard 3000,
   wardryx 8090, idryx 8081) is fixed and bound to loopback. This is a local
   demonstration, and the README says so; it is explicitly **not a supported
   deployment layout**. Never make it easy to bind elsewhere.
   *(not enforced)*
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

## Decisions that have no gate yet

Every invariant above is held by this file alone. That is the honest state.

Invariant 1 is the cheapest to gate: fail if any port in the map is bound to
anything but loopback, which is a grep with a reason attached. Invariants 2 and
3 need a real run-twice-then-teardown test, which is the thing most worth
building here and the thing that most often gets skipped.

## Standing rule

An approved architecture decision is **not finished** until it is two things: a
numbered invariant in this file, and a gate in a script if it can be checked
structurally. Until then it is a document, and documents do not stop code.

## Conventions

- **No long dashes** anywhere: not in code, docs, commit messages, or PR
  bodies. Use a comma, a colon, parentheses, or a short hyphen.
- Nothing paid or metered gets enabled without telling the user first and
  getting agreement.
- Do not delete or revoke keys, tokens, or certificates on your own initiative.
