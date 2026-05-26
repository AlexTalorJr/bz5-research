# C12 — 3-ECU Pack-Current Hunt — Notes for Друг 1

**Date**: 2026-05-26 (UTC)
**Bridge cycle**: 12
**Operator**: bridge Claude
**Client**: bz5-companion `0.1.29+24` (NOT +25 as initially noted — see *Initial attempt* below)

---

## TL;DR

- One planned 10-DID livelog session was **split into two 7-minute sessions** because the client rejected `did_list>7` with `error_kind=validation`. Cap appears unchanged from +24.
- Both sessions completed cleanly. **Three anchor DIDs (`791/0026`, `791/0038`, `790/0015`) appear in both** for cross-session timeline alignment.
- **C12a — pack-current hunt session**: all 4 pack-current candidates + VCU references.
- **C12b — residual session**: PDU `0008` + BMS `002B`/`002D` + the 3 anchors.
- **Two pack-current candidates are dead**: `790/0030` and `790/0032` are *constant* across 7 minutes of driving (1 unique value each). They cannot be pack current. Likely "unsupported" or "static config".
- New client-side validation observed in C12b: **`SANITY:PAIR:-N`** error codes on `790/002B` and `790/002D` — paired DIDs, failing at the same cycles. Suggests the client now does inter-DID consistency checks (was not visible in C11).
- Open question from C11 (is `740/0023` really pack current?) **was not retested** in C12 — owner deliberately moved on to the 4-candidate hunt.

---

## Sessions at a glance

| Field | C12a (session 8) | C12b (session 9) |
|---|---|---|
| Bridge `live_log_sessions.id` | 8 *(then DELETEd before C12b to clear collision risk)* | 9 *(currently in DB)* |
| `client_session_id` | 1 | 2 *(same BridgeDiagService runtime — counter incremented naturally)* |
| Start ack cmd | id=25, ack 16:00:31Z | id=28, ack 16:35:28Z |
| Stop ack cmd | id=26, ack 16:07:23Z | id=29, ack 16:42:12Z |
| `started_at` (bridge) | 2026-05-26T16:00:27Z | 2026-05-26T16:35:11Z |
| `ended_at` (bridge) | 2026-05-26T16:07:20Z | 2026-05-26T16:42:09Z |
| Duration | 6m53s | 6m58s |
| Cycle count | 191 | 271 |
| Entry count | 1331 | 1625 |
| Cycle period | ~2.16s/cycle (7 DIDs) | ~1.54s/cycle (6 DIDs) |
| Flush latency post-stop | ~54s | ~39s |
| Error rows | 0 | 50 (see *Anomalies*) |

There is a **~28-minute gap** between sessions (16:07:20Z → 16:35:11Z) due to phone network loss after C12a; first C12b attempt (cmd 27) timed out with `dispatched_at=null`. Retry as cmd 28 succeeded after owner's phone reconnected.

## DID coverage

### C12a — 7 DIDs (pack-current hunt)
| DID | Role | Why included |
|---|---|---|
| `791/0026` | **Anchor** — VCU odo / speed | Known from C1; time-alignment ref |
| `791/0038` | **Anchor** — VCU power-A | Known from C1; correlates with motion |
| `791/0039` | VCU power-B candidate | From C5 — varies in drive |
| `740/0009` | PDU pack-current candidate | Owner-flagged candidate |
| `790/0015` | **Anchor** — BMS pack-current candidate | Cross-session anchor; also a candidate |
| `790/0030` | BMS pack-current candidate | Owner-flagged candidate |
| `790/0032` | BMS pack-current candidate | Owner-flagged candidate |

### C12b — 6 DIDs (residual + anchors)
| DID | Role | Notes |
|---|---|---|
| `791/0026` | **Anchor** — VCU odo / speed | Same as C12a — alignment |
| `791/0038` | **Anchor** — VCU power-A | Same as C12a — alignment |
| `790/0015` | **Anchor** — BMS pack-current candidate | Same as C12a — alignment |
| `740/0008` | PDU misc | Not previously tested as pack-current |
| `790/002B` | BMS misc | Paired with 002D — see anomaly below |
| `790/002D` | BMS misc | Paired with 002B — see anomaly below |

## Per-DID first-look stats

### C12a (190–191 samples per DID)

| DID | uniq | min raw | max raw | Comment |
|---|---|---|---|---|
| `791/0026` | 22 | `62002600007345` | `62002600007345..735A` | odo +21 ticks over 6m53s |
| `791/0038` | 79 | `6200380325` | `62003807D6` | wide range 805..2006 — varying with drive |
| `791/0039` | 81 | `6200390647` | `6200390B2A` | wide range 1607..2858 — also varying |
| `740/0009` | 40 | `620009030A` | `620009046D` | narrow 778..1133 — tight cluster on `03D5/D6/D7` |
| `790/0015` | 38 | `6200153A5F` | `6200154916` | range ~15967..18710 |
| `790/0030` | **1** | `62003000` | `62003000` | **constant zero — not pack current** |
| `790/0032` | **1** | `6200323B` | `6200323B` | **constant 0x3B=59 — not pack current** |

### C12b (270–271 samples per DID; 50 paired error rows on 002B/002D)

| DID | uniq | min raw | max raw | Comment |
|---|---|---|---|---|
| `791/0026` | 30 | `6200260000746B` | `6200260000748B`/`7488` | odo +29 ticks over 6m58s |
| `791/0038` | 137 | `6200380325` | `6200380D3F` | wider than C12a (805..3391) — more dynamic drive |
| `790/0015` | 39 | `6200153A0A` | `6200154327` | matches C12a profile — **anchor consistent** |
| `740/0008` | 165 | `6200080000` | `62000803C7` | wide variation 0..967 — looks like a "real" signal |
| `790/002B` | 98 | *(some err rows)* | `62002B0D20` | actively varying, but 25 paired error rows |
| `790/002D` | 97 | *(some err rows)* | `62002D0D28` | mirrors 002B's profile and error pattern |

## Anomalies / things to note

### 1. **`SANITY:PAIR:-N` errors on 002B/002D (NEW in +24 or +25)**
50 error rows total. Always paired (25 on `002B` + 25 on `002D` at the same cycles 34..232).
Error code format: `SANITY:PAIR:-N` where N ∈ {-1, -2, -3, -4, -5, -7, -8, -9, -11, -12, -15, -21, -52, -107}.
- Looks like a client-side inter-DID consistency check.
- The negative values may be the delta the client computed between the two readings.
- This was NOT visible in C11 (no error codes were recorded).
- Suggests +24 (or whichever runtime the device is currently on) has built-in domain knowledge about which DIDs should correlate. Worth a probe.

### 2. **`790/0030` and `790/0032` are functionally dead** for the pack-current hypothesis
- 190 consecutive cycles, single unique value each, across 7 minutes of mixed driving.
- `0030` returned `62003000` (just `0x00` payload, 1 byte).
- `0032` returned `6200323B` (single byte `0x3B=59`).
- Neither responds to motion → can be dropped from future pack-current sweeps.

### 3. **Cycle rate scaling with DID count**
- 7-DID session: ~2.16 s/cycle
- 6-DID session: ~1.54 s/cycle
- Ratio observed 0.71 vs. expected linear 6/7 = 0.86 — cycles got faster than a 1-DID drop should explain. Either client batching overhead is non-linear, or some per-cycle setup work scales with DID count. Not blocking, but a curiosity if Друг 1 is tuning cycle budgeting.

### 4. **Client falls asleep after BLE session**
After C12a's flush completed at 16:08:14Z, the device stopped heartbeating until 16:33:48Z (~25 min silence). Owner reported "сеть отвалилась в телефоне". When the network came back, BridgeDiagService resumed and picked up cmd 28 within ~270 ms.
Cmd 27 (first C12b attempt at 16:10:15Z) never reached the device — `dispatched_at` stayed `null` and the timeout sweeper killed it at 16:17:29Z.

### 5. **Initial attempt — 10-DID rejected**
Before splitting, I posted the full 10-DID list as cmd 24 at 15:49:05Z. Client returned `error="did_list must have at most 7 entries, got 10"`, `error_kind=validation`, after ~294 ms dispatch→finish. No BLE work, no `live_log_sessions` row. **The 7-DID cap is still in force in +24** — owner's note "after +25" assumed the cap was lifted; it wasn't (or +25 wasn't installed).

## Raw data & artifacts

All in `cycles/012-3ecu-pack-current-hunt/`:

```
command.start.json    — cmd 24 request+response (the failed 10-DID attempt)
command.error.json    — cmd 24 terminal state, post-mortem
c12a-session.json     — session 8 metadata (from live_log_sessions row)
c12b-session.json     — session 9 metadata
raw/c12a-livelog.csv  — 1331 rows, 72.5 KB, columns: id,session_id,timestamp,ecu_tx,did,raw_hex,error_code,cycle
raw/c12b-livelog.csv  — 1625 rows, 90 KB
notes-for-drug1.md    — this document
```

Bridge DB state at end of cycle:
- `live_log_sessions` id=9 (C12b) retained for now
- `live_log_sessions` id=8 (C12a) was DELETEd after `\copy` to avoid `client_session_id` collision risk for C12b — raw CSV is canonical
- All commands (24, 25, 26, 27, 28, 29) preserved in `commands` table for audit

## Open questions for analysis

1. **Which of `740/0008`, `740/0009`, `790/0015`, `791/0039` correlates best with `791/0038` (power-A)?** That's the pack-current test.
2. **What is `SANITY:PAIR:-N` checking** between `002B`/`002D`? Negative delta of what? Cell-pair voltage delta? Worth a single-pair livelog with much higher cycle rate.
3. **What's `740/0008`'s actual physical meaning?** Wide-varying PDU signal we haven't characterized.
4. **Is the 7-DID cap intentional in +24/+25,** or does Друг 1 want to lift it in +26? With 7 we lose efficient 3-ECU sweeps.

## Pointers
- Repo: https://github.com/AlexTalorJr/bz5-research, branch `main`, commits `9f272b0` (C12a) and `5d6d071` (C12b).
- Reference docs (Друг 1 owns): `reference/known_dids.md`, `reference/decoded_semantics.md`, `reference/client_observations.md` — I have NOT edited these.
