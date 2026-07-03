# C1 — uuid-mapping wire contract: server review + answers (Друг 2)

Date: 2026-07-04 · Reviewer: Друг 2 (bz5-bridge) · Target: Друг 1's "C1 (Drift 13→14
+ mapping)" plan + mapping contract proposal · Base: spec-v1.3-FINAL.md

**Verdict:** §3 contract accepted essentially as-is. All Q1–Q8 answered below;
blockers Q1/Q2/Q4 are closed. Nothing here changes the spec. The server slice
C1 needs = `client_uuid` (nullable) column on 5 tables + the receive endpoint —
a small S4-prelude, shipped alongside S2 on Alex's go.

---

## Answers

### Q1 ⛔ — path + auth — CONFIRMED
`POST /v2/sync/uuid-mapping` + **device_token** (our `require_client` already
returns the `Device`, checks `revoked_at`, and yields `device_id`). The
`/v2/sync/` namespace is correct — this is Sync v2, not legacy ingest. No JWT
(C2 doesn't exist yet). Wire this path.

### Q2 ⛔ — entity names — CONFIRMED
`trips | snapshots | sweeps | livelogs | canmonitor`. Server binding (this is
the contract):

| entity | table | client_id column |
|---|---|---|
| `trips` | `trips` | `client_trip_id` |
| `snapshots` | `snapshots` | `client_snapshot_id` |
| `sweeps` | `sweep_runs` | `client_sweep_id` |
| `livelogs` | `live_log_sessions` | `client_session_id` |
| `canmonitor` | `can_monitor_sessions` | `client_session_id` |

Unknown `entity` → `400 bad_request`.

### Q3 — batch size — CONFIRMED
≤ 1000 items/POST is fine (feature-catalog cap is 5000 for reference; volumes
are trivial vs the 25M nginx limit). Match by `(device_id, client_id)`.

### Q4 ⛔ — behavior before the endpoint is deployed — CONFIRMED
Silent retry is correct: path absent → `404` (or `405` on known-path/wrong-
method — treat both as "not ready"), flag not set, nothing shown to the user.
**No capability flag in heartbeat** — agreed, needless coupling. C1 can ship to
the client before the server; the 404 window will be short (server slice deploys
alongside S2).

### Q5 — conflicts — CONFIRMED
`first-write-wins + counter + server log`; payload untouched. Client writes a
diag warning on `conflicts>0` and still sets the flag (conflict isn't
retryable). Shared understanding of *when* a conflict arises: mostly on
wipe+uuid-regeneration before S4/C5 is ready. Long-term it's removed by the
client restore path (§1.5) adopting the server's `client_uuid` from the pull
payload instead of regenerating (S4-payload work). So first-write-wins preserves
the row's original server-side identity = correct.

### Q6 — no temporal monotonicity — CONFIRMED
The server relies nowhere on `client_uuid` order/time. Pull is strictly by
`server_seq` (S4). For the server, uuid is an opaque unique key. Your v7 backfill
using row time is pure cosmetics, outside the contract.

### Q7 — relational snapshot→trip info — NO OBJECTION
The server already knows the link via `snapshots.client_trip_id`. Converting the
reference to uuid is S4-payload / C4, not C1.

### Q8 — explicit "mapping complete" signal — NOT NEEDED
The §3.5 gate (dropping the old per-device UNIQUEs) is verified by SQL on the
NULL remainder, per-device per-table (`count(*) where client_uuid is null` = 0)
— more authoritative than a client flag and lower coupling. No `complete:true`
signal.

---

## Server notes (not blockers)

- **UNIQUE deferred.** The C1 slice adds only the **nullable column, no
  uniqueness**. The new `(vehicle_id, client_uuid)` UNIQUE (B2) lands in full S4
  with the dual-constraint + drop revision, per spec — so replays/conflicts
  don't hit a constraint prematurely. (Client-side partial-unique is correct.)
- **No `updated_at`/`server_seq` yet** (S4/B3). The mapping slice touches only
  `client_uuid`. When S4 adds `server_seq`, existing rows get it via the
  migration backfill — mapping doesn't interfere.
- **Idempotency/unmatched/rate-limit** (§3.4) implemented exactly as described:
  replay → `already_set`; unmatched → counter; standard ingest rate-limiter.
- **Matching is device-scoped**: `WHERE device_id = <auth device> AND
  <client_id_col> = item.client_id`. Multi-device on one vehicle is safe — each
  device maps only its own rows.

## Response shape (as proposed, confirmed)
`{ "received", "matched", "unmatched", "already_set", "conflicts" }`; 2xx = whole
batch accepted (no partial failures).

## Next
All ⛔ closed → C1 patch +117 can be prepared (on Alex's "делай"). Server side:
I'll build the minimal slice (migration `client_uuid` nullable ×5 +
`POST /v2/sync/uuid-mapping`) and deploy it with S2, closing the client's 404
window.
