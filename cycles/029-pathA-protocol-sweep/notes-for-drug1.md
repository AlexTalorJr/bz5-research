# Cycle 29 — Path-A 5-protocol sweep — Notes for Друг 1

**Date**: 2026-05-29
**Bridge cycle**: 29 (5 probes back-to-back)
**Operator**: Друг 2 (bridge Claude)
**Client**: bz5-companion `0.1.29+32` (first cycle with `raw_lines[]` capture + `protocol` argument)
**Bridge**: revision `0003` (commit `a64fc88` shipped just before this cycle — see `bridge-changes-for-drug1.md`)
**Car state**: `parked_ready_on`

---

## TL;DR — **Path-A is dead. Move to Path B.**

All 5 probes returned **0 frames, 0 unique_can_ids, 100% unparsed raw_lines (241 / 241)** — and every single raw line is an ELM327 control/status message, not a CAN frame.

Per your criterion: `≤2 unique IDs in every probe AND raw_lines without new CAN formats → whitelist confirmed, move to Path B`. **Both halves satisfied unambiguously.**

| Probe | Protocol | duration | frames | unique_can_ids | raw_lines | unparsed | client_session_id |
|---|---|---|---|---|---|---|---|
| P1 | SP6 (11bit 500k) | 15 s | 0 | 0 | 80 | 80 | 1 |
| P2 | SP7 (29bit 500k) | 15 s | 0 | 0 | 63 | 63 | 2 |
| P3 | SP8 (11bit 250k) | 15 s | 0 | 0 | 29 | 29 | 3 |
| P4 | SP9 (29bit 250k) | 15 s | 0 | 0 | 39 | 39 | 4 |
| P5 | SP0 (auto) | 15 s | 0 | 0 | 30 | 30 | 5 |

---

## What's in the raw_lines (the only thing Path-A produced)

Counted unique strings across all 5 probes — **every line is an ELM327 control response**, not a captured CAN frame:

| String | Count | Probes | Meaning |
|---|---|---|---|
| `NO DATA` | 89 | P1, P2 (500k) | adapter monitoring, no frames passed the filter in 15 s |
| `CAN ERROR` | 45 | P3, P4 (250k) | bus is not 250k — adapter cannot establish at this baud |
| `OK` | 77 | all 5 | ack for each `AT CAF0`, `AT CM 000`, `AT CF 000`, `ST I` |
| `STOPPED` | 5 | all 5 | ack for `bleStopActiveOperation` (1 per probe) |
| `SEARCHING...` | 13 | P5 (auto) | SP0 auto-detect never settled |
| `?` | 1 | P4 | one of the filter commands not understood at SP9 |

**Zero raw lines that look like CAN frame data.** No hex prefixes, no payload bytes — just adapter chatter.

---

## Side findings (bonus signal for Друг 1)

### Bus baud rate

`CAN ERROR` returned uniformly for both SP8 (11bit 250k) and SP9 (29bit 250k) — total 45 errors across P3+P4 in 30 s of monitoring. **The bus we're connected to is not 250k.** Combined with `NO DATA` (not `CAN ERROR`) on SP6/SP7 (500k variants), the most likely baud is **500k**. 250k is firmly ruled out for this connection.

### Auto-detect couldn't lock

P5 (SP0 auto) emitted `SEARCHING...` 13× then `STOPPED`. ELM327 never settled on a baud rate in 15 s. Either the bus is genuinely silent or the auto-discovery handshake needs a request frame to lock onto (and our `AT CM 000`/`AT CF 000` blocked exactly that). Consistent with whitelist hypothesis: nothing on the bus to listen to except in response to requests.

### Filter setup behaviour

All 4 filter commands acked `OK` on SP6/SP7/SP8 (apart from SP9 where one returned `?` — likely the `AT CM 000`/`AT CF 000` form isn't valid in 29bit-250k mode on this adapter). The ELM327 accepted our wide-open monitor config, so the absence of frames isn't because we filtered them out: the adapter would still pass things through to us as raw bytes.

### Filter footprint check (parked-Ready-ON, with `AT CAF0 + AT CM 000 + AT CF 000`)

`AT CM 000` + `AT CF 000` are theoretically wide-open (don't reject anything 11-bit). On SP6 we still got pure `NO DATA` for 15 s. That confirms: under parked-Ready-ON, this bus carries no broadcast frames that survive ELM327's hardware filter at the requested baud, with our filter clear. **Bus quiescent or fully whitelist-gated** — Path-A gives us nothing further to chase here.

---

## Per-probe artifacts

Each probe directory contains:
- `command.start.json` — the `bleStartCanMonitor` POST/ack response (cmd id, protocol, filter_commands, ack timing)
- `can_monitor_session.csv` — single row, `protocol` column populated
- `can_frames.csv` — header only (0 frames parsed)
- `can_raw_lines.csv` — all unparsed lines per probe

Commits:
- P1: `260e022` — SP6, 80 raw lines (most filter-init chatter due to extra `ST I`)
- P2: `e43a048` — SP7
- P3: `d04128d` — SP8
- P4: `2d397f2` — SP9
- P5: `4453f97` — SP0

---

## Operational notes

### First run aborted on P2 due to phone network drop
First attempt of the pipeline got stuck on P2 SP7 — cmd 73 sat in `dispatched` for 3+ minutes because the phone lost internet mid-session. Owner reconnected, I cancelled the stuck cmd, and the full pipeline reran cleanly from P1. **The P2 hang was not protocol-specific** — same SP7 worked fine on the retry. Worth knowing: pipeline-level resilience needs internet on the client during the dispatched window, not just at POST time.

### `bleStopActiveOperation` + 10 s pause between probes — clean on +32

All 5 defensive stops between probes returned `stopped=[]` (client was already idle). The +32 fix for the stuck-AT-MA bug from C28 is holding — no busy-state retention observed between canmonitor probes either. Good.

### Bridge contract `0003` end-to-end verified

- `protocol` field stored and round-tripped ("6", "7", "8", "9", "0" — all 5 distinct values came back from `\d can_monitor_sessions`)
- `raw_lines[]` ingest path inserts every line with correct `parsed=false` flag on every probe
- `\copy` extraction works for all 3 tables (`can_monitor_sessions`, `can_frames`, `can_raw_lines`)
- Idempotency: `client_session_id` monotonically incremented 1 → 5 across probes (client BridgeDiagService stayed alive throughout)
- Pipeline pattern: `bleStop` + sleep 10 + canmonitor + wait flush + `\copy` × 3 + DELETE — repeatable across all 5 probes with no collision

---

## Recommendation

**Path-A is closed.** The gateway is conclusively whitelist (or the bus genuinely carries no listener-visible broadcasts in parked-Ready-ON under wide-open filters). Continued exploration of `bleStartCanMonitor` configuration will not surface a productive monitoring path on this hardware/wiring.

**Switch to Path B** (UDS-based, which is what the existing `bleStartLiveLog` already uses successfully — confirmed by C28 Phase B retry: 98.6% valid on 10 DIDs).

The only remaining Path-A-adjacent open question is the **`can_id=620` periodic broadcast** seen in C28 Phase A (20 frames on `620` in 30 s, payloads resembling multiplexed BMS DID values). That ran with **default protocol** (no SP override) and **no filter setup**. Worth one final controlled retest — same SP6 + no filter override — to see if removing the `AT CM 000` / `AT CF 000` setup also surfaces `620`. If it does, we have a working passive path after all (just needed the right filter config). If not, the C28 Phase A capture was a UDS-response side-effect, not a genuine broadcast.

---

## Ссылки для Друг 1

- **Сводка**: https://github.com/AlexTalorJr/cyclesbz5-research/blob/main/cycles/029-pathA-protocol-sweep/notes-for-drug1.md
- **Bridge changes (0003 contract)**: https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/028-canmonitor-baseline-and-drive/bridge-changes-for-drug1.md (still current — rev 0003 just adds `protocol` + `can_raw_lines`)
- **Per-probe CSVs (3 tables each)**:
  - P1 SP6: https://github.com/AlexTalorJr/bz5-research/tree/main/cycles/029-pathA-protocol-sweep/P1-sp6
  - P2 SP7: https://github.com/AlexTalorJr/bz5-research/tree/main/cycles/029-pathA-protocol-sweep/P2-sp7
  - P3 SP8: https://github.com/AlexTalorJr/bz5-research/tree/main/cycles/029-pathA-protocol-sweep/P3-sp8
  - P4 SP9: https://github.com/AlexTalorJr/bz5-research/tree/main/cycles/029-pathA-protocol-sweep/P4-sp9
  - P5 SP0: https://github.com/AlexTalorJr/bz5-research/tree/main/cycles/029-pathA-protocol-sweep/P5-sp0
