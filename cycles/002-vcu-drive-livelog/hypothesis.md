# Cycle 2 — VCU live log during real drive

**Date issued**: 2026-05-25
**Hypothesis target**: identify pack-current and dynamic-power DIDs
in VCU via cyclic logging during a real drive
**Prerequisite cycles**: `001-vcu-low-scan` (provides 51 candidate DIDs)

## Hypothesis

Pack current and instantaneous power signals will manifest as DIDs
whose values:

1. Approach zero in idle (Cycle 1 baseline already observed)
2. Spike positive during acceleration (motor draws current)
3. Cross zero during cruise (small steady current)
4. Spike **negative** during regen braking (motor sources current
   back to battery — sign reversal is the strong signal we're after)

A real drive over ~30 minutes naturally includes all these phases,
making it a much higher-signal experiment than a stationary
differential sweep. Live log captures all 7 monitored DIDs over the
entire drive with timestamps, enabling later analysis of which DIDs
correlate with which physical events.

## Predictions

If the hypothesis is correct, at least one of the 7 logged DIDs will
show:
- Sign reversal (or large magnitude swing) between accel and regen
- Near-zero values at idle/stop
- Sustained mid-range values during cruise

**Most promising candidates** (chosen as the 7 live-log slots — see
Experiment section). Based on Cycle 1 observations, the strongest
candidates for pack-current behaviour are the 4-byte zero-cluster
DIDs near already-known dynamic ones.

If nothing correlates, pack current is **not** exposed by VCU in
0x0001-0x00FF and Cycle 3 pivots to BMS (790) or scanning higher
VCU ranges.

## Experiment

Single live-log session on VCU (791/799), 7 DIDs, duration = entire
owner drive (~30 minutes).

### DID selection

| Slot | DID | Why this one |
| ---- | --- | ------------ |
| 1 | `0x0038` | known power-A baseline — sanity reference for sign/scale |
| 2 | `0x0039` | adjacent 2× of 0x0038 in idle — test relationship under load |
| 3 | `0x004A` | 4-byte non-zero in idle — known dynamic candidate |
| 4 | `0x004B` | 4-byte non-zero in idle — known dynamic candidate |
| 5 | `0x0046` | 4-byte zero in idle — representative of 0x46-48 cluster |
| 6 | `0x004C` | 4-byte zero in idle — representative of 0x4C-4E cluster |
| 7 | `0x000A` | 4-byte counter at value 6 — test if energy counter |

Not picking:
- `0x0026` (odometer) — known semantics, slot wasted
- 1-byte flags — won't carry current/power magnitude
- `0x0049` (10-byte structured FF-pattern) — interesting but lower
  priority than pack-current candidates
- `0x0043/44/45` (temperature candidates) — different investigation
  thread, deferred to a later cycle

### Command

```json
POST /v1/admin/commands
{
  "device_id": "26305a60-09ec-4c6d-9627-a295141d5ea3",
  "kind": "bleStartLiveLog",
  "args": {
    "did_list": [
      {"tx_ecu": "791", "rx_ecu": "799", "did": "0038"},
      {"tx_ecu": "791", "rx_ecu": "799", "did": "0039"},
      {"tx_ecu": "791", "rx_ecu": "799", "did": "004A"},
      {"tx_ecu": "791", "rx_ecu": "799", "did": "004B"},
      {"tx_ecu": "791", "rx_ecu": "799", "did": "0046"},
      {"tx_ecu": "791", "rx_ecu": "799", "did": "004C"},
      {"tx_ecu": "791", "rx_ecu": "799", "did": "000A"}
    ],
    "car_state": "real_drive_~30min",
    "notes": "Cycle 2 — live log VCU 7 DIDs during real drive for pack-current/regen identification"
  },
  "timeout_ms": 2400000
}
```

`timeout_ms = 2_400_000` = 40 minutes — allows for the full drive
plus margin. (CLIENT_API §7.3 caps at `le=600_000` ms = 10 min for
the **command** timeout, BUT this gates only the dispatch-to-start
window; the live log session itself runs until `bleStopActiveOperation`
or the head unit's own session cap.)

If the command-timeout cap is 600 s and that breaks dispatch — drop
to 600000 and bridge Claude POSTs the command **right when the
owner is about to start driving** so the dispatch happens fast and
the actual session runs as long as the head unit allows.

### Owner instructions during drive

**Drive normally.** No special manoeuvres required — the natural
variety of a real drive (acceleration, cruise, braking, regen,
stops at lights, possibly a highway segment) is exactly what we
need.

**Optional but helpful** if it's safe and convenient:
- Note approximate clock time of:
  - Drive start (gear out of P)
  - First substantial acceleration
  - First substantial regen / coast-down
  - Highway entry / exit (if applicable)
  - Drive end (gear back to P)
- These help correlate VCU DID readings to physical events during
  analysis. If forgotten, the data itself will reveal patterns from
  shape of the curves; correlation just sharpens interpretation.

**What you don't need to do**:
- Don't avoid AC / climate (owner had it off in Cycle 1; if you
  use it during drive that's fine — we're investigating VCU not
  HVAC right now, and any HVAC-induced power changes are part of
  the "real driving" signal we want)
- Don't drive in unusual ways for the experiment — natural driving
  gives the best mix of states

### Session termination

When owner reaches destination and parks (Ready OFF or P):

1. Bridge Claude (when notified by owner "drive ended") POSTs
   `bleStopActiveOperation` to stop the live log
2. Head unit ingests final live-log batch to server
3. Bridge Claude exports raw CSVs from `live_log_sessions` +
   `live_log_entries` tables and commits to repo

If the live-log session has already auto-terminated due to head unit
session cap (we'll learn the cap from this experiment if it
happens), bridge Claude exports whatever was captured.

## Branching plan

| Outcome | Implication | Next cycle direction |
| ------- | ----------- | -------------------- |
| A | One or more 4-byte DIDs show clean sign-reversal (positive accel, negative regen) → **pack-current found** | Cycle 3 = controlled experiment to nail down scale/units (constant-speed cruise, controlled regen) |
| B | 0x0038/0x0039 track power but no sign reversal in any DID (always positive magnitude) | Pack current is NOT in VCU low-byte as signed value. Cycle 3 = BMS (790) low-byte sweep |
| C | Several DIDs vary chaotically with no clear pattern | Re-run with simpler car-state experiments (idle hold, single ramped accel, then coast/regen) to isolate signals |
| D | `0x000A` increments during drive → energy counter found | Bonus finding — investigate scale + add to known_dids |
| E | Live log fails / session caps too early / errors | Infrastructure issue, capture whatever we got and adjust Cycle 3 around limitations |

## Constraints / prerequisites

- Owner is about to drive — Cycle 2 must dispatch **before** drive
  starts so live log captures from drive start
- Head unit Ready ON, BridgeDiag toggle ON, long-poll alive
- Bridge Claude needs to POST `bleStartLiveLog` quickly upon owner's
  "GO" signal (within ~30 seconds of intended drive start)
- Owner notifies bridge Claude when drive ends → bridge Claude POSTs
  `bleStopActiveOperation`
- After session ends and ingest completes, bridge Claude commits raw
  CSVs to repo. **Gzip them** (`.csv.gz`) — expected size ~30k+ rows,
  raw CSV may exceed 100 KB threshold

## Notes for bridge Claude

**Owner has explicitly asked: do not analyse the live-log values
or draw conclusions about parameter dynamics — just deliver the raw
CSVs (gzipped if >100KB) to the repo.** Pattern recognition and
interpretation is the companion Claude role.

You may, however, flag operational issues:
- Live-log session aborted unexpectedly?
- Head unit went offline mid-drive?
- Ingest failures, retries?
- Total row count and time range of captured data?

These are infrastructure observations and useful context for the
analysis — they're separate from data interpretation.

### Recommended commit shape

```
cycles/002-vcu-drive-livelog/
├── hypothesis.md          ← already committed (this file)
├── command.start.json     ← bridge Claude commits: POST body + response for bleStartLiveLog
├── command.stop.json      ← bridge Claude commits: POST body + response for bleStopActiveOperation
├── raw/
│   ├── live_log_sessions.csv      ← \copy of the one session row
│   └── live_log_entries.csv.gz    ← \copy of all entries (gzipped)
├── analysis.md            ← companion Claude after analysis
└── next.md                ← companion Claude
```
