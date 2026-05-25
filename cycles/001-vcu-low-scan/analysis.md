# Cycle 1 — Analysis

**Date analyzed**: 2026-05-25
**Data sources**: `raw/sweep_runs.csv`, `raw/sweep_results.csv`,
`command.json`

## Observations

Sweep completed successfully: 255 valid UDS positive responses, zero
NRCs, zero timeouts. Duration 28 seconds (BLE-bound — see infrastructure
findings below). Run id=1, command id=1.

Distribution of payload sizes (after stripping SID 0x62 and DID echo):

| Payload bytes | Count |
| ------------- | ----- |
| 0             | 204   |
| 1             | 26    |
| 2             | 13    |
| 4             | 10    |
| 7             | 1     |
| 10            | 1     |
| **Total**     | 255   |

This distribution itself is the first significant finding (see next
section). The 51 DIDs with payload split into clusters by size.

### All 51 DIDs with payload (sorted by DID)

| DID  | Bytes | Payload (hex) | Notes |
| ---- | ----- | ------------- | ----- |
| 0001 | 1 | 00 | flag-like |
| 0002 | 1 | 00 | flag-like |
| 0003 | 1 | 00 | flag-like |
| 0004 | 1 | 00 | flag-like |
| 0005 | 1 | 02 | small enum |
| 0006 | 1 | 01 | small enum |
| 0007 | 1 | 00 | flag-like |
| 0008 | 2 | 0001 | small counter or limit |
| 0009 | 2 | 0001 | small counter or limit |
| 000A | 4 | 00000006 | counter (32-bit, value 6) |
| 000B | 2 | 0002 | small enum/counter |
| 000C | 2 | 0000 | could be dynamic-but-currently-zero |
| 000D | 2 | 0000 | could be dynamic-but-currently-zero |
| 000E | 1 | 00 | flag |
| 0016 | 1 | 03 | small enum |
| 001D | 1 | 00 | flag |
| 001F | 1 | 47 | = 71 decimal, single byte |
| 0020 | 1 | 00 | flag |
| 0021 | 1 | 00 | flag |
| 0022 | 1 | 00 | flag |
| 0024 | 1 | 00 | flag |
| 0025 | 2 | 0000 | dynamic candidate |
| 0026 | 4 | 000070CD | **odometer, baseline ✓** |
| 002F | 1 | 00 | flag |
| 0036 | 2 | 0000 | dynamic candidate |
| 0037 | 2 | 0000 | dynamic candidate |
| 0038 | 2 | 0326 | **power-A, baseline ✓** (= 806 decimal) |
| 0039 | 2 | 0647 | **adjacent to 0038, value ≈ 2× of 0038** |
| 0040 | 2 | 0000 | dynamic candidate |
| 0041 | 2 | 0000 | dynamic candidate |
| 0042 | 2 | 0000 | dynamic candidate |
| 0043 | 1 | 28 | = 40 decimal — plausibly **temperature °C** |
| 0044 | 1 | 1B | = 27 decimal — plausibly **temperature °C** |
| 0045 | 1 | 1B | = 27 decimal — paired with 0044 |
| 0046 | 4 | 00000000 | 4B zero — dynamic candidate |
| 0047 | 4 | 00000000 | 4B zero — dynamic candidate |
| 0048 | 4 | 00000000 | 4B zero — dynamic candidate |
| 0049 | 10 | 0000FFFFFF0000FFFFFF | structured: `(2B,3B) × 2` |
| 004A | 4 | 025701FF | **4B non-zero — strong dynamic candidate** |
| 004B | 4 | 01880292 | **4B non-zero — strong dynamic candidate** |
| 004C | 4 | 00000000 | 4B zero — dynamic candidate |
| 004D | 4 | 00000000 | 4B zero — dynamic candidate |
| 004E | 4 | 00000000 | 4B zero — dynamic candidate |
| 0050 | 1 | 00 | flag |
| 0051 | 1 | 00 | flag |
| 0052 | 1 | 03 | small enum |
| 0053 | 1 | 00 | flag |
| 0054 | 1 | 00 | flag |
| 0055 | 1 | 00 | flag |
| 0056 | 7 | 00000000000000 | 7B zero — unusual width, candidate |
| 0057 | 1 | 01 | flag-like |

## Interpretation

### Finding 1: zero-payload responses are an anomaly (high confidence)

204 of 255 DIDs return `62 XX XX` with zero data bytes. This is unusual
UDS behaviour. Typical VCUs return either a positive response with
data, or NRC 0x31 (Request Out Of Range) for unsupported DIDs. The
fact that this VCU returns a zero-byte positive ACK suggests:

- DIDs in this range are **declared** but data is intentionally
  withheld (possibly session-level or security-level dependent), OR
- VCU implementation returns positive ACK as the default fallback
  even for unsupported DIDs (anti-fingerprinting? or sloppy impl)

Implication: we cannot trust "no NRC" as "DID is implemented and live".
The real population of meaningful DIDs in 0x0001-0x00FF on VCU is the
**51 with non-zero payload** (the others may or may not exist
functionally). This narrows the search significantly.

### Finding 2: temperature-cluster at 0x0043-0x0045 (medium confidence)

Three adjacent 1-byte DIDs reading 0x28, 0x1B, 0x1B = 40, 27, 27 °C
in an idle parked Ready state are very plausibly **temperature
sensors** (cabin / ambient / one-of-two BMS-aux or similar). The
identical 27/27 pair at 0044/0045 looks like paired symmetric
sensors. Decoding TBD; flagged for live-log confirmation during a
state-change experiment.

### Finding 3: adjacent power DIDs at 0x0038/0x0039 (medium confidence)

0x0038 (known baseline: power-A magnitude) reads 0x0326 = 806.
0x0039 reads 0x0647 = 1607. Ratio ≈ 1.99. In an idle Ready state,
the relationship 2× is too clean to be coincidence — these are
likely related signals. Hypotheses:
- 0x0038 = filtered/averaged power, 0x0039 = instantaneous/peak
- 0x0038 = magnitude, 0x0039 = signed (positive direction only here)
- 0x0038 and 0x0039 are in different units (e.g. W vs. W×2 = 0.5 W
  unit)
- Coincidence (low probability given the cleanness)

Confirming the relationship requires watching both during a real
power change.

### Finding 4: 4-byte non-zero pair at 0x004A/0x004B (medium confidence)

The 4-byte cluster 0x0046-0x004E is mostly zero. The two non-zero
entries 0x004A=025701FF and 0x004B=01880292 stand out and likely
carry **dynamic** data even at idle:
- 0x004A=025701FF: parses as (0x0257, 0x01FF) = (599, 511) if
  two 16-bit values, or 39,322,623 as single uint32
- 0x004B=01880292: parses as (0x0188, 0x0292) = (392, 658) two
  16-bit, or 25,691,794 as single uint32

The all-zero surrounding 4-byte fields (0046-48, 004C-E) cannot be
distinguished as "always zero" vs. "dynamic but currently zero" with
a single sweep. **Pack current at idle would round to ~0 in any
reasonable scale**, so these are still candidate slots.

### Finding 5: structured 10-byte field at 0x0049 (low confidence)

0x0049 = `0000FFFFFF 0000FFFFFF` splits symmetrically as two
identical `(2B zero, 3B FF)` halves. Possible structure:
- Two reserved/inactive slots with FF-filled "no data" markers
- Two paired (value=0, flags=FFFFFF) fault/status fields
- Two min/max threshold pairs

This DID is unique in its width (10 bytes — no other DID in the
range has this size). Worth investigating later, but lower priority
than finding pack-current.

### Anti-matches

DIDs that are *unlikely* to be pack-current based on Cycle 1:
- `0x000A = 6` — too small a value for a fresh counter; if this
  were lifetime energy in Wh, the car has driven only 6 Wh which
  is implausible. If 0.001 kWh, 6 × 0.001 = 0.006 kWh; same issue.
  Likely a different kind of counter (boot count? state machine?)
- `0x0001-0x0004, 0x0007, 0x000E, 0x001D, 0x0020-0x0022, 0x0024,
  0x002F, 0x0050-0x0055` — single-byte flags reading 0, no scale
  for pack current
- `0x0005 = 02, 0x0006 = 01, 0x0007 = 00` — small enums, more
  likely state machine or feature flags than current

### Infrastructure observations (not the experiment focus, but
recorded)

Two client-side bugs visible in the run output, reported by bridge
Claude:

1. **`args.notes` not propagated**: bridge Claude POSTed
   `notes: "Cycle 1 — VCU low-byte scan for power/current DIDs"`
   but `sweep_runs.notes` reads `"started via bridge command"`
   (hardcoded). The user-provided notes were dropped by
   `BridgeDiagService` between command dispatch and sweep_runs
   insertion. **Action**: add to bz5-companion bug list — fix in a
   future client patch.

2. **`period_ms=250` not honoured**: 28 seconds for 255 DIDs ≈
   110 ms per DID. Either `period_ms` is ignored, or 110 ms is the
   BLE round-trip floor and `period_ms` only sets a *minimum*
   interval that the actual cadence may exceed. Either way, this is
   the practical sweep rate cap. **Implication for planning**:
   sizing future sweeps assume ~110 ms × N DIDs.

## Branching decision

Outcome is closest to **A** (multiple new candidate DIDs visible)
but with a caveat: I cannot distinguish dynamic from static DIDs
with a single sweep. Picking 7 DIDs for live log is premature.

**Picking a better Cycle 2 path**: do a *differential* sweep — repeat
the same scan in a deliberately changed car state. DIDs that differ
between the two sweeps are dynamic. This narrows the live-log
candidate list materially before we spend the 7-DID live-log slot.

Proposed state change: vehicle in **D with brake pressed** (motor
torques against brake → real pack-current flow → VCU must coordinate
it). Safe and short (no movement), and produces a much bigger signal
than parked-Ready idle. See `cycles/002-vcu-state-differential/`.

## Next cycle

See `cycles/002-vcu-state-differential/hypothesis.md`.
