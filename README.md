# stack-up

Run the open [TAIPANBOX](https://github.com/TAIPANBOX) agent-governance stack on
your own machine, natively, with no Docker, and look at it in a browser.

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
| tokenfuse-gateway | 4100 | Budget-enforcement proxy. OpenAI-compatible: point an agent's base URL here and every call is metered, and an over-budget one gets a hard 402. |
| tokenfuse-cloud | 8080 | The money-plane control API (runs, budgets, savings, incidents). Started with a dev credential (see below). |
| dashboard | 3000 | The money-plane dashboard, a static page served locally. This is the thing you actually look at. |
| wardryx | 8090 | Policy decision point, seeded with a tiny demo policy scoped to fire-drill identities only. |
| idryx | 8081 | Identity/access graph, built from the event stream. Its own default `:8080` collides with cloud, so stack-up runs it on `:8081`. |

The money plane (gateway + cloud + dashboard) is mandatory; the rest degrade
gracefully. If a toolchain or a port is missing, stack-up says so and brings up
what it can, rather than failing the whole run.

## Requirements

- **git** and **curl**.
- **Rust** (stable, via [rustup](https://rustup.rs)) - tokenfuse is built from source.
- **Node** and **npm** - only for the dashboard (a one-time static build).
- **python3** - only to serve the dashboard.
- **Go** - only for wardryx and idryx. Skip them with `--only money`.

The first run builds tokenfuse in release mode and can take several minutes.
After that, builds are cached and startup is seconds. Everything after the
initial build and clone works offline.

If you already have sibling checkouts of these repos next to `stack-up`,
it reuses them (it only reads them and runs their own build tool; it never
modifies them). Otherwise it shallow-clones what it needs into `~/.stack-up/`.

## What you are looking at

The money plane has two independent faces, and stack-up runs both:

- The **gateway** (`:4100`) is the live enforcement proxy. Point an
  OpenAI-compatible client at it and every call is metered against a per-run
  budget, with a hard 402 when it is spent. Its own view is `GET :4100/v1/runs`.
- The **cloud** (`:8080`) is the aggregate control plane, and the **dashboard**
  reads from it. Cloud is populated by anything posting call records to its
  ungated `POST /v1/ingest` (that is how the mobile app and real reporters feed
  it). The gateway does not auto-report to cloud; they are separate planes on
  purpose.

So the dashboard shows whatever has been ingested into cloud. To keep it from
starting empty, stack-up seeds a short, clearly-labeled demo dataset (two runs
under `agent://demo.local/*`); pass `--no-demo` to skip it. Cloud runs
in-memory here, so that seed is fresh every run and nothing is written to disk.

To push your own data, POST call records to cloud:

```sh
curl -X POST http://127.0.0.1:8080/v1/ingest \
  -H 'authorization: Bearer devkey' \
  -H 'content-type: application/json' \
  -d '{"records":[{"run_id":"my-run","model":"gpt-4o-mini","cost_microusd":4200,"input_tokens":900,"output_tokens":300,"agent_id":"agent://acme.local/support/bot"}]}'
```

Refresh the dashboard and your run is there. To exercise the gateway's live
enforcement instead, send OpenAI-compatible traffic to `:4100` with an
`x-fuse-run-id` and `x-fuse-budget-usd` and watch it 402 when the budget runs
out (see the [tokenfuse README](https://github.com/TAIPANBOX/tokenfuse) for
wiring a real upstream).

## Options

```
--only money       just the money plane (gateway + cloud + dashboard)
--no-dashboard     skip building and serving the dashboard
--no-demo          do not seed the short demo dataset into cloud
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

State lives under `~/.stack-up/` (override with `STACK_UP_HOME`):

```
~/.stack-up/
  bin/         cached built binaries + staleness markers
  repos/       repos stack-up cloned itself (absent if you use sibling checkouts)
  events/      the NDJSON event stream the services write and read
  logs/        one log file per service
  pids/        recorded PIDs, used by down.sh
```

## License

Apache-2.0. See [LICENSE](LICENSE).
