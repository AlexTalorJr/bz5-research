# C33 — DC fast-charge pack-current calibration (790/0009)

**TL;DR for the one-line client patch:**

```dart
// connection.dart — replace the PROVISIONAL constants
static const int    _kPackCurrentZeroRaw    = 5018;     // was provisional
static const double _kPackCurrentAmpsPerLsb = 0.1021;   // A/LSB, was 0.05 (~2x low)
// I_amps = (raw - 5018) * 0.1021 ;  charge < 0, discharge > 0
```

`790/0009` (rx 798) is confirmed as the BMS pack-current readout. The provisional
`0.05 A/LSB` underestimated power ~2x; the calibrated value is **0.1021 A/LSB**
(2.04x), which matches the owner's "90 km/h shows 8–9 kW vs real ~15 kW".

## Method

LiveLog with 3 DIDs (`790/0009` current, `790/0015` pack V, `791/0038` motor power
cross-check) during a real DC fast-charge from 10.7% SOC. Decode: response is
`62 <DID:2B> <u16 BE>`; strip the 6-hex prefix, parse the next 4 hex as a big-endian
u16 = `raw`. Owner recorded the **station's** current/voltage/power at three
timestamps (external ground truth). Charge = current INTO pack = **negative**.

## Anchor points (station = ground truth)

| t (UTC) | station | raw `790/0009` (median ±25 s) | model `(raw-5018)*0.1021` | residual |
|---------|---------|-------------------------------|---------------------------|----------|
| 14:59:30 (t0, no current yet) | 0 A | 5019 | +0.1 A | +0.1 |
| 15:02 | −181 A (86.0 kW / 474 V) | 3213 | −184.3 A | −3.3 |
| 15:05 | −186 A (90.0 kW) | 3205 | −185.1 A | +0.9 |
| 15:08 | −198 A (95.8 kW) | 3101 | −195.8 A | +2.2 |

Least-squares over the 4 points → **ampsPerLsb = 0.10214**, **zeroRaw = 5017.6**
(rounded to 5018). The measured zero at t0 (flat raw 5019 before current flowed)
independently confirms the offset — no separate parked-zero capture was needed.

Residuals ≤ 3.3 A across 0–198 A.

## Cross-validation against C32 drive raws

With `(raw-5018)*0.1021`, the C32 full-throttle raw `0x26E1=9953` →
`(9953-5018)*0.1021 ≈ 503 A`, ≈ 200 kW at ~400 V — physically sane for BZ5 peak.
Cruise/regen raws straddle the zero coherently. The sign convention from C32
(discharge → raw > zero → positive; regen/charge → raw < zero → negative) holds.

## Caveats / open items

- **`791/0038` is NOT a charge cross-check.** It sat constant at raw 806 (~60 kW-eq
  via `×0.1 hp`) the whole charge — it's VCU/motor power and the motor is idle while
  charging. Fine on drive, useless on charge. Real cross-check on charge is the
  station: `474 V × 181 A = 85.8 kW ≈ 86 kW` ✓.
- **Voltage scale `790/0015` — bonus, still tentative.** raw `15311` at station
  474 V → **≈0.031 V/LSB** (≈1/32). This makes BOTH earlier guesses too low
  (`×0.02→306 V`, `×0.025→383 V`). But only ONE voltage anchor exists this cycle
  (`790/0015` dropped out at 15:05 / 15:08 — known BLE flakiness), so treat 0.031 as
  a direction, not a final. A dedicated capture with 2–3 station-voltage readings
  would pin it.
- `car_state` did not persist on client `0.1.29+46` (session stored it empty). No
  impact on the decode; flag it if the field matters client-side.

## Raw data

- `raw/live_log_session.csv` — session #22 metadata.
- `raw/live_log_entries.csv.gz` — all 2154 entries (718/DID), columns incl. decoded
  `u16` so you can re-fit independently.
