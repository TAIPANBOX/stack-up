# stack-up

Run the open [TAIPANBOX](https://github.com/TAIPANBOX) agent-governance stack on
your own machine, natively, with no Docker, and look at it in a browser.
The stack's home on the web is [it-rat.com](https://it-rat.com).

One command builds (or reuses) the service binaries from source, starts them on
a fixed loopback port map, waits for each to report healthy, and prints a
one-click link to the money-plane dashboard. Press Ctrl-C and it stops cleanly,
with no orphaned processes.

```sh
git clone https://github.com/TAIPANBOX/stack-up
cd stack-up
./up.sh
```

Then open the link it prints (something like
`http://127.0.0.1:3000/?base=http://127.0.0.1:8080&key=devkey`) and you are
looking at your own local money plane.

## What it starts

Everything binds to `127.0.0.1` only.

| Service | Port | What it is |
|---|---|---|
| tokenfuse-gateway | 4100 | Budget-enforcement proxy for the Anthropic Messages API (`/v1/messages`): point an agent's base URL here and every call is metered, and an over-budget one gets a hard 402. |
| tokenfuse-cloud | 8080 | The money-plane control API (runs, budgets, savings, incidents). Started with a dev credential (see below). |
| dashboard | 3000 | The money-plane dashboard, a static page served locally. This is the thing you actually look at. |
| wardryx | 8090 | Policy decision point, seeded with a tiny demo policy scoped to fire-drill identities only. |
| idryx | 8081 | Identity/access graph, built from the event stream. Its own default `:8080` collides with cloud, so stack-up runs it on `:8081`. |

The money plane (gateway + cloud + dashboard) is mandatory; the rest degrade
gracefully. If a toolchain or a port is missing, stack-up says so and brings up
what it can, rather than failing the whole run.

## What it installs but does not start

Four of the stack's tools are not servers. `qryx` scans a path and exits.
`mockryx` fires crafted requests at a gateway you name and exits. `engram` is a
library, a CLI, and a stdio-only MCP server over a local file. `verdryx` is a
CLI over a local file. There is no port to connect to and nothing to keep
running, so for these "up" means something different:

| Tool | Installed as | Store |
|---|---|---|
| qryx | `~/.taipan/bin/qryx` | none, scans on demand |
| mockryx | `~/.taipan/bin/mockryx` | none, runs on demand |
| engram | `~/.taipan/bin/engram-mcp` | `~/.taipan/engram.engram` |
| verdryx | `~/.taipan/bin/verdryx` | `~/.taipan/verdryx.db` |

`~/.taipan` rather than `~/.stack-up` because that is where the rest of the
stack looks. It is a fixed path, not a search: `qryx` in particular is looked up
at exactly `~/.taipan/bin/qryx`, with no environment variable and no `PATH`
fallback, so a binary installed anywhere else is a binary nothing can find.

The two stores are created **empty** and are never seeded. They are files on
disk that other tools read as real data, so demo rows in them would be
indistinguishable from your own, forever. The money plane's demo dataset is
different and stays on by default: it lives in a process that keeps it in
memory and forgets it on exit.

stack-up is not the only writer of `~/.taipan/bin` - the `taipan` deploy CLI
installs the same binaries there. It records a checksum of everything it
installs, so on a later run it refreshes its own files and leaves anyone else's
alone, saying so. `--force-install` overrides that.

Skip this whole section with `--no-tools`.

## Requirements

- **git** and **curl**.
- **Rust** (stable, via [rustup](https://rustup.rs)) - tokenfuse is built from source.
- **Node** and **npm** - only for the dashboard (a one-time static build).
- **python3** - to serve the dashboard, and to install engram and verdryx into
  their own virtualenvs (3.11+ for those two).
- **Go** - for wardryx, idryx, mockryx and qryx. Skip them with `--only money`.
  qryx pins a newer Go toolchain than the others and downloads it on the first
  build; that is automatic, and slow exactly once.

The first run builds tokenfuse in release mode and can take several minutes.
After that, builds are cached and startup is seconds. Everything after the
initial build and clone works offline.

If you already have sibling checkouts of these repos next to `stack-up`,
it reuses them (it only reads them and runs their own build tool; it never
modifies them). Otherwise it shallow-clones what it needs into `~/.stack-up/`.

## What you are looking at

The money plane has two independent faces, and stack-up runs both:

- The **gateway** (`:4100`) is the live enforcement proxy. Point an Anthropic
  Messages API client at it (`POST /v1/messages`) and every call is metered
  against a per-run budget, with a hard 402 when it is spent. Its own view is
  `GET :4100/v1/runs`.
- The **cloud** (`:8080`) is the aggregate control plane, and the **dashboard**
  reads from it. Cloud is populated by anything posting call records to its
  ungated `POST /v1/ingest`. stack-up points the gateway at cloud, so your live
  traffic through `:4100` shows up on the dashboard on its own; the mobile app
  and other reporters feed the same endpoint.

So the dashboard shows whatever has been ingested into cloud, your own gateway
traffic included. So a first look is not empty before you have sent any,
stack-up also seeds a short, clearly-labeled demo dataset (two runs under
`agent://demo.local/*`); pass `--no-demo` to skip it. Cloud runs in-memory
here, so that seed is fresh every run and nothing is written to disk.

To push your own data, POST call records to cloud:

```sh
curl -X POST http://127.0.0.1:8080/v1/ingest \
  -H 'authorization: Bearer devkey' \
  -H 'content-type: application/json' \
  -d '{"records":[{"run_id":"my-run","model":"gpt-4o-mini","cost_microusd":4200,"input_tokens":900,"output_tokens":300,"agent_id":"agent://acme.local/support/bot"}]}'
```

Refresh the dashboard and your run is there. To exercise the gateway's live
enforcement instead, send Anthropic Messages API traffic to `:4100` with an
`x-fuse-run-id` and `x-fuse-budget-usd` and watch it 402 when the budget runs
out (see the [tokenfuse README](https://github.com/TAIPANBOX/tokenfuse) for
wiring a real upstream).

## Options

```
--only money       just the money plane (gateway + cloud + dashboard)
--no-dashboard     skip building and serving the dashboard
--no-demo          do not seed the short demo dataset into cloud
--no-tools         skip the four installed-not-started tools
--force-install    replace binaries another tool installed
--workspace <dir>  look here for sibling checkouts before cloning
-h, --help         show help
```

## Stopping

Run it in the foreground and Ctrl-C stops everything. If you background it
(`./up.sh &`), stop it later with:

```sh
./down.sh
```

`down.sh` only signals the PIDs `up.sh` recorded when it launched each service.

## Scheduled governance runs

The stack produces governance signal on its own, but nobody looks at it
unless something runs it on a schedule. `routines.sh` is that schedule: it
installs OS-native timers (systemd on Linux, launchd on macOS) for five
routines, and it is also the thing those timers invoke.

| Routine | Runs (local time) | What it does |
|---|---|---|
| `focus-export` | daily 06:07 | `tokenfuse-gateway focus-export` -> a FOCUS-format FinOps CSV built from the gateway's own trace. |
| `qryx-trend` | daily 06:17 | `qryx scan` (saving evidence) then `qryx trend` -> crypto-inventory compliance-score history. |
| `verdryx-drift` | daily 06:27 | `verdryx drift` against a baseline you set -> a quality-regression check. |
| `idryx-detect` | daily 06:37 | `idryx detect` over the tokenfuse event stream -> an identity/access anomaly sweep. |
| `mockryx-drill` | weekly, Monday 06:47 | a live fire drill against your own gateway. **Opt-in only** - see the warning below. |

```sh
./routines.sh list                  # one line per routine: installed? last run?
./routines.sh run <name>            # run one now (this is what the scheduler calls)
./routines.sh install               # install timers for the four safe routines
./routines.sh install --with-drill  # also install the weekly drill (see the warning below)
./routines.sh uninstall             # remove exactly and only what install created
./routines.sh status                # last record per routine, plus the scheduler's own view
```

Each routine checks its own preconditions first - the binary it needs, the
store or file it reads, any required config - before doing anything. A
precondition that is not met is recorded as `skipped` with the exact reason
and is not a failure: that is the expected state right after a fresh
install, before you have pointed it at real binaries and data. Once those
exist, it runs for real.

### Config

An optional shell fragment at `~/.stack-up/routines/config`, sourced if
present:

```sh
ROUTINE_QRYX_SCAN_PATH=/path/to/scan        # qryx-trend's scan target (default: repos/ under STACK_UP_HOME)
ROUTINE_VERDRYX_BASELINE=some-baseline-id   # required for verdryx-drift; unset means it stays skipped
ROUTINE_VERDRYX_WINDOW=5                    # verdryx-drift's --window (default: 5)
ROUTINE_DRILL_SCENARIOS=/path/to/scenarios  # mockryx-drill's scenarios directory
```

### The record

Every run is recorded twice: appended as one line to
`~/.stack-up/routines/history.ndjson` (the full history), and written
atomically to `~/.stack-up/routines/status/<name>.json` (just the latest).
Both use the same shape:

```json
{"schema":"stackup.routine-run/v1","routine":"<name>","started_at":"<RFC3339 UTC>","finished_at":"<RFC3339 UTC>","exit_code":N,"status":"ok|findings|skipped|error","reason":"<only for skipped/error>","artifact":"<path under out/, when produced>","summary":"<one line>"}
```

This is a **stable contract**: the Genaryx console reads it, so its shape
does not change casually. `status` is one of `ok` (ran, nothing wrong - this
includes a routine that found something, since finding it is the point of
running it), `findings` (mockryx-drill specifically: it found a gap, which
is what a drill is for), `skipped` (a precondition was not met - see
`reason`), or `error` (a real usage/tool failure - see `reason`).

### The mockryx-drill warning

`mockryx-drill` is never installed by default. `install --with-drill`
prints this, first, before it installs anything:

Its weekly timer sends real traffic through your local gateway to whatever
LLM provider is configured there. That traffic can spend that provider's
money, and the drill is deliberately built to trip your policies - that is
what a fire drill is for.

### A note on clocks

The timers fire in whatever time zone the OS scheduler uses: local time, on
the machine's own clock. Every timestamp inside a recorded run
(`started_at`, `finished_at`) is UTC. If the machine's local time zone is
not UTC, "06:07 local" and the UTC timestamp on that run's record will not
line up numerically - that is expected, not a bug.

## This is a sandbox, not a deployment

- Every service binds to loopback only. Nothing is exposed off your machine.
- `cloud` runs with `TOKENFUSE_CLOUD_ALLOW_DEVKEY=1` and an empty key set, which
  activates the literal bearer `devkey`. That is a **dev credential for a local
  sandbox** and nothing else. Do not run this on a host anything else can reach.
- `idryx serve` has no authentication of its own by design (loopback only).
- There is no telemetry. The only network access is cloning the repos and
  fetching build dependencies.

This exists so you can try the whole open stack in a couple of minutes and see
how the pieces fit. For a real, governed, self-hosted deployment - keys, remote
reachability, policy you actually wrote - follow each service's own README.

## Layout

Two directories, with a clear split: one is the stack's, one is this script's.

Installed artifacts go to the stack's own home, `~/.taipan/`, because that is
where every other part of the stack looks for them. `taipan` writes here too.

```
~/.taipan/
  bin/              the built binaries, and the tool entry points
  venv/             the virtualenvs engram-mcp and verdryx run out of
  engram.engram     the memory store (created empty, never seeded)
  verdryx.db        the quality store (created empty, never seeded)
```

Everything that is only stack-up's business stays under `~/.stack-up/`
(override with `STACK_UP_HOME`):

```
~/.stack-up/
  build/       where a build lands before it is installed
  markers/     staleness stamps + a checksum of each file stack-up installed
  repos/       repos stack-up cloned itself (absent if you use sibling checkouts)
  events/      the NDJSON event stream the services write and read
  logs/        one log file per service
  pids/        recorded PIDs, used by down.sh
```

Earlier versions kept the binaries in `~/.stack-up/bin`. They are moved on the
next run rather than rebuilt, and the old directory is left empty.

`down.sh` stops processes; it is not an uninstall. Nothing under `~/.taipan/` is
removed by it, deliberately: those binaries and stores may be in use by
something stack-up did not start.

## License

Apache-2.0. See [LICENSE](LICENSE).
