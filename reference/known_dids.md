# Known DIDs (confirmed semantics)

Source-of-truth list of DIDs whose semantics are confirmed.
Bootstrap from `bz5-companion/lib/data/ecu_registry.dart` as of
2026-05-25; cycle column shows where confirmation came from (or
"baseline" for pre-research knowledge).

Each row entry: `ECU/DID — name — unit — scale/offset — confirmed-in`.

## BMS (790/798)

- `790/0005` — SOC — % — raw — baseline
- `790/0029` — SOH — % — raw — baseline
- `790/002F` — Battery temp — °C — offset −40 — baseline
- `790/002B` — Cell V min — mV — 2 bytes — baseline
- `790/002D` — Cell V max — mV — 2 bytes — baseline
- `790/0015` — HV bus voltage — V — scale ×0.025, 2 bytes — baseline
- `790/0006` — Power rated — ×0.1 kW — scale 0.1 — baseline
- `790/0008` — Current limit — ×0.1 A — scale 0.1 — baseline
- `790/0009` — Energy counter — unconfirmed scale — baseline
- `790/000A` — Counter A — unconfirmed scale — baseline
- `790/0B00` — Total energy 1 — unconfirmed semantics — baseline
- `790/0B01` — Total energy 2 — unconfirmed semantics — baseline
- `790/0B02` — Cycle count — confirmed (used in app UI) — baseline
- `790/1FFD` — SOC precise (×0.01) — % — high16/100 — baseline
- `790/1FFE` — Platform counter — high16=platform const, low16=slow counter — baseline
- `790/016D-01B7` — Module cell voltages and temps — see ecu_registry header — baseline

## VCU (791/799)

- `791/0026` — Odometer — km — baseline (re-confirmed in cycle 001 as `000070CD` = 28877; scale TBD — likely 1 km giving 28877 km, but could be 0.1 km giving 2887.7 km)
- `791/0038` — Power-A — kW magnitude (unsigned) — baseline (re-confirmed in cycle 001 as `0326` = 806 in idle Ready, unit TBD — likely W)

### VCU low-byte landscape (cycle 001 observations, semantics TBD)

Cycle 001 swept 0x0001-0x00FF on VCU. Results stored in
`cycles/001-vcu-low-scan/`. Summary:

- 255 of 255 DIDs returned positive UDS response (no NRC)
- **204 DIDs returned `62 XX XX` with zero payload** — unusual; not
  proof of DID existence in the operational sense
- 51 DIDs returned non-zero payload, broken down by width:
  - 1 byte: 26 DIDs (mostly flags/enums)
  - 2 byte: 13 DIDs (counters, small values, including 0038/0039)
  - 4 byte: 10 DIDs (counters, odometer at 0026, non-zero pair at 004A/004B)
  - 7 byte: 1 DID (0056, all zero in idle)
  - 10 byte: 1 DID (0049, structured FF-pattern)

DIDs flagged for follow-up in cycle 002 differential sweep:
- `0x0038/0x0039` — adjacent 2-byte pair, ratio ≈ 2× in idle
- `0x0043/0x0044/0x0045` — three 1-byte values 40/27/27 — plausibly temperatures °C
- `0x004A/0x004B` — 4-byte non-zero, dynamic candidates
- `0x0046/0x0047/0x0048/0x004C/0x004D/0x004E` — 4-byte zero in idle, could mask pack-current-near-zero
- `0x0025/0x0036/0x0037/0x0040/0x0041/0x0042` — 2-byte zero in idle, similar candidates

## PDU / HV Junction (740/748)

- `740/0008` — Vehicle speed — km/h — baseline (used in trip aggregates)

## OBC (782/78A)

(No specific DIDs documented in registry; ECU is listed but DIDs TBD.)

## GPS (757/75F)

(DIDs documented in `gpsEcu` section of registry; not relevant to
energy investigation.)

## Open questions

These are gaps the research aims to fill:

1. **Pack current** — not in any known DID. Suspected in VCU (791),
   PDU (740), or one of the BMS slaves (750-756).
2. **Per-subsystem energy split** — drivetrain, HVAC compressor, PTC
   heater, DC-DC converter (12V aux). No DIDs confirmed for any of these.
3. **0B00 / 0B01 semantics** — registry calls them "Total energy 1/2"
   but the actual decoding is unknown. May or may not relate to (2).
4. **HVAC ECU identity** — no HVAC ECU tx/rx pair documented. Either
   responds on an undiscovered ID, or HVAC state is in VCU/PDU but
   under a DID we haven't read, or the climate system uses HAL not OBD.

## Server-side schema reference

For analysis.md writers consuming raw/sweep_results.csv:

**sweep_runs columns**: `id, device_id, vehicle_id, client_sweep_id,
started_at, ended_at, tx_ecu, rx_ecu, start_did, end_did, period_ms,
car_state, notes, total_probes, valid_responses, received_at`.
Unique on `(device_id, client_sweep_id)`.

**sweep_results columns**: `id, sweep_run_id, did, raw_hex, error_code,
sequence`. Indexed on `(sweep_run_id, sequence)`.

Derived semantics:
- **Success**: `raw_hex IS NOT NULL` (ECU returned bytes).
- **ECU error**: `error_code IS NOT NULL` (UDS NRC like 7F / 31 / 22).
- **Skipped / timeout**: both NULL.
- **Per-DID timestamp** is not stored; reconstruct as
  `sweep_runs.started_at + (sequence - 1) × period_ms`. Sufficient for
  baseline analysis. For precise timing → use live_log_entries instead.

When filtering responding DIDs: `WHERE raw_hex IS NOT NULL`.
