# BZ5 Cloud spec v1.0 — server-side review (Друг 2 / bz5-bridge)

Date: 2026-07-03 · Reviewer: Друг 2 (bz5-bridge, this VPS) · Target: **BZ5 Cloud — спецификация v1.0 (хэндофф)** by Друг 1

Scope: correctness pass over the spec against the *actual* current state of the
bridge server. Verified against live code/DB on the VPS (FastAPI app + Postgres
16), not from memory. Grouped by severity.

TL;DR — the spec is factually sound; almost nothing about the current server is
wrong. But there are **two design holes that break history-restore if left
unaddressed** (A2 and B1), one factual inaccuracy about restore (A1), and one
about the dedup defect being worse than described for `trips` (A3). Stage order
S1→S2→S3→S4 does not need to change.

---

## A. Factual inaccuracies (fix these)

### A1. §2.4 "Restore covers device identity" — wrong for current state
Cloud-restore today restores **data** (trips, snapshots), **not identity**.
After an APK reinstall on DiLink the `client_token` is wiped from secureStorage,
and the current recovery path is: owner runs Setup → `register-device`, which
issues a **brand-new `device_id` + new token**. So identity is **re-minted, not
restored**. Directly conflicts with A2.

### A2. D5 ↔ §2.2/§2.4 contradiction (load-bearing — resolve first)
- D5 / §2.3: "device_token never changes, valid indefinitely." §4.2: "the head
  unit keeps working with its old token."
- §2.2 makes **restore (= the reinstall scenario) the foundation**. But that is
  exactly the scenario where the token is **physically gone** — there is no "old
  token" to keep.

Consequence:
- D5 is correct **only** for scenario (a): an already-running client that gets
  the account layer bolted on top of a live token → just pair it, token
  untouched. ✅
- For scenario (b) — a fresh reinstall (the restore foundation) — there is no
  token, so the device **needs a new one**. The pairing flow must therefore
  cover "device with no token": **who mints the token, and on which step?**
  Today `POST /v2/device/pair/start {device_id}` assumes the device already
  exists and already has a `device_id`/token. Decide explicitly: **pairing on a
  fresh device replaces `register-device`** (device generates `device_id`
  locally; `pair/claim` creates the `devices` row + issues the token under the
  account). Otherwise restore-on-a-clean-head-unit doesn't logically close.
- Side issue: **auth for `/v2/sync/pull` is unspecified.** On restore to a fresh
  head unit it must authenticate with the account JWT + vehicle ownership (the
  device token may not exist yet). Clarify.

### A3. §3.1/§9 "silent drop" — for `trips` it is a silent OVERWRITE (worse)
Verified in `app/routers/data.py`:
- `trips` and `feature_catalog` → **UPSERT (ON CONFLICT DO UPDATE)**
- `snapshots` / `samples` / `sweeps` / `livelogs` / `canmonitor` → **DO NOTHING**

So after a local DB wipe + autoincrement restart:
- snapshots/sweeps/livelog — yes, **silent drop** (as the spec says);
- **trips** — a new trip with `client_trip_id=1` **overwrites the data of old
  trip #1** on the server (history corruption, not a lost new row).

This **strengthens** the case for D1, but the defect wording must be widened.
Practical follow-on: ship the C1 migration (client_uuid + mapping) **before**
more `trips` overwrites accumulate.

### A4. §8 Q2 "body limits for pull batches" — conceptual mix-up
`client_max_body_size 25M` in nginx limits the **request body (uploads/push)**,
not responses. **Pull is a download** — its size is not gated by that. What
matters for pull: `proxy_read_timeout` (currently **60 s**) and **pagination**
(chunked since-cursor). Tune timeout + page size for pull, not body-limit. The
body-limit matters for the reverse case (push batches exceeding 25M).

### A5. §8 Q1 "confirm framework/versions with Друг 2 at S2 start" — already answered
From the 3 Jul report: Python 3.11, FastAPI 0.115.x, uvicorn 0.32, SQLAlchemy
2.0 (async) + asyncpg, Alembic 1.14, Pydantic v2. Admin UI is static vanilla
(html/css/js, hash-routing) — not an SPA framework, not server-rendered. This
question can be closed now.

---

## B. Design holes (not errors, but bake into S2/S4)

### B1. Seed-user reconciliation — critical, or the current history is orphaned
Today the existing vehicle (1) + devices (2) + trips (50) + snapshots (1315) are
owned by a **seed `users` row with no email**. §4.1 "creates a users row on first
login" → when Alex logs in via OTP he gets a **second** account, while the
current car and all its history stays bound to the **old seed user** (orphaned).
S2 must explicitly: on the owner's first OTP login, **write the email into the
existing seed row** (or reassign `owner_user_id`) rather than minting a new user.
Without this, "pull by vehicle" on the new account returns empty.

### B2. Dedup key (device_id, client_*_id) → (vehicle_id, client_uuid): migration + old-constraint decision
Current UNIQUEs are **per-device** (`UNIQUE(device_id, client_*_id)`). Moving to
`(vehicle_id, client_uuid)` is new UNIQUE constraints + an alembic revision, and
you must decide whether to **drop the old ones** or keep both during the mapping
backfill. Also the (desirable) semantic effect: two devices on one vehicle start
**deduplicating jointly** — good for multi-device, but it's a behavior change;
lock it in consciously.

### B3. server_seq / updated_at / deleted_at are all net-new columns
The current schema carries only `received_at`; `id` is a **global** autoincrement
(not per-vehicle). §3.2 needs: (a) a monotonic **per-vehicle cursor** (a
dedicated column/sequence, or careful use of the global `id` as cursor), (b)
`updated_at` for LWW (absent from trips and snapshots today), (c) `deleted_at`
for tombstones. Separate revision — just plan it into S4.

### B4. D6 (rate-limit in Postgres) on the hot ingest path
Moving rate-limit into Postgres adds a **DB write per ingest** (the 60/min limit
is the hottest endpoint). At `max_connections=20` and current volumes this is
fine, but: (a) count it as extra DB load, (b) `otp_codes`/`sessions`/
`refresh_tokens` need an **expired-row cleanup sweeper** — extend the existing
retention sweeper, don't build a new one.

---

## C. Minor / nitpicks

- **C1. §5 auth audit into the existing `audit_log` (30-day retention).** Note:
  (a) `audit_log` is **best-effort** middleware (write errors never block the
  response → an event can be lost), (b) 30 days is short for a security trail
  (login/pair/revoke), (c) `audit_log` has no user/account reference, only
  `token_fp` (8 hex). If auth audit matters → a separate durable table with
  longer retention.
- **C2. §4.3 revoke → "client shows 'pairing required', keeps data".** The
  current client does **not** do this: after 3×401 it wipes the **token** (not
  the Drift data) and stops. "Data survives" is true; but the graceful
  "pairing required" state needs a **client change** (a Друг 1 C-stage).
  Separate: token ≠ local data.
- **C3. §6 S1 offsite backup (S3).** This is a conscious **reversal** of a prior
  explicit project decision ("S3 backups out of scope; local pg_dump is enough").
  Justified for a cloud-durable v2, but have Alex confirm + provide object-store
  creds.
- **C4. §1 resources phrasing "74% used (~12 GB — docker junk)".** More precisely:
  **66 GB of 90 used (74%)**, of which **~12 GB is reclaimable** by docker prune;
  the rest is a shared VPS with Alex's other projects, not our data.

---

## Verdict
Resolve before starting: **A2** (D5 vs the restore foundation — who mints the
token on a fresh head unit) and **B1** (seed-user reconciliation). These two
break history-restore if not designed into S2/S3. Everything else is wording
fixes and ordinary build-notes. The S1→S2→S3→S4 sequencing stands.

Supporting facts (verified live 2026-07-03):
- ingest conflict semantics: `trips`/`feature_catalog` = UPSERT; all other Plane
  B ingest = DO NOTHING (`app/routers/data.py`).
- current row counts: users 1, vehicles 1, devices 2, trips 50, snapshots 1315.
- retention: trips/snapshots = none (permanent); samples/livelog/can 90d,
  audit 30d, commands(finished) 14d, diag 180d.
- resources: 4 vCPU / 7.7 GB RAM (swap 0) / 90 GB disk, 66 GB used, ~12 GB
  docker-reclaimable. Postgres DB size ~12 MB.
- email: no MTA, no mail libs, nothing on 25/587 — greenfield.
