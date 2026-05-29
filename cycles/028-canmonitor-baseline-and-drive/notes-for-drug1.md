# Cycle 28 — CAN baseline + drive livelog — Notes for Друг 1

**Date**: 2026-05-29
**Bridge cycle**: 28 (composite — smoke + Phase A + Phase B)
**Operator**: Друг 2 (bridge Claude)
**Client**: bz5-companion `0.1.29+30` (first canmonitor cycles on +30)
**Bridge**: revision `0002` (commit `c73f0fb` shipped just before this cycle, see `bridge-changes-for-drug1.md` in same dir)

---

## TL;DR

**Phase A (canmonitor 30s parked Ready ON)**: clean run, `exit=completed`, **unique_can_ids=2 → gateway whitelist** per your rubric.
**Phase B (livelog 25m drive, 10 DIDs)**: 2898 entries, **0 valid responses**. Two hypotheses below; strongest is **ELM327 state-bleed from Phase A's `AT MA` into Phase B's UDS reads**. The protocol's defensive `bleStopActiveOperation` + 30 s pause did NOT reset the adapter out of monitor-mode.

This is a client-side / adapter-firmware issue, not a bridge issue. Bridge pipeline (`/v1/data/ingest/canmonitor` + the new tables) handled everything cleanly across both phases: idempotency, `client_session_id` persistent counter, `notes` carrying your `exit=...`, `ts_ms` relative. **Bridge contract OK.**

---

## Phase A — Gateway openness probe (parked Ready ON, 30 s)

```
cmd 63 bleStartCanMonitor duration_sec=30 car_state="parked_ready_on"
  → ack ok in 3 s, result {kind:"canmonitor", started:true}
session id=2, client_session_id=2 (incremented from smoke's 1 — persistent monotonic ✓)
duration=30s, started_at 15:34:06Z, ended_at 15:34:37Z
notes: "Cycle 28 phase A — gateway openness test | exit=completed"
frame_count=20, unique_can_ids=2
flush latency post-stop: ~46 s (row arrived at 15:35:23Z)
```

### Verdict against your checklist
**`exit=completed` + `unique_can_ids = 2`** → falls in your **`1-3 = gateway whitelist`** bucket. **Gateway is closed/whitelist — not open.**

### Frame breakdown
- `can_id=620`: 19/20 frames. Periodic broadcast across `ts_ms 1000..5000` (4-second active window, then 25 s silence). Frame cadence ~4.75 Hz.
- `can_id=014`: 1 frame, `ts_ms=1000`, empty payload (wake-up?)

### Interesting payload structure on `620` — possible multiplex
Several `620` payloads contain hex sequences that **look like encoded BMS DID-value pairs** we've been probing via UDS:

| ts_ms | payload_hex | possible decode |
|---|---|---|
| 2000 | `02B0CC8` | DID `0x002B` → `0x0CC8` |
| 3000 | `02D0CCD` | DID `0x002D` → `0x0CCD` |
| 2000 | `015419B` | DID `0x0015` → `0x419B` |
| 4000 | `02C05`   | DID `0x002C` → `0x05` (short, or wrong padding) |
| 4000 | `02E00`   | DID `0x002E` → `0x00` |

If this is real multiplex, **subscribing to `620` could replace UDS polling of 0x00xx-range DIDs**. Worth your call. But there's a complication — see *Possible client serialization bug* below.

### Possible client serialization bug (Phase A only — smoke was OK)

In the smoke run (5 s), all 7 captured frames had **even-length** `payload_hex` (12 chars = 6 bytes): standard UDS positive responses like `056201A70CCC`.

In Phase A, payloads had **odd-length** hex: `00501`, `02C0221`, `02D01CB`, `015419B`, `02B0CC8`, `02D0CCD`, `02C05`, `02E00`, `A0700CD`...

This is impossible for a real hex byte string — every byte is 2 nibbles. Most likely cause: the client serializes the payload as `Integer.toHexString(value)` somewhere, which strips leading zeros. The 7-char strings probably represent 4-byte values with a leading-zero nibble missing (e.g., `02B0CC8` → `002B 0CC8`); the 5-char ones probably represent 3-byte values.

Decoding is recoverable on your side (just left-pad to nearest even length), but it would be cleaner to fix the serialization to always pad to even.

### Phase A artifacts

- Session row: https://github.com/AlexTalorJr/cyclesbz5-research/blob/main/cycles/028-canmonitor-baseline-and-drive/phase-a/can_monitor_session.csv
- Frames (20 rows): https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/028-canmonitor-baseline-and-drive/phase-a/can_frames.csv
- Commit: `8723e9c`

---

## Phase B — Drive livelog (~25 min, 10 DIDs)

```
cmd 65 bleStartLiveLog duration_sec=1800 (drive ended early)
  did_list:
    BMS  790/798: 0608, 060B, 060F, 0700, 0708, 070F, 0015
    VCU  791/799: 0026, 0038
    PDU  740/748: 0008
  → ack ok in 5 s, result {kind:"livelog", started:true}
session id=10, client_session_id=1 (BridgeDiagService runtime restarted between phases)
duration: 15:39:24Z → 16:04:28Z = 25m4s
notes: "started via bridge command | exit=cancelled"   ← I sent stop early
entry_count=2898, cycle_count=290  →  ~8.6 s/cycle (10 DIDs × ~860 ms each)
flush latency post-stop: ~60 s
```

**+30 lifted the 7-DID cap.** 10-DID list accepted with no validation error. Good.

### The bad news — 0 valid responses

Across 2898 entries, **none** had a valid UDS response. Distribution:
| Bucket | Count | Notes |
|---|---|---|
| `error_code = EMPTY` (transport timeout / no response) | 289 | exactly 1 per cycle, on a single DID per cycle |
| `error_code = MALFORMED:<broadcast-like>` (5+ hex chars) | 2029 | many distinct codes — looks like CAN broadcasts |
| `error_code = MALFORMED:<short>` (2-4 chars) | 580 | values `54`, `53`, `5F`, `6000` repeating |

Per-DID summary: **every requested DID returned 290 errors (1 per cycle)**, never a single `raw_hex` payload.

### The smoking gun — MALFORMED codes look like CAN broadcast frames

| MALFORMED code | Count | Notes |
|---|---|---|
| `6080000` | 290 | matches requested DID `0x0608` + zero payload, padded as CAN-frame-ish |
| `60B0000` | 290 | matches `0x060B` |
| `60F0000` | 290 | matches `0x060F` |
| `7000000` | 290 | matches `0x0700` |
| `7080000` | 290 | matches `0x0708` |
| `70F0000` | 290 | matches `0x070F` |
| `80323`/`80324`/`80325`/`803xx`...`806xx` | 700+ | look like CAN broadcasts from ID `0x080` (or similar) with varying payloads |
| `6000` | 290 | exactly 1 per cycle, fixed value |

The 6 codes at exactly 290 each (matching `cycle_count`) correspond **exactly** to the 6 high-byte BMS DIDs we requested (`0608, 060B, 060F, 0700, 0708, 070F`). The client appears to receive **something** for these reads, but the response shape doesn't match positive RDID (`62 ...`), so the parser flags MALFORMED.

The hundreds of `803xx-806xx` MALFORMED codes look like **drive-time CAN broadcast frames** (variable values consistent with telemetry from a periodic broadcaster on the bus).

### Hypothesis: ELM327 stuck in `AT MA` monitor mode

In Phase A, the client used `bleStartCanMonitor` which (per your spec) issues `AT MA` to the ELM327. After my `bleStopActiveOperation` + 30 s pause, the client started a new `bleStartLiveLog` — but **the ELM327 may not have actually exited monitor mode**. In that state:
- Every UDS request would either time out (`EMPTY`) or get echoed alongside still-arriving broadcast frames
- The client's UDS parser would see broadcast frames where it expects positive responses → MALFORMED

This is consistent with everything observed:
1. The 6 MALFORMED codes at exactly 290 occurrences (the 6 DIDs that returned ECHO-like CAN-frame-ish responses every cycle)
2. The huge variety of 800-range MALFORMED codes (real drive-time CAN broadcasts during the 25-min drive)
3. The 289 `EMPTY` (one DID per cycle entirely silent)
4. The other 4-byte DIDs (0015, 0026, 0038, 0008) ALSO returning MALFORMED — also matches if the parser is just receiving wrong data

If correct, **the workaround `bleStopActiveOperation` + sleep is insufficient between canmonitor and livelog on +30**. Likely needs an explicit `AT MA` exit (e.g., send any non-monitor AT command to the ELM327) before re-arming the UDS request loop. Or a longer cool-down. Or restart the BLE GATT session.

### Alternative hypothesis (less likely)

`+30` has a livelog parser regression unrelated to canmonitor. Possible but doesn't explain why the MALFORMED codes look so much like CAN broadcasts.

### Phase B artifacts

- Session row: https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/028-canmonitor-baseline-and-drive/phase-b/live_log_session.csv
- Entries (2898 rows, gzipped 19 KB): https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/028-canmonitor-baseline-and-drive/phase-b/live_log_entries.csv.gz
- Commit: (this commit)

---

## Bridge pipeline verification (full session, all phases)

Across smoke + Phase A + Phase B the bridge side did exactly what your `c73f0fb`-shipped contract promised:

| Check | Result |
|---|---|
| `bleStartCanMonitor` accepted by whitelist | ✓ (smoke + Phase A) |
| `bleStartLiveLog` with 10 DIDs accepted | ✓ (no validation error — +30 lifted the 7-DID cap) |
| `POST /v1/data/ingest/canmonitor` ingested rows | ✓ (smoke 7 frames, Phase A 20 frames) |
| `client_session_id` persistent monotonic (smoke=1, Phase A=2) | ✓ |
| `notes` carries client `exit=...` | ✓ (`exit=completed` in both) |
| `ts_ms` relative to `started_at` (not epoch) | ✓ (0..1000 smoke; 1000..5000 Phase A) |
| `frame_count` matches stored count | ✓ (7=7, 20=20) |
| `unique_can_ids` self-consistent | ✓ |
| Idempotency UNIQUE constraint exercised | not live (single POST per session, no client retry) |
| `bleStopActiveOperation` between phases | ✓ (cmd 64, `stopped=[]`) |

---

## Open questions / suggested follow-ups

1. **Confirm or refute the ELM327 stuck-in-monitor hypothesis.** If correct, the `bleStartCanMonitor` → `bleStartLiveLog` transition needs more than `bleStopActiveOperation` + sleep. Suggestions: explicit `AT MA` exit, or `AT PP <param> ON` cycle, or `ATZ` soft reset, or close+reopen GATT session.
2. **Phase B-prime as control.** A regular `bleStartLiveLog` with the same 10 DIDs but **without** running canmonitor beforehand would confirm or refute the bleed theory in one cycle.
3. **`620` broadcast multiplex.** If real, this is interesting: subscribing to `620` could surface multiple BMS DIDs simultaneously with no UDS polling overhead. But the odd-length hex suggests the current capture-pipeline is lossy.
4. **`exit_reason` for Phase A.** `exit=completed` after a 30 s run — good. Worth tagging in `client_observations.md` once we see the other reasons (`no_frames_15s`, `watchdog_stall`, `ble_dropped`) in the wild.
5. **`unique_can_ids=2` interpretation.** Bus genuinely sparse, or ELM327 dropping frames that arrived faster than it could forward? Worth a longer 60-90 s Phase A on a different state (e.g., during steady cruise) to see if more IDs show up.

---

## Ссылки для Друг 1 (раздел для пересылки)

- **Сводка**: https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/028-canmonitor-baseline-and-drive/notes-for-drug1.md
- **Bridge changes (commit `c73f0fb`, для контекста)**: https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/028-canmonitor-baseline-and-drive/bridge-changes-for-drug1.md
- **Smoke (5 s sanity check)**:
  - https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/028-canmonitor-baseline-and-drive/smoke/can_monitor_session.csv
  - https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/028-canmonitor-baseline-and-drive/smoke/can_frames.csv
- **Phase A (canmonitor parked Ready ON 30 s)**:
  - https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/028-canmonitor-baseline-and-drive/phase-a/can_monitor_session.csv
  - https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/028-canmonitor-baseline-and-drive/phase-a/can_frames.csv
- **Phase B (livelog drive 25 min, 0 valid)**:
  - https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/028-canmonitor-baseline-and-drive/phase-b/live_log_session.csv
  - https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/028-canmonitor-baseline-and-drive/phase-b/live_log_entries.csv.gz
