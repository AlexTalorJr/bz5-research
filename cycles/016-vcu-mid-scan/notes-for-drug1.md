# C13-C16 batch — Pack-Current Hunt Sweeps — Notes for Друг 1

**Date**: 2026-05-27 (UTC)
**Bridge cycles**: 13, 14, 15, 16
**Operator**: bridge Claude (Друг 2)
**Client**: bz5-companion **`0.1.29+26`** (first cycles on +26 — see *Client version note* below)
**Car state**: `parked_ready_off` throughout (~12 minutes total)
**This file lives in cycle 016 because the four batch cycles are delivered together; commit hashes per cycle below.**

---

## TL;DR

| C | ECU | Range | rows | valid/total | One-line verdict |
|---|---|---|---|---|---|
| 13 | 750/758 BMS slave | 0001-00FF | 230 | 0/255 | ECU alive, range NRCs (`7F2231` on 224/230) — slave is gated on subFunction, not DID range |
| 14 | 715/71D HV Junction | 0001-00FF | 53 | 0/255 | ECU **gave up at DID 0035** — first 53 DIDs returned `EMPTY` (transport-empty / timeout), DIDs 0036-00FF got no response at all |
| **15** | **790/798 BMS master mid** | **0100-01FF** | 256 | **81/256** | **Real find** — 60 zero-byte exposed DIDs + 20 single-byte per-cell-module values + 1 ASCII part number |
| 16 | 791/799 VCU mid | 0100-01FF | 39 | 12/256 (client says 0) | Only 12 DIDs alive total, mostly zero-byte; 1 ASCII part number; rest are `7F2201` GeneralReject |

**Headline**: BMS master `790/798` has a **regular per-module telemetry structure at 0x016D-0x01B7** with stride 8: every module exposes a pair `(...D, ...F)` returning single-byte values. **10 modules × 2 DIDs = 20 responses**, values clustered `0xD5..0xDA` (213-218). With car parked/ready-off, no current flowing → these are likely either per-cell voltage offsets, per-cell temperatures, or SoC slices. **Needs a livelog under varying current to confirm what moves.**

**No 4-byte signed-int candidates anywhere** in 13-16. The pack-current signed-current hypothesis didn't fire in mid-byte range. Either it lives in `0x0Bxx` (Toyota aggregate convention — not yet swept on 790) or on an ECU we excluded (motor controllers are security-locked).

---

## C13 — BMS slave 750/758 0x0001-0x00FF

```
sweep_runs id=7 → DELETEd after \copy (Друг 2's collision-avoidance pattern)
client_sweep_id=1 (first sweep after +26 install — client counter started fresh)
total_probes=255, valid_responses=0, csv_rows=230 (25 DIDs got no response at all)
commit 223cc06
```

### Findings
- **224 of 230 responses are NRC `7F2231`** (subFunctionNotSupported, sid=0x22)
- 6 responses parse as "valid" by bridge but are empty/single-byte:
  - 2× 0-byte: `62 00 XX YY` echo with no payload
  - 4× 1-byte
- Interpretation: BMS slave 750 is **alive at the UDS layer** (responds to all queries) but **subFunction 0x22 (ReadDataByIdentifier) gates this DID range**. This is consistent with Toyota's typical pattern: slaves only expose data via Plus subFunction or a different SID; the master is the read-target for diagnostics.

### Friend-1 checklist
- 4-byte signed: none
- High-variance 2/4-byte: none (single sweep, no variance probe)
- 0x0B00+ aggregate: not in range
- ASCII strings: none

### Suggested follow-up
Probably not worth more time on 750 unless we suspect a subFunction-based read (e.g., ReadDataByLocalIdentifier 0x21) is the access method. Move on.

---

## C14 — HV Junction 715/71D 0x0001-0x00FF

```
sweep_runs id=8 → DELETEd after \copy
client_sweep_id=2
total_probes=255, valid_responses=0, csv_rows=53 (202 DIDs got no response at all)
commit 82b959e
```

### Findings
- 53 of 53 responses have **`error_code='EMPTY'`** (a NEW error code I had not seen before — see *Client version note*)
- `EMPTY` means: client sent the UDS request, but received no UDS response data — likely a transport-level timeout or an empty PDU. Distinct from `7F2231` (explicit NRC).
- The 53 entries cover DIDs **0001-0035 only**. After 0x0035 the ECU went **completely silent** — neither client nor bridge recorded those DIDs.
- Interpretation: HV Junction 715 either (a) sleeps through this UDS query type and BLE timed out, (b) crashed after DID 0x0035, or (c) routing on the K2/CAN gateway is broken for this range.

### Friend-1 checklist
- 4-byte signed: none
- High-variance: none
- 0x0B00+: not in range
- ASCII: none

### Suggested follow-up
- Worth a retry with extended per-DID timeout to distinguish (a) vs (b).
- OR target this ECU with a narrow probe at DIDs we know other Toyota HVJB units expose (status flags, contactor states).
- The fact that 53 DIDs responded `EMPTY` rather than `7F2231` is itself notable — most ECUs return NRCs for unsupported DIDs. `EMPTY` suggests no response at all, which feels like a gateway / routing issue.

---

## C15 — BMS master 790/798 0x0100-0x01FF (**main find**)

```
sweep_runs id=9 → DELETEd after \copy
client_sweep_id=3
total_probes=256, valid_responses=81, csv_rows=256 (no DIDs silent — every probe got a response or NRC)
commit 55b4a4e
```

### Findings — payload size distribution of the 81 valid responses

| Payload bytes | Count | Notes |
|---|---|---|
| 0 (echo only) | 60 | DID exposed, no data — likely "settable" or "stub" DIDs |
| 1 | 20 | **The per-module pattern — see below** |
| 16 | 1 | ASCII part number — see below |

The remaining 175 of 256 = `7F2231` NRC. No 2-byte, no 4-byte payloads anywhere in mid-byte.

### **Per-module structure at 0x016D-0x01B7**

10 module pairs at fixed stride 8:

| Module idx | DID `...D` | value | DID `...F` | value |
|---|---|---|---|---|
| 0 | `016D` | 0xD6 (214) | `016F` | 0xDA (218) |
| 1 | `0175` | 0xD6 (214) | `0177` | 0xD8 (216) |
| 2 | `017D` | 0xD6 (214) | `017F` | 0xD9 (217) |
| 3 | `0185` | 0xD6 (214) | `0187` | 0xD9 (217) |
| 4 | `018D` | 0xD6 (214) | `018F` | 0xD8 (216) |
| 5 | `0195` | 0xD6 (214) | `0197` | 0xD8 (216) |
| 6 | `019D` | 0xD6 (214) | `019F` | 0xDA (218) |
| 7 | `01A5` | 0xD5 (213) | `01A7` | 0xD8 (216) |
| 8 | `01AD` | 0xD6 (214) | `01AF` | 0xD8 (216) |
| 9 | `01B5` | 0xD6 (214) | `01B7` | 0xD9 (217) |

Between these "live" DIDs, **60 zero-byte DIDs** fill the gaps (e.g., `016C`, `016E`, `0170-0174`, `0176`, …) — these may be **read-modify-write parameters** the master exposes for tuning each module.

Total: 10 modules visible. If BZ5 has 10 module groups, this matches. If it has more, this is a window into a subset.

### **DID 0x0105 = 16-byte ASCII part number `'960003011       '`**

Toyota part-number convention (8 + padding). This is the BMS master's own part number. Worth cataloguing in `reference/decoded_semantics.md`.

### Friend-1 checklist
- **4-byte signed**: NONE in this range. Pack-current is not at `0x01xx` on the master.
- **High-variance**: can't tell from single static sweep — needs a livelog.
- **0x0B00+ aggregate**: not in range; **suggest C18 sweep `790/798 0B00-0BFF`** as the next logical hunt for energy accumulators.
- **ASCII strings**: 1 — `'960003011       '` at DID 0x0105.

### Suggested follow-ups
1. **Livelog the 10 module pairs under load** — does anything in 0xD5-0xDA region swing under throttle / regen? If yes, these are per-cell currents or voltages.
2. **Probe the 60 zero-byte DIDs with writes** to see which are parameters. (Defer — risk.)
3. **Sweep `790/798 0x0B00-0x0BFF`** for aggregates. None of the candidates we know would live there yet.
4. **What do these `0xD5..0xDA` values represent?** Hypothesis: 8-bit packed offsets from a base (e.g., `cellV = 3.500 + value × 0.005` → 4.565-4.590V — too high). Or per-cell temps °C (213-218°C — physically impossible). Or 1/2 cell mV offset from a 3.7V base (3.700 + 213/1000 → 3.913V — plausible). Or just SoC: `214 × 0.5% = 107%` — no. **Most plausible**: per-cell mV offset from a 3.7V base.

---

## C16 — VCU 791/799 0x0100-0x01FF

```
sweep_runs id=10 → DELETEd after \copy
client_sweep_id=4
total_probes=256, valid_responses=0 (client's count), csv_rows=39 (12 of which look "valid" to me, see below)
commit a5aa4a1
```

### Findings
- 12 responses had no error code; the bridge's `valid_responses` count says 0 — **possible client-side discrepancy** in how `valid` is computed (the client may treat 0-byte payloads as invalid).
- 7× zero-byte payloads at DIDs 0100, 0103, 0107-010B
- 4× single-byte payloads:
  - DID 0101: `00`
  - DID 0102: `00`
  - DID 0104: `88` (uint8=136)
  - DID 0106: `00`
- 1× 16-byte ASCII at DID 0x0105: `'998103030       '` — the VCU's own part number, **different from the BMS master's** at the same DID.
- Remaining 27 are `7F2201` (GeneralReject, sid=0x22) — VCU rejects mid-byte reads outside its narrow exposed set.

### Friend-1 checklist
- 4-byte signed: none
- High-variance: n/a
- 0x0B00+: not in range
- ASCII: 1 — VCU part number `'998103030       '`

### Suggested follow-up
- VCU mid-byte range is mostly closed — only a handful of DIDs respond, and only DID 0x0104 has a non-zero value (0x88). Worth a livelog to see if 0x0104 changes under throttle/brake.

---

## Cross-batch observations

### **Client version note — first cycles on +26**

The device was on `0.1.29+24` when C12 ran. Owner installed `+26` between C12 and C13. Bridge confirmed `last_client_version=0.1.29+26` at C13 start. **This batch is the first telemetry under +26.**

A couple of new client behaviors observed:
- **NEW error code `EMPTY`** in C14 (transport-empty / no UDS response received). I had not seen this before — possibly +26-introduced or simply a code path that hadn't been hit in earlier cycles.
- **Discrepancy between `valid_responses` and "no error" rows** in C13 and C16 (bridge says 0, parser sees a few non-empty). The client's "valid" criterion appears stricter than just "no error code" — possibly excluding zero-payload responses.

### **Client sweep busy-state retention (NEW finding)**

C15 first attempt (cmd 32) returned `error_kind=busy`, `error="Another BLE operation in progress (sweep=true livelog=false dtc=false)"` even though C14 sweep batch had already been ingested by the bridge ~35 seconds prior. Sending a follow-up `bleStopActiveOperation` (which returned `stopped=[]` — confirming no actual operation was running) cleared the state and C15 went through cleanly on retry.

**Operator practice (Друг 2):** Between back-to-back sweeps, send `bleStopActiveOperation` defensively *before* each `bleStartSweep`. This avoids a race where the client's BLE layer hasn't released the "busy" flag after a natural sweep completion. The stop is cheap (acks in ~3s) and idempotent.

This means: **30s pause between sweeps is not always enough**. With explicit stop, even a 5-second pause works.

### What we did NOT find
- No 4-byte (32-bit) payload candidates for signed pack current in any of the four scopes
- No 16-bit (2-byte) payload candidates either — all valid responses were 0-byte, 1-byte, or 16-byte ASCII
- No `0x0Bxx`-range data (not in scope this batch)

---

## Pointers
- Repo: https://github.com/AlexTalorJr/cyclesbz5-research, branch `main`
- Commits: `223cc06` (C13), `82b959e` (C14), `55b4a4e` (C15), `a5aa4a1` (C16)
- Per-cycle dirs: `cycles/013-bms-slave-low-scan/`, `014-hv-junction-low-scan/`, `015-bms-master-mid-scan/`, `016-vcu-mid-scan/`
- Each cycle dir has: `command.start.json`, `sweep-run.json`, `raw/sweep.csv`

## Suggested next cycles (from C15's signal)

In rough priority order:

1. **C17 — livelog the 10 BMS master module pairs** under driving conditions (throttle + brake + regen). 7-DID limit applies if cap unchanged in +26 — likely send 7 DIDs: `790/0105 (ASCII anchor)`, `790/0175` + `790/0177` + `790/017D` + `790/017F` + `790/0185` + `790/0187` (first 3 modules). Add VCU `791/0038 power-A` as a known-good current correlate? No, 7 cap. Drop ASCII anchor and add power-A: `791/0038, 790/016D, 016F, 0175, 0177, 017D, 017F` = 7. **Goal:** see which (if any) of these single-byte values correlate with 0x0038 power.

2. **C18 — BMS master `790/798 0x0B00-0x0BFF` sweep** — search for cumulative/energy aggregates in Toyota's traditional aggregate range. We did this for PDU in C8 and got 0/256, but BMS master is a different ECU and may use the range.

3. **C19 — narrow VCU mid-byte verification**: livelog `791/0104` under throttle to see if `0x88` is a live value.

4. **(deferred)** C20+ — HV Junction 715 retry with extended per-DID timeout; would clarify whether the `EMPTY` returns at 0001-0035 are gateway issues or just slow ECU.
