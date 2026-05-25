# bz5-research

Iterative reverse-engineering log for the Toyota BZ5 vehicle ECU
landscape. Used to identify undocumented DIDs that enable better
telemetry in the `bz5-companion` Flutter app — primarily a per-trip
energy breakdown (drivetrain / HVAC / auxiliary).

## Roles

| Role | Who | What |
| ---- | --- | ---- |
| Owner | Human | Drives the car, sets car state for experiments, approves direction, copies data between Claudes |
| Friend 1 (companion Claude) | Claude session | Formulates hypotheses, designs sweep / live-log experiments, analyzes returned data, plans next cycle |
| Friend 2 (bridge Claude) | Server-side Claude session | Executes admin commands against the long-poll command queue, exports results from Postgres to this repo |

The companion Flutter app on the head unit hosts `BridgeDiagService`,
which long-polls `/v1/commands/next` and executes received commands
(`bleStartSweep`, `bleStartLiveLog`, `bleStopActiveOperation`)
against the car over BLE.

Friend 2 issues commands by `POST /v1/admin/commands`. Friend 1 reads
the resulting data from this repo (via `raw.githubusercontent.com`
URLs the Owner pastes into the chat).

## Process per cycle

Each investigation cycle lives in its own subdirectory under
`cycles/NNN-short-slug/`. The shape of a cycle is:

1. **`hypothesis.md`** — what Friend 1 thinks and why, before issuing
   any command. Includes branching plan: what does each possible
   result imply for the next cycle?
2. **`command.json`** — the exact admin command body that was POSTed.
3. **`raw/`** — unmodified data dumps from Postgres. CSV or JSON,
   produced by Friend 2 via `\copy` or `jq`. No editorial intervention.
4. **`analysis.md`** — Friend 1's interpretation after seeing `raw/`.
   Identifies candidates, flags anomalies, decides next direction.
5. **`next.md`** — the seed of the next cycle's `hypothesis.md`.
   Written at the end of analysis so the chain is unbroken.

## Living documents (root level)

- **`reference/known_dids.md`** — every DID with confirmed semantics,
  by ECU. Each entry has a one-line summary + the cycle that confirmed
  it. Single source of truth that `bz5-companion/lib/data/ecu_registry.dart`
  should track (out-of-band, owner copies updates by hand).
- **`reference/ecu_map.md`** — table of all ECU tx/rx ids encountered,
  with role hypotheses. Updated as we explore.
- **`reference/decoded_semantics.md`** — longer-form writeups for
  DIDs whose decoding required multiple cycles to confirm.

## File naming

- Cycles are zero-padded to 3 digits: `cycles/001-vcu-low-scan/`.
- Slugs are short and descriptive: ECU + scan-type or hypothesis.
- Raw data filenames mirror the SQL table they came from:
  `sweep_results.csv`, `live_log_entries.csv`, `sweep_runs.csv`.
- When the same cycle has multiple raw exports
  (e.g. baseline + repeat at different car state), suffix with
  state: `sweep_results.parked-climate-off.csv`,
  `sweep_results.driving-climate-on.csv`.

## What this repo is NOT

- Not a code repo. No source, no builds. Code lives in
  `bz5-companion` (Flutter client) and the server (Friend 2's repo).
- Not a complete OBD-2 reference. We document only what BZ5 actually
  exposes. UDS spec stays the spec.
- Not authoritative for production behavior — only for what we have
  observed. Confirmed DIDs migrate from here into
  `bz5-companion/lib/data/ecu_registry.dart` after they prove out.

## License

Public domain / CC0. This is reverse-engineering knowledge about a
mass-produced car; it benefits future BZ5 owners and other tooling
projects.
