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
./scripts/one-trust-domain.sh
./scripts/gateway-decides-its-upstream.sh
./scripts/gateway-cache-is-off.sh
./scripts/declassify-is-keyed.sh
./scripts/revoke-key-not-printed.sh
./scripts/typed-mode.sh
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

8. **The delegation bring-up keeps a revocation across a restart, and its key
   is a secret, not a demo value.** `--with-delegation` points vouchryx at an
   on-disk revocation store (`$STACK_UP_HOME/delegation/revocations.ndjson`)
   and mints a bearer key once, at `$STACK_UP_HOME/delegation/revoke.key`
   (0600, `umask 077` before the file is written), reusing it on every later
   run rather than rotating it: a rotation revokes nothing, it only orphans a
   revocation recorded under the old key. Neither file sits under a path
   `down.sh` touches, so `./down.sh` then `./up.sh --with-delegation` keeps an
   earlier revocation in force rather than forgetting it, which is what this
   launcher did on every restart before vouchryx's own revocation store
   existed. The closing summary also hands genaryx's own console the two
   variables it needs to revoke from there instead of `curl`
   (`GENARYX_VOUCHRYX_URL`, `GENARYX_VOUCHRYX_REVOKE_KEY_FILE`, the second a
   PATH, never the key's content), printed for the operator to export, since
   this launcher does not start `genaryx-web` itself.
   *(partly gated: `scripts/revoke-key-not-printed.sh` proves the key's
   content is read once and handed straight to vouchryx's own environment,
   never to a `log`/`warn`/`echo`/`printf` call. What it does not cover: that
   a revocation actually survives the restart. That half has no script, for
   the same reason invariants 2 and 3 don't: it needs a real
   run-twice-then-teardown test, which nothing here has yet, and is instead
   shown by hand in the commit that added this invariant.)*

9. **The gateway's semantic response cache is turned off explicitly, not left
   to its default.** `@decided 2026-09-24`: unset, tokenfuse's gateway enables
   the cache in shadow mode, which takes one global mutex per call and walks
   up to 10,000 cached entries computing cosine similarity, serving nothing;
   this launcher sets `TOKENFUSE_CACHE="off"` on every gateway start instead
   (tokenfuse#319).
   *(gate: `scripts/gateway-cache-is-off.sh`)*

10. **Where typryx's data goes is chosen on purpose, refused before anything is
    built, and the Jev key is a file this launcher never reads.**
    `@decided 2026-09-30`: typed answers have three data modes and the
    operator picks one. `--typed-mode jev` sends the named fields of each
    question to TypeSafe AI's hosted API and needs `--typed-key-file`;
    `--typed-mode own-model` points typryx at the operator's own
    OpenAI-compatible server (`--typed-model-url` ending in `/v1`,
    `--typed-model`, optional key file) so nothing leaves their hardware;
    `--typed-mode off` starts nothing. No mode is picked for anyone: with no
    `--typed-mode`, nothing starts, and `--with-typed` alone is the stub
    backend with no environment change. A bad choice exits 2 at argument
    parsing, before any build, probe or write (`--typed-plan` stops there and
    prints what would start and what would leave the machine). The key is a
    FILE: the launcher checks it is not blank with `grep -q`, hands typryx the
    path in its environment, and never puts the bytes in a variable, an
    argument or a log line. Under a chosen mode the other backend's variables
    are removed from typryx's environment, so a stale exported
    `TYPRYX_JEV_URL` cannot redirect the key.
    **The local training log is a second opt-in, `--typed-training`, off by
    default.** `@decided 2026-09-30`: a customer may train a model of their own
    on their own questions and their own human judgements, typryx keeps the
    records, and the log is off unless switched on. On, it sets typryx's
    `TYPRYX_TRAINING_DIR` to `$STACK_UP_HOME/typryx/training`, beside the ledger
    the launch already gives typryx (the export needs the ledger for the human
    truths). The launcher creates that directory 0700 (and tightens one that
    existed looser), refuses the flag when typryx is not going to run (exit 2,
    at argument parsing, like every other bad choice here), refuses a typryx
    older than v0.3.0 at launch rather than start one that ignores the variable,
    and does not touch the path in `--typed-plan`. The log holds the question
    fields a template lets through and never a backend's answer, so a Jev answer
    cannot become a training label through it; the launcher never reads or
    sends the log, and README shows `typryx export --training`.
    *(gate: `scripts/typed-mode.sh`, 77 checks through `--typed-plan`, plus a
    static check that up.sh never reads the key file, plus the training log's
    directory function and typryx's can-it-log function cut out of `up.sh` and
    run (0700 fresh and tightened, an old typryx refused); 21 typed cases in
    `gates-have-teeth.sh`. What it does not cover: typryx actually running in
    each mode, and the key staying out of the running process's arguments and
    log. That half was shown by hand in the pull request that added this
    invariant, not by a script, because it needs a built typryx and a free
    port. The same holds for the training log: that a real ask writes a line,
    that the export pairs it with a posted truth and drops the extra field was
    run by hand in the pull request that added it, not by a script. typryx is
    built from whatever checkout is found, no tag is pinned, so a run on an
    older checkout is caught only by the launch-time refusal, not by the plan.)*

11. **The gateway's declassify key is minted per run and reaches the gateway
    through its environment only.** `@decided 2026-10-04` (estate audit, wave 1):
    the tokenfuse gateway's `POST /v1/fuse/declassify` lifts a run's taint
    label, the release valve for its agent firewall. It is not behind the
    money plane's key; its own credential, `TOKENFUSE_DECLASSIFY_KEY` (presented
    as `x-fuse-declassify-key`), is optional in the gateway, and with it unset
    anything that can reach the gateway port can clear a run, recorded only as
    `authenticated: false`. This launcher set none. `up.sh` now mints
    `GATEWAY_DECLASSIFY_KEY` with `rand_hex 24` before the first gateway start,
    refuses to continue on an empty result (the gateway reads an empty value as
    unset, so a failed mint would leave the endpoint open without a word), and
    gives it to each gateway start as a PREFIX assignment ahead of `env`, not an
    argument to it: an argument to `env` is on its command line for the moment
    before it execs the gateway. The closing summary prints the key once with
    the URL it opens and says it is held in the gateway's environment only and
    minted fresh each run, the posture typryx's and the broker's per-run keys
    already have. Nothing in this estate calls the endpoint, so minting a key
    closes it by default and breaks nothing. The reader is tokenfuse's
    `declassify.rs`, declared in its `components.json`.
    *(gate: `scripts/declassify-is-keyed.sh`, subjects found like invariant 9's
    (every `"$GATEWAY_BIN"` command-position start, `mcp-broker` excluded); it
    requires a variable-valued `TOKENFUSE_DECLASSIFY_KEY` on each start ahead of
    any `env`, a `rand_hex` mint above the first start, and the refusal after
    it; refuses to report OK with no up.sh, no `GATEWAY_BIN` or no start to
    judge; teeth in `scripts/gates-have-teeth.sh`. Not covered: a running
    gateway actually refusing a call with no key, which needs a built gateway;
    and that a value in the process environment is private: it is on no command
    line, but the same user can read it (`/proc/<pid>/environ` on Linux, `ps eww`
    on macOS).)*

An approved architecture decision is **not finished** until it is two things: a
numbered invariant in this file, and a gate in a script if it can be checked
structurally. Until then it is a document, and documents do not stop code.

## Conventions

- **No long dashes** anywhere: not in code, docs, commit messages, or PR
  bodies. Use a comma, a colon, parentheses, or a short hyphen.
- Nothing paid or metered gets enabled without telling the user first and
  getting agreement.
- Do not delete or revoke keys, tokens, or certificates on your own initiative.
