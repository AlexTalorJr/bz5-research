# C32 — Drive sign-check (notes for Друг 1)

**Date:** 2026-05-30
**Client:** bz5-companion `0.1.29+32` (no new code since C31), bridge rev `0003`.
**Goal:** Drive livelog of the C31 candidate set to sign-check pack current/power
(charge = +, discharge = −). Same 10-DID list across two drive runs, started near
100 % SOC.

## Runs

| Run | session/csid | entries | exit | notes |
|-----|--------------|---------|------|-------|
| 1 | 18 / 7 | 2652 | cancelled | mixed city drive from 100 % SOC |
| 2 | 19 / 8 | 4053 | cancelled | mixed drive; **last ~5 min steady ~90 km/h** (clean steady-discharge tail) |

Both runs clean: **0 client errors** across all 10 DIDs, byte-lengths identical to
C31 charge (no padding drift this time — see table). Bridge DB rows deleted after
capture (data is in `raw/` here).

## DID list (unchanged from C31 candidate set)

`790/0015` (pack-V anchor), `790/1FFD` (SOC anchor), `791/0026` (odo anchor),
`790/0009`, `790/000A`, `790/0006` (const ref), `791/0038`, `791/0039`,
`740/0008`, `740/0022`.

## Charge (C31) vs Drive (C32 run1+run2) — decoded uint, "62"+DID prefix stripped

`straddle = BOTH` means drive values fall **both below and above** the C31 charge
median — the signature we'd expect from a signed/bidirectional current that swings
to charge polarity on regen and discharge polarity on accel.

| ECU/DID | role | charge med (hex) | drive min..med..max (hex) | span | distinct | straddle |
|---------|------|------------------|---------------------------|------|----------|----------|
| 790/0015 | pack voltage | 0x42bc | 0x3a49 .. 0x42f8 .. 0x4cca | 4737 | 169 | **BOTH** |
| 790/1FFD | SOC (4-byte) | 0x10183b09 | 0x2486… .. 0x26fc… | — | 55 | above (100 % start) |
| 791/0026 | odometer (4-byte) | — | monotonic ↑ | 266 | 236 | — (sane) |
| **790/0009** | **BMS current** | **0x1355 (4949)** | **0x1122 .. 0x1404 (5124) .. 0x1bbe (7102)** | **2716** | **459** | **BOTH** |
| 790/000A | BMS cand (weak) | 0x03c1 (961) | 0x0104 .. 0x0116 (278) .. 0x01b6 (438) | 178 | 47 | below only |
| 790/0006 | const ref | 0x05e7 | 0x05e1 (constant) | 0 | 1 | — (control OK) |
| **791/0038** | **VCU power-A** | **0x0326 (806)** | **0x0323 .. 0x0491 (1169) .. 0x08a6 (2214)** | 1411 | 284 | **BOTH** |
| **791/0039** | **VCU current** | **0x0648 (1608)** | **0x0645 .. 0x0791 (1937) .. 0x0eda (3802)** | 2197 | 279 | **BOTH** |
| 740/0008 | PDU cand | 0x0000 (0) | 0x0000 .. 0x02ae (686) .. 0x0594 (1428) | 1428 | 353 | above (0 on charge) |
| 740/0022 | PDU cand | 0x4650 (18000) | 0x4650 .. 0x465e .. 0x4673 | 35 | 22 | flat |

Byte-lengths: every DID consistent charge↔drive (790/0015,0009,000A,0006,791/0038,
791/0039,740/0008,740/0022 = 2B; 790/1FFD, 791/0026 = 4B). **No idle/charge padding
drift this cycle** (contrast Pattern-A from C31).

## Steady-90 tail (last ~5 min of run 2, n≈109 per DID)

| DID | charge med | full-drive med | **steady-90 med** | tail span |
|-----|-----------|----------------|-------------------|-----------|
| 790/0009 | 4949 | 5124 | **5283** | 1639 |
| 790/000A | 961 | 278 | 353 | 171 |
| 791/0038 | 806 | 1169 | **804** | 947 |
| 791/0039 | 1608 | 1937 | **1608** | 2196 |
| 740/0008 | 0 | 686 | 1268 | 237 |
| 740/0022 | 18000 | 18014 | 18012 | 1 |

Note the near-exact return of **791/0038 (804 vs charge 806)** and **791/0039 (1608 vs
charge 1608)** to their AC-charge medians under steady cruise — worth your decode.

## Verdicts

- **790/0009 — strongest signed pack-current candidate.** 459 distinct values,
  straddles the AC-charge baseline both ways. Ordering is physically coherent for a
  signed current axis:
  `regen(min 4386) < AC-charge(4949) < idle/cruise(5124) < steady-90(5283) < hard-accel(max 7102)`.
  Regen (large charge current) sits *below* the small 8 A AC charge, discharge sits
  *above* — i.e. value rises with discharge, falls with charge. **Hypothesis: signed
  int16 pack current; zero-point just below the AC-charge value.** Needs your scale/
  offset fit (C31 gave ~8.4–8.7 A at 4949 → ~0.0017 A/LSB if linear; please confirm).
- **791/0038 & 791/0039 — confirmed dynamic, bidirectional.** Both straddle BOTH and
  snap back to their AC-charge median at steady 90 km/h. Consistent magnitude story;
  sign decode is yours.
- **740/0008 — drive-only power.** Zero throughout AC charge, ranges 0–1428 under
  drive. Reads like PDU/motor delivery (active only when driving), not a battery-side
  signed current.
- **790/000A — reject as pack current.** Narrow under drive (47 distinct, span 178),
  *lower* than charge, no bidirectional swing. Likely a temperature/per-module field.
- **740/0022 — reject as current.** Flat ~18000 in both charge and drive (drive span
  35). Looks like a voltage rail / config constant, not current.
- **Anchors sane:** 790/0015 swings hard both ways (sag on accel, rise on regen);
  790/1FFD high (100 % start), trending down; 791/0026 odo monotonic up; 790/0006
  constant (control DID held → rig validated).

## Owner's two explicit questions

1. **790/0015 over time:** ✅ clear sag/rise. Drive range 0x3a49 (≈373 V at ×0.025)
   .. 0x4cca (≈491 V) vs a tight charge median 0x42bc (≈428 V). Voltage moves ±~60 V
   around the charge level under accel/regen — the load response we wanted. Full trace
   in the run CSVs (filter `ecu_tx=790, did=0015`, plot `raw_hex` vs `timestamp`).
2. **Do 790/0009 / 790/000A jitter more under road load than charging?**
   - **790/0009: YES, dramatically** — 459 distinct drive values across a 2716-count
     span and bidirectional, vs a tight band on charge. Strong current behaviour.
   - **790/000A: NO** — stays narrow (47 distinct, span 178) and *below* its charge
     level. Not behaving like pack current.

## Caveat (method honesty)

A naive same-second pairing of `790/0009` vs `790/0015` gave only ~73–109 pairs with
near-zero Pearson r — **inconclusive**, because the 10 DIDs are sampled round-robin so
current and voltage rarely land in the same 1 s bucket, and accel/regen transients are
brief relative to the per-DID revisit interval. A proper time-aligned (interpolated)
correlation is left to you — flagging so the weak r is not read as evidence against
790/0009. The straddle + ordering evidence above does not depend on it.

## Raw files

All under `cycles/032-drive-signcheck/`:
- `run-1/command.start.json`, `run-1/raw/live_log_sessions.csv`, `run-1/raw/live_log_entries.csv.gz`
- `run-2/command.start.json`, `run-2/raw/live_log_sessions.csv`, `run-2/raw/live_log_entries.csv.gz`

Entries schema: `id,session_id,timestamp,ecu_tx,did,raw_hex,error_code,cycle`.
Decode: strip `62`+DID (6 hex chars) prefix → remaining bytes are the payload.

---

# C32 FINAL — canonical runs 3+4 (Drug1 directive) + combined

Two more drive runs on the canonical 10-DID set (`791/0038,0039`, `790/0009,0010,0015,1FFD`,
`740/0008,0022,0023`, `782/000A`), `duration_sec=600`, client `0.1.29+32`.
Command-level `timeout_ms` capped 630000→600000 (bridge schema `le=600_000`; gates the
claim window only, not the 600 s livelog). Per-run phase notes in `run-3/drive-phases.md`,
`run-4/drive-phases.md` (run-4 = 3–5 full-throttle accel + max-regen — the high-current window).

## 1. Pattern A (high-byte loss) — DEFINITIVELY ABSENT

Across runs 3+4 (n≈247 per DID), **zero 1-byte samples on any current DID**, including when
the high byte was clearly non-zero:

| DID | n | 1-byte? | byte-lens | max MSB | max val |
|-----|---|---------|-----------|---------|---------|
| 790/0009 | 247 | **none** | {2} | **0x26** | 0x26E1 |
| 791/0039 | 247 | **none** | {2} | 0x10 | 0x1062 |
| 791/0038 | 247 | **none** | {2} | 0x0D | 0x0D41 |
| 782/000A | 246 | none | {2} | 0x55 | 0x557F |
| 740/0023 | 246 | none | {2} | 0xC6 | 0xC64F |
| 740/0008 | 245 | none | {2} | 0x04 | 0x04D3 |
| 790/0010 | 247 | none | {3} | — | 0x06A1 |
| 790/0015 | 246 | none | {2}+44 empty | 0x4A | 0x4AD5 |

**Conclusion:** the C31 "1-byte on charge" was just minimal-value encoding (true high byte = 0
at ~8 A) — **not** a truncation bug. Full 16-bit value is preserved whenever the high byte is
non-zero (verified up to MSB 0x26 on 790/0009 at full throttle). `791/0039` — the DID you
specifically flagged — is 247/247 two-byte. **No byte-loss correction needed.**

## 2. Sign

- **740/0023 — real sign-bit flip, but only as a 2-state signal.** Distinct values per run:
  run-3 `{0x46CB ×68 (positive), 0xC64F ×40 (negative-as-int16)}`; run-4 `{0x46CB ×138 only}`.
  The sign bit *does* flip on regen (run-3), but the DID reports just two quantised levels and
  was **frozen** for all of run-4 (along with 740/0022). PDU 740 sub-DIDs look cached/stale on
  this client — **treat 740/0023 as corroborating sign evidence only, not a usable current.**
- **790/0009 / 791/0038 / 791/0039 — continuous, monotonic with load, stay positive raw**
  (offset-encoded, not two's-complement). Dynamic range over runs 3+4:

  | DID | distinct | min..max (hex) | span |
  |-----|----------|----------------|------|
  | 790/0009 | 116 | 0x0D12 .. 0x26E1 | 6607 |
  | 791/0039 | 63 | 0x0646 .. 0x1062 | 2588 |
  | 791/0038 | 60 | 0x0326 .. 0x0D41 | 2587 |

  790/0009's max climbed monotonically as accel got harder (run-1/2 0x1BBE → run-3 0x1ED8 →
  run-4 full-throttle 0x26E1), and dips below its AC-charge value on regen — i.e. **signed pack
  current via a fixed offset**, not a sign bit. Your job: fit the zero-offset + A/LSB (C31 anchor
  ≈ 8.4–8.7 A at the AC-charge value).

## 3. Primary-DID recommendation for the dashboard

**790/0009 (BMS 790/798) as the primary pack-current readout:** BMS-sourced (authoritative),
widest + smoothest dynamic range, monotonic with load, **no byte loss**, low error rate, live in
all 4 runs. Pair with **791/0038** as the power (kW) readout and cross-check `P = V × I` using
**790/0015** pack voltage (note: 0015 dropped ~18 % of samples to empty on drive — BLE flakiness,
still enough for V×I). **Drop 790/0010** from drive views (3-byte, near-constant 0x069x off-charge
— AC-side only). 740/0022 flat (not current); 782/000A is OBC/AC-side.

## Raw files (runs 3+4)
- `run-3/{command.request.json, command.start.json, drive-phases.md, raw/live_log_*.csv}`
- `run-4/{command.request.json, command.start.json, drive-phases.md, raw/live_log_*.csv}`
