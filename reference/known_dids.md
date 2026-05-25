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

- `791/0026` — Odometer — km — baseline
- `791/0038` — Power-A — kW magnitude (unsigned) — baseline

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
