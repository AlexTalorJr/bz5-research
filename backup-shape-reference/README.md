# Cloud backup shape — reference (trip 18, "30 May 16:06" drive)

What the bridge cloud actually holds for one real trip, so the client side knows
exactly what survives a head-unit APK reinstall (uninstall+install wipes local
Drift; restore can only return what the cloud stored).

Trip: `id=18`, `client_trip_id=11`, `2026-05-30 13:06–14:14 UTC` (16:06 local),
73.3 km, device `26305a60-…`, vehicle `842665c4-…`.

## Files
- `trip_18.csv` — the single **trip aggregate row** (all columns).
- `snapshots_trip18.csv` — the **25 snapshots** tagged to this trip
  (`client_trip_id=11`), ordered by `captured_at`.

## What survives a reinstall (= is in these files)
- **Trip aggregates**: distance, energy, avg_consumption, peak_speed (149.0),
  avg_moving_speed (79.2), moving/idle seconds, start/end + min/max SOC,
  min/max battery temp, max_cell_spread, peak_power, odometer, `sample_count`
  (a counter, 24229 here), and `extra` (jsonb).
- **Snapshots**: coarse point-in-time rows — SOC, SOH, battery_temp_c, cell
  voltages/spread, odometer, pack_voltage, hv_bus, gear, charging flags, cycle
  count. **No speed field.**

## What does NOT survive (physically absent from the cloud)
- **`samples`** — the per-second time series. `INGEST_SAMPLES_ENABLED=false`
  (ADR-08); the server returns `403 samples_disabled` and the client never
  uploads them. The `samples` table is empty for every trip. Hence the speed /
  SOC / battery-temp **distributions** of pre-reinstall trips cannot be rebuilt
  from the cloud — only the peak/avg scalars above remain.

## `extra` here is null — why, and the fix
This trip was recorded before client **+37**. `trips.extra` is `null`, so there
is no stored speed histogram. From +37 on, the client computes the speed-distri
histogram at trip end and writes it to `trips.extra` as
`{"v":1,"speedHist":[15 ints]}` — a few hundred bytes that ride along with the
trip row and survive reinstall (the cheap alternative to enabling raw samples).

Bridge round-trip for `extra` is verified clean (object in → jsonb → object out,
no double-escaping), and the upsert is **null-preserving** since 2026-05-31
(`coalesce(nullif(excluded.extra,'null'::jsonb), trips.extra)`): a later push
that omits `extra` — e.g. a rollback to +36 — will not clobber a stored
histogram. See bz5-bridge `docs/CLIENT_API.md` (trip upsert rules).
