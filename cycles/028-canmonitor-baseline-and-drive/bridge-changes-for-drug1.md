# Bridge changes for `bleStartCanMonitor` — info for Друг 1

**Date**: 2026-05-29
**Bridge commit**: `c73f0fb` (`feat(canmonitor): add bleStartCanMonitor + can_monitor_sessions/can_frames tables`)
**Bridge alembic revision**: now at `0002` (was `0001`)
**Repo**: https://github.com/AlexTalorJr/bz5-bridge
**Live CLIENT_API.md (always-fresh)**: https://carbridge.neardo.work/client-api.md

This document is a courtesy hand-off so the client side is fully aligned on the contract. Everything below is also in the formal `CLIENT_API.md` §3.6 and §7.3, but the bridge added one detail Друг 1 did not specify, and that detail is load-bearing for the client implementation. Calling it out explicitly.

---

## What's deployed

1. **Command kind `bleStartCanMonitor`** added to the whitelist. POSTs with this kind go through; smoke-test cmd 61 was created `pending` then cancelled, confirming the path.
2. **Migration `0002`** created two tables (additive, no data migration):
   - `can_monitor_sessions` (parent, with `UNIQUE(device_id, client_session_id)`)
   - `can_frames` (child, `ON DELETE CASCADE`, index on `(monitor_session_id, sequence)`)
3. **Ingest endpoint `POST /v1/data/ingest/canmonitor`** mirrors `/ingest/livelogs` exactly — same envelope, same atomic insert, same `on_conflict_do_nothing` idempotency.
4. **Admin stats** lists both new tables.
5. **Retention sweeper** purges `can_frames` whose parent `can_monitor_sessions.received_at < now() - RETENTION_CAN_FRAMES_DAYS` (default `90`, matches `live_log_entries`). If a different TTL is preferable, say so.

## Decisions the bridge made that Друг 1 did not specify

### 1. `client_session_id` is REQUIRED on the session row

Друг 1's message described the parent row as `(started_at, ended_at, duration_sec, car_state, notes, frame_count, unique_can_ids)`. The bridge follows the established pattern for all Plane B sessions (per ADR-07): every session needs a `client_session_id` that the client picks (a per-runtime monotonic integer). The `UNIQUE(device_id, client_session_id)` constraint is what makes the ingest idempotent for retries.

**Action on the client side**: include `client_session_id` in the upload payload. Reuse whatever counter you already maintain for `live_log_sessions` (the existing perRuntime monotonic counter is fine — they don't need to share namespaces, BMS livelog sessions and CAN monitor sessions are separate tables and don't collide).

If you can't include it, bridge will reject the insert with a 422 validation error and the batch will retry until it gives up. Trivial to add; please add it.

### 2. Retention 90 days

Same as `live_log_entries`. Configurable on the bridge via `RETENTION_CAN_FRAMES_DAYS` env var if Friend 1 wants longer/shorter. Frames are the bulky child; the session row itself is small and is not separately retained.

### 3. `notes` field carries `exit_reason`

Friend 1's spec says the client writes `exit_reason` into `notes`. Bridge does not parse this — it's stored verbatim. Convention from this batch: `"exit=completed"`, `"exit=no_frames_15s"`, `"exit=watchdog_stall"`, `"exit=ble_dropped"`, `"exit=cancelled"`. Bridge does not enforce this — but the operator workflow (Друг 2) reads `notes` to grade Phase A success.

---

## Bridge schema (canonical reference)

```sql
CREATE TABLE can_monitor_sessions (
  id                BIGSERIAL PRIMARY KEY,
  device_id         UUID NOT NULL REFERENCES devices(id),
  vehicle_id        UUID NOT NULL REFERENCES vehicles(id),
  client_session_id INTEGER NOT NULL,
  started_at        TIMESTAMPTZ NOT NULL,
  ended_at          TIMESTAMPTZ,
  duration_sec      INTEGER NOT NULL,
  car_state         TEXT,
  notes             TEXT,
  frame_count       INTEGER NOT NULL DEFAULT 0,
  unique_can_ids    INTEGER NOT NULL DEFAULT 0,
  received_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (device_id, client_session_id)
);

CREATE TABLE can_frames (
  id                  BIGSERIAL PRIMARY KEY,
  monitor_session_id  BIGINT NOT NULL REFERENCES can_monitor_sessions(id) ON DELETE CASCADE,
  sequence            INTEGER NOT NULL,
  ts_ms               BIGINT NOT NULL,
  can_id              TEXT NOT NULL,
  payload_hex         TEXT NOT NULL
);
CREATE INDEX can_frames_session_idx ON can_frames (monitor_session_id, sequence);
```

Fields the bridge fills in (do NOT include in client payload):
- `id` (BIGSERIAL — bridge assigns)
- `device_id`, `vehicle_id` (bridge resolves from auth token)
- `received_at` (bridge stamps at ingest)

Fields the client MUST provide:
- `client_session_id` (perRuntime monotonic — see decision #1)
- `started_at`, `duration_sec`
- `frame_count`, `unique_can_ids` (the client's own counters; bridge does not recompute)

Optional client fields:
- `ended_at`, `car_state`, `notes` (carry your `exit=...`)

---

## Ingest request shape

```http
POST /v1/data/ingest/canmonitor
Authorization: Bearer <client-token>
Content-Type: application/json

{
  "items": [
    {
      "client_session_id": 1,
      "started_at": "2026-05-29T11:30:00Z",
      "ended_at":   "2026-05-29T11:30:30Z",
      "duration_sec": 30,
      "car_state": "parked_ready_on",
      "notes": "exit=completed",
      "frame_count": 1240,
      "unique_can_ids": 47,
      "frames": [
        {"sequence": 1, "ts_ms": 0,    "can_id": "7DF", "payload_hex": "0210"},
        {"sequence": 2, "ts_ms": 12,   "can_id": "7E0", "payload_hex": "5001"},
        {"sequence": 3, "ts_ms": 25,   "can_id": "100", "payload_hex": "00112233"},
        ...
      ]
    }
  ]
}
```

Response: `{"received": N, "inserted": K, "duplicates": N-K}` where `inserted=0` on a retry of an already-ingested `client_session_id`.

`frames[]` may be empty (e.g., `exit=no_frames_15s`) — bridge accepts and stores the session row regardless.

---

## Operator workflow (Друг 2) for C28

The cycle plan stays as Друг 1 specified:

1. Phase A: `bleStartCanMonitor duration_sec=30 car_state="parked_ready_on"` → wait for `can_monitor_sessions` row + child `can_frames` to arrive on bridge → `\copy` both tables to `cycles/028-canmonitor-baseline-and-drive/raw/`
2. Defensive `bleStopActiveOperation` + 30 s pause (sweep busy-retention pattern)
3. Phase B: `bleStartLiveLog` 10-DID drive (the existing 10-DID set), drive, then `bleStopActiveOperation` on owner cue → `\copy` of `live_log_sessions` + `live_log_entries`
4. Friend-1 notes file + URL block as usual

---

## If something doesn't line up

The most likely client-side surprise is the `client_session_id` requirement. If your `bleStartCanMonitor` client implementation uploads a session row without it, the bridge will return a 422 with the field name in `details.errors`. The fix is a one-liner on the client. Nothing else should be controversial.

Reach back through the owner if you'd like to:
- Change the 90-day retention
- Lift the `(device_id, client_session_id)` UNIQUE in favor of a different idempotency key
- Add an admin read endpoint for `can_monitor_sessions` (Друг 2 currently extracts via `\copy`, no read endpoint exists — that's a deliberate scope cut to keep this patch tight)
