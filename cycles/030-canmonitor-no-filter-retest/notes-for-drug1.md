# Cycle 30 — `can_id=620` retest, SP6 no filter override — Notes for Друг 1

**Date**: 2026-05-29
**Bridge cycle**: 30 (single control probe)
**Client**: bz5-companion `0.1.29+32`
**Bridge**: revision `0003`
**Car state**: `parked_ready_on`

---

## TL;DR — **Hypothesis rejected. Path-A is conclusively dead.**

Replicated C28 Phase A's exact setup (SP6, no `filter_commands` field in args, default ELM327 init `AT SP 6 / AT H1 / AT S0 / AT MA`) for 30 s of `parked_ready_on`. **Zero frames, zero unique_can_ids, 15 raw_lines all unparsed.** Exit reason: `no_frames_15s` — client's own auto-stop fired after 15 s of total silence on the bus.

The earlier C28 Phase A capture of 20 frames on `can_id=620` (with payloads that looked like multiplexed BMS DID values) **was not a genuine broadcast**. Most likely explanation: UDS-response echoes from a preceding session that hadn't fully cleared when canmonitor started — consistent with the ELM327 stuck-in-AT-MA bug we later identified in the same C28 run (Phase B failure).

**Path-A is closed. UDS via `bleStartLiveLog` (Path B) remains the only viable extraction route on this hardware/wiring.**

---

## Session row

```
cmd 86 bleStartCanMonitor protocol="6"
  → ack ok in 3 s, result {kind:"canmonitor", started:true}
session id=9, client_session_id=7
duration_sec=30 requested, actual runtime 21 s
notes: "C30 620 retest — SP6 no filter, replica of C28 Phase A | exit=no_frames_15s"
frame_count=0, unique_can_ids=0
```

The client's `no_frames_15s` auto-stop fired at 18:42:15Z (15 s after start), session ended at 18:42:21Z, batch flushed by 18:43:31Z.

---

## What the 15 raw_lines actually were

| ts_ms | raw | parsed | notes |
|---|---|---|---|
| 1000 | `SEARCHING...` | false | first attempt to lock onto bus traffic |
| 1000 | `STOPPED` | false | timeout |
| 2000 | `SEARCHING...` | false | retry |
| 3000 | `STOPPED` | false | timeout |
| 3000 | `OK` × 5 | false | acks for `AT SP 6 / AT H1 / AT S0` / etc default setup |
| 3000-4000 | `SEARCHING...` / `STOPPED` × 4 | false | adapter trying & giving up |
| 5000 | `STOPPED` | false | final, before exit |

**Not a single line that resembles a CAN frame.** All 15 are ELM327 control/status messages.

Interesting: even on SP6 explicitly set, the adapter emitted `SEARCHING...` five times — meaning the ELM327's hardware listener never registered any bus activity that would let it lock baud/format. This is independent of any AT-filter chain.

---

## What this tells us vs C28 Phase A

| Aspect | C28 Phase A (had 20 frames on `620`) | C30 (replication, 0 frames) |
|---|---|---|
| Client version | `0.1.29+28` (early canmonitor) | `0.1.29+32` (current) |
| Protocol | default (no `protocol` argument) | SP6 explicit |
| Filter setup | client default only (no override) | client default only (no override) |
| Bridge state of ELM327 just before | likely contaminated by previous UDS operation (cf. C28 Phase B `MALFORMED` finding) | clean idle (defensive stop returned `stopped=[]`) |
| Result | 20 frames, all on `can_id=620` and one on `014` | 0 frames |

The two material differences are (1) the client now explicitly sets `SP 6` and (2) the adapter wasn't carrying over `AT MA` residue from an earlier session.

Strongest interpretation: **the C28 Phase A frames were stale UDS-response data being read out of the adapter's buffer**, not live broadcast. The `620` payloads in C28 Phase A (`02B 0CC8`, `02D 0CCD`, `015 419B` — exactly the DIDs we'd previously polled via UDS) line up cleanly with that explanation. The bus, in `parked_ready_on`, does not carry broadcast frames that survive ELM327 hardware detection.

---

## Confirmed picture (after C28-C30)

1. **Path-A (passive `AT MA`) is dead** on this hardware/wiring.
   - C29 (5 protocols × 15 s, wide-open filters): 0 frames anywhere
   - C30 (SP6, no filter override, 30 s): 0 frames
   - Bus baud is 500k (C29 P3/P4 250k → `CAN ERROR`), so it's not a baud-rate mismatch
2. **Gateway is whitelist-mode** — or the OBD-II port is wired only to a sub-bus that carries no broadcast traffic in parked-Ready-ON. Same observable end-state either way.
3. **Path-B (`bleStartLiveLog` UDS) is the only working extraction path.** C28 Phase B retry confirmed 98.6% valid response rate on a 10-DID drive.

---

## Recommendation

- Stop investing in Path-A configuration variations. The data is in.
- Continue Path-B campaign: livelog under varying drive states, single-DID high-frequency probes, narrow chunked sweeps past the +27/+30 watchdog cutoff.
- Open C28 takeaways are still actionable: `740/0008` surfaces as a new variable candidate, `790/0015` is confirmed pack-current-shaped, and the `SANITY:NA` / `SANITY:PAIR:-N` errors on cell-pair DIDs are worth a deeper look.

---

## Pipeline notes

### `exit=no_frames_15s` is a useful early-stop signal
Client's auto-stop after 15 s of zero frames means our `duration_sec=30` was a soft upper bound. Bridge happily ingests the partial-duration session — `duration_sec` (in the row) stores the requested value, but `ended_at - started_at` reflects the actual runtime (21 s here, with the 6 s difference being client-side cleanup/flush prep). Worth keeping in mind for future Path-A debugging: if the client gives up after 15 s, you have an explicit signal that the bus produced nothing.

### Bridge contract `0003` continues to behave
- `protocol` field stored as `"6"` and round-tripped intact
- `raw_lines[]` with 15 entries, `parsed=false` on all 15, ingest atomic
- Single POST, no retries (audit confirms one `/v1/data/ingest/canmonitor` 200)

---

## Ссылки для Друг 1

- **Сводка**: https://github.com/AlexTalorJr/cyclesbz5-research/blob/main/cycles/030-canmonitor-no-filter-retest/notes-for-drug1.md
- **CSVs**:
  - Session: https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/030-canmonitor-no-filter-retest/can_monitor_session.csv
  - Frames (empty): https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/030-canmonitor-no-filter-retest/can_frames.csv
  - Raw lines (all parsed=false): https://github.com/AlexTalorJr/bz5-research/blob/main/cycles/030-canmonitor-no-filter-retest/can_raw_lines.csv
