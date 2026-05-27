# C17-C18 batch — BMS master 0B00 + Brake controller — Notes for Друг 1

**Date**: 2026-05-27 (UTC, same session as C13-C16)
**Bridge cycles**: 17, 18
**Operator**: Друг 2
**Client**: bz5-companion `0.1.29+26`
**Car state**: `parked_ready_off`
**Defensive `bleStopActiveOperation`** sent before each sweep (per C15 lesson). Pipeline clean.

---

## TL;DR

| C | ECU | Range | rows | valid (client) | valid (rows w/o error) | Verdict |
|---|---|---|---|---|---|---|
| **17** | **790/798 BMS master** | **0B00-0BFF** | **11** | 0/256 | 11 | **First-pass find of the aggregate cluster**; stops at 0x0B0A. **`0B02 = 0x0E = 14`** confirmed cycle count. |
| 18 | 7B0/7B8 Brake controller | 0001-00FF | 27 | 0/255 | 0 | All 27 are `EMPTY` (transport timeout); brake controller silent through standard UDS on this range |

**No 4-byte signed-int pack-current candidate found in either cycle.** The `0x0Bxx` hunt yielded only small (1-3 byte) values; no aggregate energy counter is exposed at that range on the master.

---

## C17 — BMS master 790/798 0x0B00-0x0BFF

```
sweep_runs id=11 → DELETEd after \copy
client_sweep_id=5
total_probes=256 (claimed), csv_rows=11 (DIDs 0B00..0B0A only)
commit 4661113
```

### Findings

The sweep persisted only 11 rows — DIDs 0x0B00 through 0x0B0A. Everything after 0x0B0A returned silently (no row stored, even with `error_code='EMPTY'`). Compare to C14 where 53 `EMPTY` rows were recorded for DIDs 0001-0035 and then silence: the client appears to truncate the recorded results once it gives up. This is consistent with **client short-circuit after N consecutive timeouts** — see *Cross-batch client observation* below.

The 11 stored DIDs and their payloads:

| DID | Bytes | Payload (hex) | Decimal interpretation |
|---|---|---|---|
| `0B00` | 1 | `75` | uint8=117 |
| `0B01` | 1 | `71` | uint8=113 |
| `0B02` | 1 | `0E` | **uint8=14 — confirms Друг 1's "known 0B02 cycle count"** |
| `0B03` | 0 | (empty echo) | DID exposed, no value |
| `0B04` | 0 | (empty echo) | DID exposed, no value |
| `0B05` | 0 | (empty echo) | DID exposed, no value |
| `0B06` | 3 | `01 02 02` | could be packed date (1 Feb 2026?), version (1.2.2), or counter |
| `0B07` | 3 | `00 00 00` | empty 3-byte field |
| `0B08` | 3 | `00 00 00` | empty 3-byte field |
| `0B09` | 3 | `00 00 00` | empty 3-byte field |
| `0B0A` | 3 | `00 00 00` | empty 3-byte field |

### Friend-1 checklist
- **4-byte signed**: NONE. The aggregate range on BMS master does not expose 32-bit signed values.
- **High-variance**: n/a (single sweep, parked)
- **0x0B00+ aggregate**: **partial hit** — small (1-3 byte) status/version values found at 0B00-0B0A. No "lifetime energy in Wh" type counter.
- **ASCII strings**: none in this range

### Open questions

1. **What encodes the 1-byte values `0x75 0x71 0x0E`?** `0E=14` is cycle count (per your memory). What are `75=117` and `71=113`? They're close in magnitude — could be: temps in °C (117°C/113°C — too hot for a parked car), key-on cycles, or charge cycles. Or scaled SoH metrics.
2. **`0B06 = 01 02 02`** — date `2002-01-02`? version `1.2.2`? something else? Worth a livelog to see if it's a true constant (likely it is, looks like manufacture metadata).
3. The 0-byte echoes at `0B03`-`0B05` and 3-byte zeros at `0B07`-`0B0A` look like "writable parameters not yet set" or "reserved for future".

### Suggested follow-up

- **Read 0x0B02 over a key-cycle to verify it's the cycle counter** (number should increment by 1 on next ready-off → ready-on).
- The cluster is tiny — likely no further aggregate counters live on BMS master. Energy and current accumulators are probably elsewhere (e.g., on the PDU or charger ECU 0x723 once a charging session runs).

---

## C18 — Brake controller 7B0/7B8 0x0001-0x00FF

```
sweep_runs id=12 → DELETEd after \copy
client_sweep_id=6
total_probes=255 (claimed), csv_rows=27 (DIDs 0001..001B), all error_code=EMPTY
commit 7c0cc66
```

### Findings
- 27 rows, all `error_code='EMPTY'`, covering DIDs 0001-001B
- DIDs 001C-00FF: silent, not stored
- Same pattern as C14 (HV Junction): partial `EMPTY` window, then silence
- The brake controller does NOT expose standard UDS ReadDataByIdentifier on this range via the K2 routing

### Friend-1 checklist
- 4-byte signed: none
- High-variance: n/a
- 0x0B00+: not in range
- ASCII: none

### Open questions

1. Is the brake controller actually reachable on K2 at all, or are we hitting a gateway that just times out? Worth a single-DID probe with a much longer timeout to disambiguate.
2. If it's reachable, the regen torque signal may use a different SID (e.g., ReadDataByLocalIdentifier 0x21, or a manufacturer-specific service). Standard 0x22 is not the access path.

### Suggested follow-up

- **De-prioritize this ECU** for pack-current hunting. Even if the regen torque DID exists, the `EMPTY`-then-silence pattern says the routing or service is wrong, not the DID.
- Better path: livelog `791/0038` (VCU power-A, known) under throttle/brake/regen to see if regen events are visible at the VCU side rather than the brake controller.

---

## Cross-batch client observation (NEW)

In both C17 and C18, the bridge ended up with **far fewer sweep_results rows than `total_probes`** would suggest:
- C17: total_probes=256, csv_rows=11 (DIDs 0B00..0B0A)
- C18: total_probes=255, csv_rows=27 (DIDs 0001..001B), all `EMPTY`

Compare with earlier sweeps:
- C13: 230/255 rows (224 NRC + 6 valid)
- C15: 256/256 rows (81 valid + 175 NRC)

So when an ECU returns explicit NRCs (C13, C15), the client persists every row. When responses are missing/timed out, the client **stops persisting after some threshold** — looks like it gives up after a small number of consecutive non-responses.

This means our `valid_responses=0` reading is misleading for C17: the client did stop probing or stop persisting at DID 0x0B0A, not at 0x0BFF. We genuinely scanned **only 0x0B00-0x0B0A**, not the whole range.

**Worth confirming on Друг 1's side:** is this a `+26` change? Should we re-sweep narrow chunks (e.g., 0x0B10-0x0B1F, 0x0B20-0x0B2F) explicitly to probe past the give-up point? Or is the cluster genuinely just at 0x0B00-0x0B0A?

---

## Pointers
- Repo: https://github.com/AlexTalorJr/bz5-research, branch `main`
- Commits: `4661113` (C17), `7c0cc66` (C18)
- Per-cycle dirs each contain `command.start.json`, `sweep-run.json`, `raw/sweep.csv`

## Ссылки для Друг 1 (раздел для пересылки)

- Сводка: https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/018-brake-controller-low-scan/notes-for-drug1.md
- Сырые CSV:
  - C17 BMS master 0B00: https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/017-bms-master-0B00-scan/raw/sweep.csv
  - C18 Brake controller: https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/018-brake-controller-low-scan/raw/sweep.csv

## Suggested next steps (carrying over from C13-C16 notes)

The pack-current 4-byte signed-int signal has not surfaced anywhere across C13-C18. Best remaining hypothesis: **the value lives in livelog under load**, not as a static read at park. Recommended next cycle:

- **C19 — livelog the BMS master 10-module pairs from C15 under driving + regen**. 7-DID cap from +24 may or may not still apply on +26 — try with 10 first; if rejected, fall back to 7 with the most-promising subset.
