# C23-C27 batch — Retries on +27 + new ranges — Notes for Друг 1

**Date**: 2026-05-27 (UTC, same session as C13-C22)
**Bridge cycles**: 23, 24, 25, 26, 27
**Operator**: Друг 2
**Client**: bz5-companion **`0.1.29+27`** (confirmed via heartbeat at start; first batch on +27)
**Car state**: `parked_ready_off` throughout (~8 minutes total — sweeps ended fast)

---

## TL;DR

**Watchdog model on +27 appears different from +26**: results suggest a **time-based** watchdog (~60-80 s wall-clock per sweep) replaced the earlier count-based one. Effect:
- **`7F2201` (VCU GeneralReject) coverage improved ~6×** (80 → 495 DIDs)
- **`7F2231` (BMS subFunctionNotSupported) coverage now depends on per-DID latency** — 13 to 440 DIDs across the same NRC class

| C | ECU | Range | Stored | Coverage end | Err | vs prior |
|---|---|---|---|---|---|---|
| 23 | 790 BMS master | 0200-05FF | 13 | 0x020C | 13× `7F2231` | C19 had 357 → **MUCH WORSE on +27** |
| 24 | 790 BMS master | 0C00-0FFF | 440 | 0x0DB7 | 440× `7F2231` | C21 had 512 → ~similar |
| 25 | 791 VCU | 0200-05FF | 495 | 0x03EE | 495× `7F2201` | C22 had 80 → **6× BETTER** |
| 26 | 790 BMS master | 0700-0AFF | 49 (16 valid + 33 NRC) | 0x0730 | 33× `7F2231` | extends C20 — **cluster bounded at 16 DIDs** |
| 27 | 791 VCU | 0C00-0FFF | 495 | 0x0DEE | 495× `7F2201` | new — same coverage as C25 |

**No 4-byte signed-int candidates** in this batch. The pack-current static-read hunt is now exhausted across all reachable BMS master / VCU ranges.

---

## Watchdog model — time-based hypothesis

Wall-clock duration vs probe count for each sweep:

| C | wall-clock | DIDs stored | DIDs/sec | inferred ms/DID |
|---|---|---|---|---|
| 23 | ~46 s | 13 | 0.28 | **3500 ms** — slow BLE link |
| 24 | ~80 s | 440 | 5.5 | 180 ms |
| 25 | ~80 s | 495 | 6.2 | 162 ms |
| 26 | ~48 s | 49 | 1.02 | **980 ms** (valid responses cost more than NRCs) |
| 27 | ~80 s | 495 | 6.2 | 162 ms |

When responses are fast (~160-180 ms/DID), the sweep reaches 440-495 DIDs in ~80 s and ends.
When responses are slow (valid payloads or laggy BLE), the sweep covers far fewer DIDs in the same window.

**Implication: the +27 watchdog deadline is ~60-90 s wall-clock**, not a probe count. This is a much more predictable and tunable mechanism than +26's count-based behaviour, but **1024-DID ranges still won't complete in one sweep** — you need to chunk the remaining ranges from each cycle's cutoff onward.

(Caveat: C23 had a 3.5 s/DID outlier likely due to a transient BLE link issue at sweep start. Worth a clean retry to see if it goes deeper on a normal-latency run.)

---

## C26 — the only meaningful data finding

The C20 zero-byte cluster at 0x0700-0x070F is **bounded at exactly 16 DIDs**. C26 swept 0x0700-0x0AFF and got:
- DIDs 0x0700..0x070F: 16 × `0x00` 1-byte payloads (confirms C20)
- DIDs 0x0710..0x0730: 33 × `7F2231` (no further cluster)
- DIDs 0x0731..0x0AFF: not reached (watchdog cut)

No expansion of the cluster. Whatever those 16 DIDs are, they form a closed group at `0x0700-0x070F`.

---

## Per-cycle details

### C23 — BMS master 0200-05FF retry (+27)
```
cmd id=52, sweep_runs id=17 (deleted post-copy)
stored=13, range 0200..020C, all 7F2231
46 s wall — outlier slow run (3.5 s/DID)
commit see git log
```
Effectively useless on this run. **Recommend a clean retry** to see if the watchdog yields a deeper scan under normal latency.

### C24 — BMS master 0C00-0FFF retry (+27)
```
cmd id=54, sweep_runs id=18
stored=440, range 0C00..0DB7, all 7F2231
80 s wall, 180 ms/DID
```
Similar to C21 +26 (512 stored). The range is uniformly NRC-rejected on BMS master at this auth level — no new finding.

### C25 — VCU 0200-05FF retry (+27)
```
cmd id=56, sweep_runs id=19
stored=495, range 0200..03EE, all 7F2201
80 s wall, 162 ms/DID
```
**6× improvement over C22 +26.** Confirms the +27 watchdog lift for GeneralReject. Still didn't reach end_did=0x05FF — needs chunked sweep from 0x03EF onward to map the remaining ~270 DIDs.

### C26 — BMS master 0700-0AFF (expand C20)
```
cmd id=58, sweep_runs id=20
stored=49 (16 valid 1-byte zeros + 33 NRC), range 0700..0730
48 s wall, 980 ms/DID
```
Cluster confirmed bounded; no further finding in this range.

### C27 — VCU 0C00-0FFF (new)
```
cmd id=60, sweep_runs id=21
stored=495, range 0C00..0DEE, all 7F2201
80 s wall, 162 ms/DID
```
VCU high range is uniformly GeneralRejected, same as VCU mid. No data exposed. **Chunked retry from 0x0DEF onward needed** to confirm the rest is also rejected.

---

## Cross-batch observations

1. **+27 watchdog model**: time-based, ~60-90 s wall-clock per sweep. Replaces +26's NRC-count-based cutoff. More predictable, still partial on big ranges.
2. **`bleStopActiveOperation` between sweeps still showed `stopped: ['sweep']`** on +27 — the busy-retention behavior is unchanged. Keep using defensive stop between cycles.
3. **No improvement to NRC handling latency** — fast NRCs still run at ~160-180 ms/DID. Valid responses cost ~3-6× more (C26's 980 ms/DID per response is consistent with prior livelog probes).

---

## Recommendations for Друг 1

1. **Chunk past every +27 cutoff** if more data is needed:
   - BMS master `0x020D-0x05FF` (C23 left out 1011 of 1024)
   - BMS master `0x0DB8-0x0FFF` (C24 left out 583)
   - BMS master `0x0731-0x0AFF` (C26 left out 975)
   - VCU `0x03EF-0x05FF` (C25 left out 528)
   - VCU `0x0DEF-0x0FFF` (C27 left out 528)
2. **Pack-current hunt in static reads is exhausted.** All reasonable static-DID territory on BMS master / VCU has been probed. **The signal must come from livelog under load.** Best candidate: C28 livelog combining `791/0038` (power-A reference) + the 7 most-promising BMS module DIDs from C15 (`790/0175 0177 017D 017F 0185 0187 016D`) under driving + regen.
3. **The 16 zero-byte DIDs at `0x0700-0x070F`** still beg an explanation. Static read = 0 across two visits. Worth a livelog under driving to see if any go non-zero, or a `WriteDataByIdentifier` probe (risky — would need owner authorization).
4. **C23 had abnormal BLE latency** (3.5 s/DID). A clean retry might cover 400+ DIDs like C24/C25 did. Could be queued opportunistically.

---

## Pointers

Commits in `bz5-research` `main`:
- C23: see `git log cycles/023-bms-master-mid-retry/`
- C24: `cycles/024-bms-master-0C00-0FFF-retry/`
- C25: `cycles/025-vcu-mid-retry/`
- C26: `cycles/026-bms-master-0700-0AFF-cluster/`
- C27: `cycles/027-vcu-high-range/`

## Ссылки для Друг 1 (раздел для пересылки)

- **Сводка**: https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/027-vcu-high-range/notes-for-drug1.md
- Сырые CSV:
  - C23 BMS master 0200-05FF (+27): https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/023-bms-master-mid-retry/raw/sweep.csv
  - C24 BMS master 0C00-0FFF (+27): https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/024-bms-master-0C00-0FFF-retry/raw/sweep.csv
  - C25 VCU 0200-05FF (+27, +6× coverage): https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/025-vcu-mid-retry/raw/sweep.csv
  - C26 BMS master 0700-0AFF (cluster bounded): https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/026-bms-master-0700-0AFF-cluster/raw/sweep.csv
  - C27 VCU 0C00-0FFF (new): https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/027-vcu-high-range/raw/sweep.csv
