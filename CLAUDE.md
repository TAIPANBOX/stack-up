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
./scripts/cloud-key-is-per-run.sh
./scripts/cloud-key-is-not-printed.sh
./scripts/admin-keys-are-per-run.sh
./scripts/postures-are-held.sh
./scripts/keyryx-is-per-run.sh
./scripts/wardryx-fails-closed.sh
./scripts/firewall-is-enforce.sh
./scripts/pii-is-shadow.sh
./scripts/revoke-key-not-printed.sh
./scripts/typed-mode.sh
./scripts/run-budget-ceiling-is-set.sh
./scripts/bus-files-match-sources.sh
./scripts/chain-verify-routine.sh
./scripts/manifest-is-true.sh
./scripts/features-are-bound.sh
./scripts/die-keeps-its-exit-status.sh
./scripts/demo-issuer-is-unbound.sh
./scripts/bus-is-operator-owned.sh
./scripts/demo-runs-after-its-planes.sh
./scripts/pins-are-release-tags.sh
./scripts/risk-hold-is-seeded.sh
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
   *(gate: `scripts/gateway-cache-is-off.sh`, teeth in
   `scripts/gates-have-teeth.sh`, including a launcher with no gateway start at
   all: until 2026-10-04 this gate and `gateway-decides-its-upstream.sh` read
   their subjects through a here-document that always delivers one empty line,
   so zero starts counted as one and their "measured nothing" refusal could
   never fire. `@measured` both gateway launch lines renamed in a scratch copy,
   2026-10-04: both gates exited 0 "(1 checked)" before the fix and exit 1
   "measured nothing" after.)*

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
    *(gate: `scripts/typed-mode.sh`, 128 checks through `--typed-plan` (the last 51 are
    invariant 13's), plus a
    static check that up.sh never reads the key file, plus the training log's
    directory function and typryx's can-it-log function cut out of `up.sh` and
    run (0700 fresh and tightened, an old typryx refused); 43 typed cases in
    `gates-have-teeth.sh` (21 for this invariant, 22 for invariant 13). What it does not cover: typryx actually running in
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

12. **Every gateway start sets the operator's run-budget ceiling, and the flag
    refuses what the gateway would refuse.** tokenfuse v1.5.0 (invariant 73) has
    `TOKENFUSE_MAX_RUN_BUDGET_USD`, a ceiling on the budget one run may be
    granted when that budget comes from the caller's `x-fuse-budget-usd` header,
    a policy default or the built-in USD 5, applied on every call so widening an
    open run reaches the ceiling and no further. It is off unless set, so a
    launcher that sets nothing is no more bounded than before. `up.sh` sets it
    on both gateway starts from `RUN_BUDGET_CEILING_USD`, default `5.00`,
    overridden by `--run-budget-ceiling <usd>`; `--plan` prints the figure.
    `@claude 2026-10-04`: default 5.00 equals tokenfuse's own DEFAULT_RUN_BUDGET,
    so an ordinary run is unchanged and only a caller-declared larger budget is
    clamped. Not on the Cloud budget (tokenfuse does not clamp those) and not on
    the MCP broker (it holds no run budget). It is one figure per run, not per
    agent: an agent that opens a new run id gets a new ceiling's worth. A figure
    the gateway would refuse (zero, a sign, `1e9`, a seventh decimal, past
    9223372036854.775807; measured against a v1.5.0 gateway 2026-10-04) exits 2
    at argument parsing, before any build, rather than after it as "gateway did
    not come up". A gateway that does not name the setting (built before v1.5.0,
    for example one another tool installed) is refused when the operator asked
    for a figure and warned about otherwise, judged by the binary naming the
    setting (`bin_reads_setting`), nothing executed.
    *(gate: `scripts/run-budget-ceiling-is-set.sh`, 2 starts checked, 22 figures
    driven through `--plan`, the old-gateway function cut out of `up.sh` and run
    on three files; 14 cases in `gates-have-teeth.sh`. Not covered: a running
    gateway clamping a call, which is tokenfuse's own test and needs a built
    gateway.)*

13. **The typed risk signal is opt-in, says what leaves the machine before
    anything starts, and reaches only the MCP broker.** `@decided 2026-10-04`
    (estate audit, J2): the first typryx consumer is wardryx, and a risk signal
    may turn a call into a hold and never a deny. Here, `--typed-risk-signal`
    runs `typryx wardryx-proxy` (typryx v0.4.0) on `127.0.0.1:4330` in front of
    wardryx and points the broker's `TOKENFUSE_WARDRYX_URL`, and only the
    broker's, at it. Off by default. Refused at argument parsing (exit 2) unless
    typryx is going to run (`--with-typed`, or `--typed-mode jev` or `own-model`;
    `off` contradicts it) and wardryx is (not `--only money`); refused at launch
    when wardryx did not come up, when typryx lacks the proxy, or when the
    checkout lacks the `action.risk_class` template. The LLM gateway keeps
    talking to wardryx directly: the model path has no pending call to classify
    and a hosted backend's latency would push decisions past the gateway's own
    timeout. No `hold_if_signal` policy is seeded by a plain run.
    `@claude 2026-10-19`: with the flag, invariant 28 seeds one hold on a missing signal;
    README.md shows how to write your own.
    `--typed-plan` prints what leaves the machine for the chosen backend: under
    jev, the tool name, arguments and target of every brokered call go to
    TypeSafe AI, one ask per call. `@claude 2026-10-04`: the broker's policy gate
    is off unless `TOKENFUSE_WARDRYX_MODE` and `_URL` are both set, so the
    launcher also sets MODE=enforce (the gateway's own mode here), KEY and a
    timeout on the broker; the spec named only the URL. The proxy runs with no
    journal, no ledger, no keys and no training log: each would make it a second
    writer of a file the typryx service owns (the journal is one hash chain with
    one writer, and `agent-conform` now verifies it), and the training log would
    copy every tool call's arguments. "Only the broker can reach it" is as strong
    as a loopback bind on one machine: any local process can, and it carries no
    key because the broker cannot add an `X-Typryx-Key` header. Deadlines,
    aligned with stack-single#88: the proxy asks its backend before it forwards
    the decision, and typryx's own default ask deadline of 150 ms drops a hosted
    answer (Jev median 229 ms) and a local-model answer (qwen2.5:7b median
    2130 ms on 8 vCPU), after which the call is forwarded with no signal and a
    `hold_if_signal` rule never fires, silently. So `TYPRYX_PROXY_ASK_TIMEOUT_MS`
    is 3000 (`RISK_ASK_TIMEOUT_MS`; longer than the longest measured answer and
    inside typryx's 1 to 5000), and the broker's decide deadline is
    `TOKENFUSE_MCP_WARDRYX_TIMEOUT_MS=7000` (`RISK_DECIDE_TIMEOUT_MS`; the variable
    tokenfuse reads for a decide that carries a tool call, longer than the ask).
    The LLM gateway's own wardryx timeout (2000) is not touched: it never goes
    through the proxy. `typryx`'s own backend deadline `TYPRYX_TIMEOUT_MS` (2 s by
    default, passed through unchanged) is separate: a local model slower than that
    still needs it exported.
    *(gate: `scripts/typed-mode.sh`, section 9 through `--typed-plan` and 7b
    statically, 51 checks, and 22 cases in `gates-have-teeth.sh`. Not covered: the
    proxy running in front of a real wardryx behind this broker with a policy that
    holds; shown by hand in the pull request that added this, not by a script,
    because it needs built binaries and free ports.)*

14. **Every stream file this launcher configures is one heraldyx and idryx accept
    as the source it carries.** heraldyx v0.3.0 and idryx v1.1.0 refuse an event
    whose `source` is not allowed for its file: `<source>.ndjson` carries
    `<source>`, `tokenfuse-cloud.ndjson` and `tokenfuse-mcp.ndjson` carry
    `tokenfuse`, anything else is read only for lines claiming its own name. This
    launcher writes `tokenfuse`, `tokenfuse-mcp`, `wardryx`, `scopyx`, `vouchryx`,
    `costcrew`, `typryx`, `verdryx` and `agent-conform` under `$EVENTS_DIR`, and
    passes idryx `--load tokenfuse:tokenfuse.ndjson` in two places; the table is in
    the pull request that checked it. `@claude 2026-10-04`: the gate's allow table
    is a copy of the readers' own, and nothing holds the three equal.
    *(gate: `scripts/bus-files-match-sources.sh`, 9 stream files and 2 `--load`
    pairs, teeth in `gates-have-teeth.sh`. Not covered: what each producer writes
    INTO its file; read from each producer's source constant, not measured.)*

15. **The chain-verify routine never calls a standing break ok.**
    `@claude 2026-10-04`: agent-stack-go v1.1.0's `agent-conform watch-dir`
    verifies the `prev_hash` chain of every stream in the events directory and
    appends one `chain_broken` (high) event per NEW break to its own
    `agent-conform.ndjson`, announcing each break once. `up.sh` installs the
    binary (built from agent-stack-go's `cmd/agent-conform`, not started) and
    `routines.sh` runs it daily at 06:52 as `chain-verify`, in the default set,
    state file under `routines/` and not in the bus. It announces once, so the
    second run exits 0 on a bus that is still broken: exit 0 with a `FAIL` line in
    its output is recorded `findings`, never `ok`; exit 1 is `findings`, exit 2 is
    `error`. heraldyx v0.3.0 mails a `chain_broken` with generic wording (an event
    this build has no description for, naming neither the file nor a tamper), and
    the record plane counts it as `unknown_schema` and does not seal it.
    *(gate: `scripts/chain-verify-routine.sh`, 11 checks against a stand-in
    verifier, teeth in `gates-have-teeth.sh`. Not covered: the real verifier on a
    real bus, shown by hand in the pull request that added this.)*

16. **`up.sh` leaves with the status it was exiting with.** `@claude 2026-10-04`:
    `die` runs `exit 1`, and the EXIT trap's `cleanup` used to end in a hard-coded
    `exit 0`, so from the moment the trap was armed every refusal ("the gateway
    did not come up", "needs a gateway built from tokenfuse v1.5.0") printed its
    error and exited 0, and a script, a CI step or a supervisor driving the
    launcher read a failed bring-up as a success (measured 2026-10-04, found while
    running the refusals of the 2026-10-04 releases). Now `cleanup` leaves with
    the status the script was exiting with; the INT and TERM traps pass 0 (the
    operator stopping the stack on purpose); the hold loop passes 1, because a
    plane that died underneath the launcher did not stop it cleanly (this changes
    that path's status from 0 to 1).
    *(gate: `scripts/die-keeps-its-exit-status.sh`, which runs the launcher's own
    `cleanup` and trap lines (cut out of `up.sh`, not copied) with and without a
    started service, 7 checks, 6 cases in `gates-have-teeth.sh`. Not covered: the
    whole launcher dying at each of its `die` sites; shown by hand in the pull
    request that added this for one refusal, a SIGTERM and a killed plane.)*

17. **The tokenfuse cloud holds one key minted for the run, and every caller of
    the cloud uses that key.** `@claude 2026-10-09`: tokenfuse#380 removes the
    cloud's `devkey` fallback. A cloud started with `TOKENFUSE_CLOUD_ALLOW_DEVKEY`
    set logs an ERROR and exits 2, and an empty `TOKENFUSE_CLOUD_KEYS`
    authenticates nobody, so this launcher, which ran the cloud exactly that way,
    would stop at "cloud did not come up". `up.sh` now mints `CLOUD_KEY` with
    `rand_hex 16` above the first gateway start (the gateway is handed the key at
    its start; the cloud now starts before it, invariant 27), refuses to continue on an empty result, and
    starts the cloud with `TOKENFUSE_CLOUD_KEYS="$CLOUD_KEY:default:admin"` (the
    org, role and no-site the old fallback had). The gateway gets it as
    `TOKENFUSE_CLOUD_KEY`, a prefix assignment ahead of `env` like the declassify
    key; the demo seed, the dashboard link and the closing summary carry the same
    key, and the summary names the file that holds it instead of printing it
    (invariant 26). `STACK_UP_CLOUD_KEY` replaces the minted
    key with the operator's own, refused at argument parsing (exit 2) unless it
    is 16 to 128 characters from `A-Z a-z 0-9 . _ ~ -`, because it is written into
    a `key:org:role` spec and a URL query. Nothing sets
    `TOKENFUSE_CLOUD_ALLOW_DEVKEY`. Scope is the cloud's key only: wardryx's own
    dev-key mode (`WARDRYX_ALLOW_DEVKEY`, the `devkey` placeholder in
    `TOKENFUSE_WARDRYX_KEY` and `SCOPYX_WARDRYX_KEY`) is a separate decision and
    unchanged. The quiet failure this guards is the gateway: handed a key the
    cloud does not hold, it starts, meters every call and gets a 401 on every
    push to the cloud, which only its own log shows.
    *(gate: `scripts/cloud-key-is-per-run.sh`: no non-comment
    `TOKENFUSE_CLOUD_ALLOW_DEVKEY=`; every cloud start sets `TOKENFUSE_CLOUD_KEYS`
    from one variable; that variable minted with `rand_hex` above the first
    gateway start with the refusal after it; every gateway start sets
    `TOKENFUSE_CLOUD_KEY` from the same variable ahead of `env`; every other use
    of the cloud's credential (a logical line naming `CLOUD_PORT`) presents that
    variable and never `devkey`; refuses to report OK with no up.sh, no cloud
    start, no gateway start or no cloud call to judge. 15 cases in
    `gates-have-teeth.sh`, `features/the-cloud-key-is-minted-per-run.feature`.
    Not covered: a running cloud accepting the key and refusing `devkey`, which
    needs a built cloud; and that the key is private: it is printed in the
    file and the dashboard link's fragment on purpose (invariant 26), and the seed's `curl` carries it
    on its command line for the moment it runs.)*

18. **Every gateway start runs tokenfuse's agent firewall from one switch, and the
    switch defaults to enforce.** `@decided 2026-10-13`: the launcher runs the agent
    firewall in enforce by default, shipped as its own change after a test stack,
    and one switch, `--firewall enforce|shadow|off`, runs it in shadow or off.
    `up.sh` sets `TOKENFUSE_FIREWALL` on both gateway starts from `FIREWALL_MODE`,
    which only `--firewall` fills: never the caller's environment, never a literal.
    The MCP broker start does not carry it, since the broker is the same binary on a
    subcommand and reads no firewall. Any other word exits 2 at argument parsing,
    because tokenfuse's own loader keeps its shadow default silently for a value it
    does not name. `@claude 2026-10-13`: the flag's name, its three words and the
    refusal are my choices under that decision; the enforce default is the decision.
    What enforce refuses, on tokenfuse's starter policy: exec, write and network
    egress on a run that has read untrusted input (web, email, file or unclassified
    sources, or a tool result that read like an instruction), and network egress on
    a run holding a secret. A tool a request declares whose description reads as an
    instruction carries the same injection label (tokenfuse's invariant 93).
    *(gate: `scripts/firewall-is-enforce.sh`: every gateway start (a launch at the
    command position, not `mcp-broker`) carries exactly one `TOKENFUSE_FIREWALL`
    assignment, and it is `"$FIREWALL_MODE"`; `FIREWALL_MODE` is `enforce` by
    default; the MCP broker start carries none; `--plan` names the mode; `--firewall`
    accepts enforce, shadow and off and refuses every other word with exit 2, and
    creates no state directory on a refusal. Refuses to report OK with no up.sh, no
    GATEWAY_BIN, no gateway start or no `--plan`. 14 cases in
    `gates-have-teeth.sh`, `features/the-agent-firewall-is-enforce-by-default.feature`
    (14 scenarios). Not covered: that a running gateway refuses a dangerous
    capability on a run that read untrusted input. That is tokenfuse's own test (its
    invariants 25 to 27 and 93) and needs a built gateway; this gate proves only that
    the launcher hands the gateway the switch's value.)*

19. **Every gateway start runs tokenfuse's PII masks from one switch, and the switch
    defaults to shadow.** `@decided 2026-10-13` (paraphrased): personal data in
    prompts and tool arguments is recorded as an event and never refused, and an
    operator keeps one switch, `--pii off|shadow|mask|block`, to run them otherwise.
    `@claude 2026-10-13`: "recorded as an event" in that paraphrase is wrong about the
    mechanism, and the decision stands: shadow writes no event and no trace row. The
    gateway adds an `x-fuse-dlp` header and the broker logs a warning, each with the
    count and kinds found, and marks `_tokenfuse.dlp_pii` on tool responses.
    `up.sh` sets `TOKENFUSE_DLP_PII` on each gateway start and `TOKENFUSE_MCP_DLP_PII`
    on the MCP broker start, both from `PII_MODE`, which only `--pii` fills: never the
    caller's environment, never a literal. Any other word exits 2 at argument parsing,
    because tokenfuse keeps its off default silently for a value it does not name.
    `@claude 2026-10-13`: the flag's name, its four words and the refusal are my
    choices under that decision; the shadow default is the decision.
    *(gate: `scripts/pii-is-shadow.sh`: every gateway start carries exactly one
    `TOKENFUSE_DLP_PII` assignment, taken from `"$PII_MODE"`; the default is
    `PII_MODE="shadow"`; the broker start, where present, carries
    `TOKENFUSE_MCP_DLP_PII` the same way; `--pii` accepts the four words and refuses
    every other with exit 2, and a refusal or a plan creates no state directory. It
    refuses to report OK with no up.sh, no GATEWAY_BIN, no gateway start or no
    `--plan`. 16 cases in `gates-have-teeth.sh`, 13 fault and 3 pass. Not covered: that
    a running gateway records a personal-data hit in shadow and refuses one in block,
    which is tokenfuse's own test and needs a built gateway; and that a gateway binary
    names the setting, which the launcher does not check.)*

20. **The gateway fails closed on its policy decision point, and the launcher stops when that point does not come up.**
    `@decided 2026-10-17` (paraphrased): a gateway wired to the policy plane refuses a decision it cannot get,
    and a stand whose gateway is wired to it does not run without it. tokenfuse's default fail mode is open,
    which allows a call whose decision never arrives, so every gateway start that sets `TOKENFUSE_WARDRYX_MODE`
    also sets `TOKENFUSE_WARDRYX_FAILMODE=closed`. The wardryx health wait ends in `|| die`: a wardryx that does
    not answer, or cannot be fetched or built, exits the launcher with a non-zero status after the EXIT trap has
    stopped what it started. Nothing that the launcher prints says the gateway will fail open.
    `@claude 2026-10-17`: the fail mode and the stop are my reading of the decision. The variable's name and its
    two words (`open`, `closed`) were read in tokenfuse's `defaults.rs` (`wardryx_failmode_from`); what the closed
    branch does with an unanswered decision was not read here and not run.
    *(gate: `scripts/wardryx-fails-closed.sh`: every gateway start that sets `TOKENFUSE_WARDRYX_MODE` sets
    `TOKENFUSE_WARDRYX_FAILMODE` to the literal `"closed"`; the wardryx health wait ends in `|| die`; no non-comment
    line says fail open; the wardryx block never sets `WANT_POLICY=0` after the gateway is wired to it. 9 fault
    cases and 1 pass case in `gates-have-teeth.sh`; `features/the-policy-plane-fails-closed.feature`, 6 scenarios.
    Not covered: a running gateway refusing a decision while wardryx is silent, which is tokenfuse's own test and
    needs a built gateway. Also not covered: the preflight drops wardryx before the gateway is wired to it (a busy
    port, a missing toolchain). That path is unchanged, and the gateway then has no policy plane at all.)*

21. **The gateway's admin routes need a key minted for the run, and the key is never printed.**
    `@decided 2026-10-17` (paraphrased): the admin routes include the kill switch, so each run gives its gateway
    an admin key of its own and tells the operator which file holds it. `up.sh` mints `GATEWAY_ADMIN_KEY` with
    `rand_hex 24` above the first gateway start and refuses an empty result. Each gateway start takes it as
    `TOKENFUSE_ADMIN_KEYS`, a prefix assignment ahead of `env`. The value goes to `$STACK_UP_HOME/gateway-admin.key`,
    made 0600, and the closing summary names that path and nothing else.
    `@claude 2026-10-17`: the file name, the example request and the key's length are my choices; tokenfuse's
    admin gate was read in its `adminkeys.rs` and not run here.
    *(gate: `scripts/admin-keys-are-per-run.sh`: every gateway start takes `TOKENFUSE_ADMIN_KEYS` from one run
    variable as a prefix assignment ahead of `env`; that variable is minted with `rand_hex` above the first start,
    with a refusal on empty right after; the value is written to a file that is `chmod 600`; no other non-comment
    line names it. 10 fault cases and 1 pass case in `gates-have-teeth.sh`; `features/the-admin-key-is-minted-per-run.feature`,
    6 scenarios. Not covered: a running gateway refusing a call with no key, which needs a built gateway; that the
    value is private inside a process environment (`/proc/<pid>/environ`, `ps eww`); and the `mcp-broker`
    subcommand, which is not given the key and whose own routes were not checked.)*

22. **The gateway and the MCP broker hold the postures they set, from values minted for this run.**
    `@decided 2026-10-18` (paraphrased, from the estate's posture review of 2026-10-17): the gateway
    admits only a caller that presents a client key, the gateway and the broker present an
    enforcement-point key to wardryx and never the built-in devkey, identity is enforced, and the
    broker blocks secrets in tool arguments and poisoned tools and refuses when wardryx cannot answer.
    `up.sh` mints `GATEWAY_CLIENT_KEYS` (`secret:key_id`, `rand_hex 24` above the first gateway start,
    refused when empty) and `WARDRYX_PEP_KEY` (refused when empty), gives each to every gateway start
    as a prefix assignment ahead of `env`, sets `TOKENFUSE_IDENTITY_STRICT="enforce"` on both starts,
    sets `TOKENFUSE_MCP_DLP` and `TOKENFUSE_MCP_SCAN` to `block` and `TOKENFUSE_WARDRYX_FAILMODE=closed`
    on the broker, and starts wardryx with `WARDRYX_KEYS` naming the pep key as role `pep`, with no
    `WARDRYX_ALLOW_DEVKEY`. The demo's own calls send the client secret as `x-fuse-key` on stdin (`curl -H @-`), never on a command line. The client
    secret and wardryx's admin key each go to a 0600 file, never to the terminal.
    `@claude 2026-10-18`: the key id, the file names and the explicit identity setting are my choices.
    tokenfuse's own default for identity strict is already enforce (read in `identitymap.rs` at
    origin/main, not run), so the setting here names what the default already does.
    *(gate: `scripts/postures-are-held.sh`: every gateway start takes `TOKENFUSE_CLIENT_KEYS` from one
    minted and refused run variable ahead of env, sets identity strict to enforce, and takes any
    wardryx key from a minted and refused variable; the broker start sets DLP and scan to block, and its
    wardryx array sets the closed fail mode and a minted key; no devkey literal and no
    `WARDRYX_ALLOW_DEVKEY=` outside a comment; no client key on a curl command line; wardryx's key list
    names the pep key as pep. 15 fault cases and 2 pass cases in `gates-have-teeth.sh`;
    `features/the-launcher-holds-its-postures.feature`, 9 scenarios. Not covered: a running gateway refusing a call with no key, a running wardryx refusing
    a viewer, and the broker's DLP and scan refusing a secret or a poisoned tool; these need built
    binaries. The broker's block settings were not run against typryx's own tool descriptions.)*

23. **keyryx runs per run: custody holds wardryx's approval key, the witness reads the record from its own process, and no key value leaves the launcher.**
    `@decided 2026-10-18` (paraphrased, from the agent-security review's wave 2 design): key custody
    and an independent witness of the record, both off every request path, with wardryx's approvals
    signed by custody and not by a shared secret. `@claude 2026-10-18`: the shape here is my reading of
    that decision for a launcher, not a stated decision. `up.sh` builds keyryx from the commit that
    tag and commit in the pin table names, refused unless the clone is that commit (invariant 29), because keyryx v0.1.1 publishes a
    container image and no binary and this launcher runs no containers. It mints three values per run
    above the first custody start, each refused when empty: the custody root key and the witness root
    key (`rand_hex 32`, each in its own 0600 file under `$STACK_UP_HOME/keyryx`) and the bearer key
    wardryx presents to custody (`rand_hex 24`, written with no trailing newline). The policy names one
    consumer, wardryx, by the SHA-256 of that bearer key, and one held key, `wardryx-approval`. Custody
    and the witness each get a fresh data directory, and the two directories differ. wardryx starts with
    `WARDRYX_APPROVAL_SIGNER=keyryx`, its custody URL and its key file, and without
    `WARDRYX_APPROVAL_SECRET`; the launcher refuses to start a wardryx binary that does not name the
    signer. The witness writes its alerts to its own data directory, not to the shared bus, because
    heraldyx does not render keyryx's events yet. The witness is optional and says so when it does not
    come up; custody is not, because wardryx cannot sign without it.
    *(gate: `scripts/keyryx-is-per-run.sh`: the keyryx pin is a 40-hex commit and a tag; custody and the
    witness take their data directory and root key file from run variables, and the two data
    directories differ; each root key is minted with `rand_hex` above the first custody start and refused
    when empty; the key files are written under `umask 077` and made 0600; the wardryx start names the
    keyryx signer, the custody URL and the key file, takes no approval secret, and the launcher checks the
    binary names the signer; no key value reaches a log, warn, die or echo line, a printf that is not a
    file write, or a keyryx or wardryx command line; it refuses OK when it found no custody, witness or
    wardryx start. 18 fault cases and 2 pass cases in `gates-have-teeth.sh`;
    `features/the-keyryx-custody-and-witness-run-per-run.feature`, 7 scenarios. Not covered: that a running
    custody refuses a consumer it does not know, that the witness finds a rewrite (keyryx's own tests,
    keyryx v0.1.1 `internal/witness`, and its built-binary test), and that a process keeps its key from
    the same user (`/proc/<pid>/environ` and argv are readable by that user). The launcher runs as one
    OS user, so custody and the witness are separated by process and directory only, not by uid.)*

24. **The demo issuer's trusted line ends in `|unbound`, and no other line does.**
    `@claude 2026-10-19`: vouchryx v0.5.0 refuses a subject token with no `cnf.jkt` unless its issuer
    line ends in `|unbound` (vouchryx `internal/config`, `loadTrusted`). The demo IdP sends such tokens,
    so `up.sh` writes the marker on its one trusted-issuer line, and an operator's own issuer never gets
    it. `@measured` vouchryx `main` at `a917865`, built from source into a scratch directory and started
    with the trusted line `up.sh` writes, the README's `vouchryx-demo exchange` run against it, 2026-10-19:
    with the marker absent the exchange returned HTTP 400 `invalid_grant`; with it present the exchange
    returned a token, and a revocation of the subject survived a restart of vouchryx on the same
    revocations path.
    *(gate: `scripts/demo-issuer-is-unbound.sh`, 4 cases in `gates-have-teeth.sh`. Not covered: the
    gateway rows of the README loop, a call through the gateway with the token and the 401 after the
    revocation, which need a built tokenfuse and were not run.)*

25. **The bus directory is made by this user, before any service starts, and nothing in the launcher
    hands it to another owner.** `@claude 2026-10-19`: agent-stack-go v2 creates an event stream only in
    a directory its own uid owns, and makes the file 0640 (`event/create.go`, `openAppend`). Every writer
    this launcher starts runs as the operator, so the directory `mkdir -p` makes is one each writer owns.
    A `sudo`, `chown` or `chgrp` on it would make the next writer refuse to create its stream, and that
    refusal shows only in the writer's own log. `@measured` vouchryx `main` at `a917865`, started on a
    directory `mkdir -p` made, 2026-10-19: it wrote `vouchryx.ndjson` as `-rw-r-----`, owned by the operator.
    *(gate: `scripts/bus-is-operator-owned.sh`, 5 cases in `gates-have-teeth.sh`. Not covered: the refusal
    itself, a writer asked to create a stream in a directory another uid owns, which needs a second user;
    and the 0640 mode of the other Go writers (wardryx, scopyx, costcrew, typryx, keyryx, agent-conform),
    which were not run here.)*

26. **The Cloud key stays out of URLs and out of the terminal.** `@decided 2026-10-17`
    (paraphrased, from the 2026-10-17 security review, finding F-028): a credential in a
    query string reaches the server's log, the browser history and the Referer, and a
    credential printed to a terminal reaches whatever captured it, so the cloud key is
    held in files and printed nowhere. `@claude 2026-10-19`: the mechanism is my
    reading of that decision. The dashboard link carries the key after `#key=`, a
    fragment a browser never sends to a server; the dashboard reads it first and removes
    it from the address bar on arrival (tokenfuse#469). The key and the key-bearing link
    are written to 0600 files under `$STACK_UP_HOME` (`cloud-key`, `dashboard-link`),
    each made under `umask 077`. The summary prints the link without the key, the path of
    the file that holds the key-bearing link with the one line that opens it, and the
    path of the key file.
    *(gate: `scripts/cloud-key-is-not-printed.sh`: no URL up.sh builds carries `key=` in a
    query string; no command that prints names the Cloud key or a variable derived from
    it; a link carries the key after `#key=`; every write of the key or its link to a
    file is made `umask 077` and `chmod 600` in the same statement. 8 fault cases, one
    "measured nothing" case and 2 pass cases in `gates-have-teeth.sh`; `features/the-cloud-key-stays-out-of-sight.feature`,
    7 scenarios. Not covered: that a running dashboard reads the fragment and clears the
    address bar, which is tokenfuse's own test and a browser run, not done here; that the
    loopback origin is answered by the cloud, which tokenfuse-cloud v1.19.0 does by default
    (read in its `crates/cloud/src/cors.rs`, not run here); and that the key is private
    inside a process: `/proc/<pid>/environ`, `ps eww`, and the launcher's own curl calls,
    which carry it on their command line while they run.)*

27. **The demo's calls through the gateway are made after every plane that answers them.**
    `@claude 2026-10-19`: two ordering faults made the demo's six calls answer nothing, and
    neither was loud: the stand came up, the summary said "the gateway answered nothing" and
    the dashboard showed only the seed. A gateway configured with a control plane refuses
    every call that carries a run id with `503 seed_pending` until it has read the Cloud's
    money state (tokenfuse invariant 103, `seedgate.rs`), and the Cloud was started after
    the gateway; and the gateway fails closed on wardryx (invariant 20) while the demo ran
    before wardryx started. So the Cloud starts, and is waited for, before the first gateway
    start, and `demo_traffic` runs once, after the wardryx health wait and before idryx and
    the notifier start, since they read the bus the demo fills. `@measured` `./up.sh` on a Linux
    sandbox at `dc4a137`, then with these two moves applied, reading its `governed traffic`
    line and `grep -c 'wardryx decide call failed' logs/gateway.log`, 2026-10-19: before,
    all six calls refused (503 `seed_pending` in the seed gap, then wardryx unreachable);
    after, "2 call(s) allowed, then the Breaker refused 4 with HTTP 402", and 0 wardryx
    failures in the gateway log.
    *(gate: `scripts/demo-runs-after-its-planes.sh`: the first Cloud start and its
    `wait_health cloud` come before the first gateway start; `demo_traffic` is called once,
    after `wait_health wardryx` and before `register idryx` and `register heraldyx`. 5 fault
    cases, one "measured nothing" case and 1 pass case in `gates-have-teeth.sh`. Not covered:
    the two 200s and four 402s themselves, which need built binaries and are the bring-up
    above, not a script here.)*

28. **With `--typed-risk-signal`, a brokered tool call that the signal never reaches is held, not allowed.**
    `@decided 2026-10-19`, paraphrased: the risk signal can add a hold and never a deny, and a hold that a
    silent classifier never gave is a hold too, so a call that arrives with no signal waits for a person.
    `@claude 2026-10-19`: the seeded rule and its refusals are my reading. The launcher seeds
    `stack-up-typed-risk-hold` in the wardryx policy file only under the flag: `action.risk_class` in
    destructive, external_send or financial at 0.8 or more, `when_absent: hold`, and `target: "agent://*"`,
    because a brokered call carries the broker's caller id, which is not one trust domain. It refuses,
    before wardryx starts, a wardryx binary that does not read `when_absent` (wardryx v1.4.0 and later).
    Single-use stays on: nothing sets `WARDRYX_APPROVAL_SINGLE_USE`, so one approval lifts one held call.
    *(gate: `scripts/risk-hold-is-seeded.sh`: the rule's lines, the guard that writes it only under the flag,
    the `when_absent` check and its refusal, no `when_absent` set to allow or deny, and no single-use switch
    off; `features/the-typed-risk-signal-holds-when-absent.feature`, 8 scenarios, every one bound to a case in
    `gates-have-teeth.sh`. Mutants, each caught by a named case: the `when_absent` line dropped, `when_absent`
    set to allow, the rule written without the flag, the wardryx check removed, single-use switched off, the
    threshold removed, the target narrowed to one trust domain, and the rule renamed away (measured nothing).
    Not covered: a running wardryx holding a padded call, which needs built binaries and the typryx proxy in
    front of it; wardryx v1.4.0's own tests cover the hold, and the launcher's part was not run live.)*

29. **Every component the launcher builds is a release tag, at the commit that tag names, from one table.**
    `@decided 2026-10-19`, paraphrased: a build is what a release says it is, so a component is checked out at
    a tag and its commit, and a checkout that is not that commit is refused. `@claude 2026-10-19`: the table is
    `pin_of` in up.sh; each line was read from the repository's remote tags (git ls-remote, the peeled commit)
    on that date. Every component has a release (verdryx's first, v0.1.0, since 2026-10-19), and
    `--from-main` builds sibling or main checkouts and says so at the top of the run.
    *(gate: `scripts/pins-are-release-tags.sh`: each table entry is a release tag and a full 40-hex commit,
    every component the launcher builds has an entry, locate_repo (the sibling lookup) is called only from
    pinned_repo, git clone runs only in pinned_repo and locate_repo, pinned_repo clones with `--branch` and
    refuses a HEAD that is not the pinned commit, and --from-main is a flag that says it is not a release;
    `features/every-component-is-pinned-to-a-release.feature`, 11 scenarios bound to cases in
    `gates-have-teeth.sh`. Mutants, each caught by a named case: a branch name in place of a tag, a short
    commit, a locate_repo call in the default path, the --branch dropped from the clone, the refusal made
    to accept, a clone added outside the pinned path, a component with no entry, --from-main removed, its
    warning weakened, and the table renamed away (measured nothing). Measured on this change: pinned_repo
    cloned all 14 pinned tags and each HEAD equalled its table commit; verdryx was refused; a forced
    commit mismatch was refused. Not covered: a live bring-up at the new pins (not run here), and the
    cross-version fit of wardryx v2.4.0 with keyryx v0.1.1, which only the wardryx compatibility note reads.)*

An approved architecture decision is **not finished** until it is two things: a
numbered invariant in this file, and a gate in a script if it can be checked
structurally. Until then it is a document, and documents do not stop code.

## Conventions

- **No long dashes** anywhere: not in code, docs, commit messages, or PR
  bodies. Use a comma, a colon, parentheses, or a short hyphen.
- A scenario in `features/` is bound by a `# -> gates-have-teeth.sh "<case>"`
  line under it, and `scripts/features-are-bound.sh` holds the binding both ways.
- Every component is built from its pinned release tag, from the pin table (invariant 29). `--from-main` is the developer switch to sibling or main checkouts, and it is loud. A release's new setting is
  held by checking at launch that the binary names it, never by a version number.
- Nothing paid or metered gets enabled without telling the user first and
  getting agreement.
- Do not delete or revoke keys, tokens, or certificates on your own initiative.
