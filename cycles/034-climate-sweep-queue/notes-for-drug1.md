# Cycle 034 — climate sweep queue (bleStartSweepQueue, first run)

**When:** 2026-10-22 15:25:46–15:37:21 UTC (11 min 35 s for 5 ECUs).
**Device:** head unit `3e401db7`, client 0.2.22+221, bridge command 115 (`command.json`).
**Car state:** P + Ready, climate AUTO 19 °C, A/C on. Outside ~9 °C.
**Range:** DID `0000–03FF` (1024 DIDs) on each of 722, 755, 716, 744, 760. RX = TX+8.

## Outcome

Every ECU answered every DID; all five runs `exit=completed`, 1024 results each,
no `silent_ecu`, no `ble_wedged`, no `TIMEOUT`, one `NO_DATA` (722/0003).
Negative response `7F 22 31` (requestOutOfRange) is instant, so an ECU took
~1 min 50 s instead of the planned 7.5 min; 760 took 4 min 13 s.

| ECU | positive DIDs | notes |
|---|---|---|
| 722 | 7 | 0001, 0004, 0005, 000E, 0100, 0105, 0200 |
| 755 | 5 | 0105, 0111, 0112, 0113, 0116 |
| 716 | 1 | 0105 only |
| 744 | 15 | 0007–0009, 0010–0015, 0017, 0018, 0021, 0022, 0024, 0105 |
| 760 | 1 | 0105 only |

`0105` answers on all five ECUs with an ASCII part-number-like string
(`"88734030 0 "`, `"88370030 30"`, `"88162030 40"`, `"881B0030 50"`,
`"881D0030 20"`) — looks like a per-ECU identification DID, not a signal.

744 is the richest: 0007–0024 look like live values (`0008=02DD`, `0009=03D9`,
`0014=45DD`, `0022=463C`, `0018=000057E44650`, and the 100-byte blob at `0024`).
Candidates for compressor / climate state worth a livelog under changing
setpoint and A/C on/off.

## Files

- `raw/sweep_runs.csv` — the five run rows (ids 39–43).
- `raw/sweep_results.csv.gz` — all 5120 probes (run, ecu, sequence, did, raw_hex, error_code).
- `raw/positive_dids.csv` — the 29 non-7F responses.
- `command.json` — the bridge command as enqueued and acknowledged.

## Bridge side, for the record

First end-to-end run of: `bleStartSweepQueue` whitelist (`18496ae`), sweeps
upsert + `UNIQUE (sweep_run_id, sequence)` (`0d5d091`, migration 0021), and the
+221 client holding runs until `ended_at` — each run arrived once, complete,
with its exit reason. The morning runs 37/38 (+220) stay truncated: the head
unit was reinstalled before the cursor reset and sweeps are not in the cloud
restore set.
