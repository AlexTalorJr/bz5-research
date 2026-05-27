# C19-C22 batch — Big BMS master + VCU mid/post ranges — Notes for Друг 1

**Date**: 2026-05-27 (UTC, same session as C13-C18)
**Bridge cycles**: 19, 20, 21, 22
**Operator**: Друг 2
**Client**: bz5-companion `0.1.29+26`
**Car state**: `parked_ready_off`
**Pipeline note**: First attempt failed due to a bridge constraint — `timeout_ms` is capped at `600000` ms (10 min) on the admin command schema. Your request specified `900000` (15 min). The bridge returned `400 bad_request` and the script's CMD_ID parsing failed, looping silently for 8 min before I killed it. **Operator practice updated**: use `timeout_ms ≤ 600000`. The cmd `timeout_ms` only gates the start-ack window anyway — the actual sweep can run much longer (cf. C11: 17 min sweep with `timeout_ms=120000`).

---

## TL;DR

The **client short-circuits sweep persistence well before reaching `end_did`** when responses are predominantly non-data (NRC or EMPTY). Across these 4 cycles, **the sweep gave up after 80-512 DIDs regardless of requested range**. Only one cluster of unusual data found.

| C | ECU | Range | Requested | **Actually probed** | Cutoff DID | Valid (no err) | Notes |
|---|---|---|---|---|---|---|---|
| 19 | 790/798 BMS master | 0200-05FF | 1024 | 357 (35%) | 0x0364 | 0 | All `7F2231` |
| **20** | **790/798 BMS master** | **0600-0AFF** | 1280 | 495 (39%) | 0x07EE | **24** | **Two zero-byte clusters at 0x0608-060F and 0x0700-070F** |
| 21 | 790/798 BMS master | 0C00-0FFF | 1024 | 512 (50%) | 0x0DFF | 0 | All `7F2231` |
| 22 | 791/799 VCU | 0200-05FF | 1024 | 80 (7.8%) | 0x024F | 0 | All `7F2201` GeneralReject (VCU bailed fastest) |

**No 4-byte signed-int pack-current candidates anywhere.** No 2-byte values. Nothing 16-byte ASCII. The pack-current signal does not surface in static reads of BMS master or VCU mid-byte ranges.

---

## Key finding: client gives up faster on `7F2201` than on `7F2231`

C22 stopped at **80** rejections; C19/C20/C21 made it to 357-512. The difference is the NRC type:
- C19, C21, C20: `7F2231` (subFunctionNotSupported) → client tolerates ~500
- C22: `7F2201` (GeneralReject) → client tolerates only ~80

Looks like the client's "give up" heuristic treats GeneralReject more harshly. Worth a Друг-1-side note: if you want to push past 0x024F on the VCU mid-byte range, you'll need to **start the sweep at 0x0250** (or split into ~80-DID chunks).

This also explains C13 (BMS slave 750) which got 230 rows of `7F2231` before stopping — same family, same threshold.

---

## C20 — the only "find" of the batch

24 DIDs returned **1-byte payload `0x00`** in two clean clusters:

```
Cluster A: 0x0608, 0x0609, 0x060A, 0x060B, 0x060C, 0x060D, 0x060E, 0x060F   (8 DIDs)
Cluster B: 0x0700, 0x0701, 0x0702, 0x0703, 0x0704, 0x0705, 0x0706, 0x0707,
           0x0708, 0x0709, 0x070A, 0x070B, 0x070C, 0x070D, 0x070E, 0x070F  (16 DIDs)
```

All payloads are a single `0x00` byte. Interpretations:
- **Settable parameters not yet configured** — uint8 default of 0
- **Status flags currently in "off" state** — would change under different vehicle state
- **Reserved fields** — exposed for compatibility, no real data

The cluster shape (8 + 16 = 24) is interesting. Cluster A's stride 1 across 8 DIDs and cluster B's stride 1 across 16 might map to:
- A: 8 cell groups × 1 status each
- B: 16 cells × 1 status each
- Or: 8 + 16 = 24 different sub-systems

Worth a livelog under load to see if any of these `0x00` values flip to nonzero.

---

## Per-cycle details

### C19 — BMS master 790/798 0x0200-0x05FF
```
sweep_runs id=13, client_sweep_id=7
csv_rows=357 (DIDs 0x0200..0x0364), all 7F2231
commit a7296e4
```
Nothing useful. The range is uniformly subFunction-rejected on this ECU at this auth level.

### C20 — BMS master 790/798 0x0600-0x0AFF (**find**)
```
sweep_runs id=14, client_sweep_id=8
csv_rows=495 (DIDs 0x0600..0x07EE), 471 NRC + 24 zero-byte
commit 51f0bef
```
See "Key finding" above.

### C21 — BMS master 790/798 0x0C00-0x0FFF
```
sweep_runs id=15, client_sweep_id=9
csv_rows=512 (DIDs 0x0C00..0x0DFF), all 7F2231
commit 6cf1a22
```
Range entirely rejected. The client got further here (512 of 1024) than C19 (357 of 1024) — same range size, same NRC, different total. Suggests the cutoff isn't a simple counter; possibly tied to per-DID timing or chunk boundaries.

### C22 — VCU 791/799 0x0200-0x05FF
```
sweep_runs id=16, client_sweep_id=10
csv_rows=80 (DIDs 0x0200..0x024F), all 7F2201
commit fd56bfa
```
VCU rejects mid-byte mid-range with GeneralReject — and client bails after just 80. This range needs follow-up via chunked sweeps (0x0250-0x02CF, 0x02D0-0x034F, etc.) to map past the cutoff.

---

## Cross-batch client behaviour observations

1. **Sweep persistence cutoff is around 80-512 DIDs depending on NRC type**:
   - `7F2231` (subFunctionNotSupported): ~357-512 DIDs tolerated
   - `7F2201` (GeneralReject): ~80 DIDs tolerated
   - `EMPTY` (transport timeout): ~11-53 DIDs (C14, C17, C18)

2. **`bleStopActiveOperation` between sweeps reported `stopped: ['sweep']` for all 4 cycles in this batch.** Confirms my earlier hypothesis: even after the bridge has received the sweep_results batch, the client's BLE layer retains the "sweep busy" flag until explicitly stopped. The defensive stop is **mandatory** for back-to-back sweeps; 30s of `sleep` alone is insufficient.

3. **Sweep duration is dominated by NRC count, not by `period_ms`.** All 4 sweeps completed in ~60s wall-clock from start ack to row arrival, despite requesting 1024-1280 probes at 250ms each (which would imply 4-5 min if fully executed). The client is iterating much faster than 250ms when responses are NRC-class. The `period_ms=250` parameter seems to govern only successful-response pacing, not the abort path.

4. **Bridge `timeout_ms` cap at 600000.** The admin command schema enforces `timeout_ms ≤ 600000`. Specifying higher values returns `400 bad_request`. Pipeline updated to clamp at 600000.

---

## Open / suggested follow-ups

1. **Chunk past the cutoffs:** Re-sweep narrow ranges where we got cut off:
   - BMS master `0x0365-0x05FF` (start sweep at 0x0365)
   - BMS master `0x07EF-0x0AFF`
   - BMS master `0x0E00-0x0FFF`
   - VCU `0x0250-0x05FF` in 80-DID chunks
2. **Livelog the 24 zero-byte DIDs from C20** under driving / charging — see if any flip non-zero.
3. **Probe the cutoff itself:** does the client give up after N NRCs, N elapsed time, or N consecutive non-responses? Could affect future sweep design.
4. **The pack-current 4-byte signed-int hunt is exhausted in static sweep mode** across BMS master 0x0001-0x05FF, 0x0600-0x07EE, 0x0B00-0x0B0A, 0x0C00-0x0DFF and VCU 0x0100-0x024F. **Final remaining hypothesis: livelog under load is where the signal will surface, not any static read.** Recommend C23 livelog of the 10 BMS module pairs from C15 (`790/0175 0177 017D 017F 0185 0187` + VCU `791/0038`) under driving.

---

## Pointers
- Repo: https://github.com/AlexTalorJr/cyclesbz5-research, branch `main`
- Commits: `a7296e4` (C19), `51f0bef` (C20), `6cf1a22` (C21), `fd56bfa` (C22)

## Ссылки для Друг 1 (раздел для пересылки)

- Сводка: https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/022-vcu-mid-range/notes-for-drug1.md
- Сырые CSV:
  - C19 BMS master 0200-05FF: https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/019-bms-master-mid-range/raw/sweep.csv
  - C20 BMS master 0600-0AFF (**find**): https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/020-bms-master-0600-0AFF/raw/sweep.csv
  - C21 BMS master 0C00-0FFF: https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/021-bms-master-post-0B00/raw/sweep.csv
  - C22 VCU 0200-05FF: https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/022-vcu-mid-range/raw/sweep.csv
