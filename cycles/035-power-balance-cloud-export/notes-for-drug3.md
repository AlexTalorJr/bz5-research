# 035 — what the cloud actually holds for the power-balance model

Requested: `hal_samples` (pack_voltage, pack_current, motor_*, speed, soc_precise,
battery_temp, ac_*) at ≥1 Hz for the 2026-10-21 parking session and the last
5–10 head-unit trips.

**The cloud has no HAL samples at all.** Raw per-sample ingest (`samples`) is
disabled by design since v1.0 (`403 samples_disabled`, ~1 % of the value at
~100× the disk), and no `hal_*` entity was ever added. HAL samples live only in
the head unit's local Drift DB.

What *is* here, exported as-is (2026-10-19 → 2026-10-22, UTC):

| file | what | density | signals |
|---|---|---|---|
| `raw/trips.csv` | per-trip aggregates + `speed_hist` | 1 row / trip | energy_used_kwh, energy_from_soc_kwh, regen, soc, temps, peak power/regen, moving/idle s |
| `raw/trip_series_points.csv` | LTTB-downsampled per-trip series | ≤240 pts / trip / series → 10–15 s/pt on a 40–60 min trip, 3–10 s on short ones | `power_kw` (pack power as the client reports it), `pack_voltage_v`, `soc`, `battery_temp_c` |
| `raw/snapshots.csv` | periodic snapshots | ~1 / min while driving, 2–3 min when parked | soc, pack_voltage_v, hv_bus_v, battery_temp_c, cell min/max/spread, is_charging, charging_power_kw, gear, odometer |

Not present anywhere server-side: `pack_current`, `motor_power` / torque / rpm,
`speed` as a series (only `speed_hist` per trip and `peak_speed_kmh`),
`soc_precise`, any `ac_*`, battery-heat / coolant flags.

2026-10-21 parking session (15:00–15:40 UTC = 18:00–18:40 head-unit time):
12 snapshots, no series (the phone-side "trips" 1011/1012 of that window carry
no `trip_series`). Not usable for an A/C on/off step.

Trips with full-length series: 969 (19.10 15:16, 54 min), 970 (20.10 05:09,
42 min), 1005 (20.10 07:34, 19 min), 1007 (20.10 15:31, 58 min). Charge phases:
`snapshots.is_charging` / `charging_power_kw`; none of these trips overlap a charge.
