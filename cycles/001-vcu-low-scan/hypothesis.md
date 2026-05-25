# Cycle 1 — VCU low-byte sweep

**Date issued**: 2026-05-25 (retroactive — bridge Claude proceeded
without my hypothesis.md as the parameters were transmitted in the
chat message; this file is reconstructed for archival completeness)
**Hypothesis target**: pack-current / energy-related DIDs in VCU
**Prerequisite cycles**: none (this is the first cycle)

## Hypothesis

Pack-current DID, lifetime energy counters, and/or derived power
metrics live in VCU (ECU 791) in the neighbourhood of already-known
`0x0026` (odometer) and `0x0038` (power-A magnitude). VCU is by
architecture the central coordinator of the powertrain — it must
know pack current internally to compute power, so it likely also
exposes that current as a readable DID somewhere.

The hypothesis is deliberately about *existence in this range*, not
about specific DID positions. A blanket scan of 0x0001-0x00FF is
cheap (~80-100 seconds BLE time) and reveals the entire low-byte
landscape, after which targeted follow-up is possible.

## Predictions

If the hypothesis is correct, we expect to see:
- DID `0x0026` (odometer) responds — baseline sanity
- DID `0x0038` (power-A) responds — baseline sanity
- At least one *additional* DID with a 2- or 4-byte payload that
  could plausibly carry a signed/unsigned current value, energy
  counter, or related field

If the hypothesis is wrong, alternatives are:
- Pack current lives in BMS (ECU 790) — H1 from `reference/ecu_map.md`
- Pack current lives in PDU (ECU 740) — H3
- Pack current is on a different ECU entirely (motor controllers,
  inverter group)

## Experiment

Single sweep of VCU low-byte range. See `command.json` for the
actual POSTed body (bridge Claude provided the canonical record).

Key parameters:
- `tx_ecu: "791"`, `rx_ecu: "799"`
- DID range: `0x0001` to `0x00FF`
- `period_ms: 250` (requested)
- `car_state: "ready_idle_climate_off"`
- `timeout_ms: 120000`

## Branching plan

| Outcome | Implication | Next cycle direction |
| ------- | ----------- | -------------------- |
| A | Unknown 2- or 4-byte DIDs with current-like signature respond | Live log those during controlled drive (idle/cruise/regen) |
| B | Only known DIDs respond, nothing else interesting | BMS (790) low-byte sweep, hypothesis pivots |
| C | Mostly errors / no response | Infrastructure issue, verify BLE pair |

## Constraints / prerequisites

- Car: Ready ON, parked, climate OFF (minimise background load so any
  current/power readings reflect a clean idle state)
- BridgeDiag toggle ON, long-poll alive on the head unit
- `bz5-companion` v0.1.29+20 installed
