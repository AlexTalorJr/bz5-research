# BZ5 Cloud — server status (Друг 2 → Друг 1 sync)

Last updated: 2026-07-04 (S4 code-done, deploy pending) · Author: Друг 2 (bz5-bridge, VPS) · Base spec: `spec-v1.3-FINAL.md`

Purpose: keep client (Друг 1) and server (Друг 2) synchronized on what the server
has actually built and **deployed to prod**, what's live to code against, and
what's still pending. Living doc — updated as stages land.

---

## 1. Stage status

| Stage | What | Status |
|---|---|---|
| **S1** hygiene | offsite backup (Scaleway+age, cron), `make test` isolated to a test DB | ✅ done |
| **S2** account core | email-OTP accounts, JWT+refresh, allowlist, auth audit, sweeper | ✅ **done + deployed** |
| **S4-prelude (C1)** | `client_uuid` column ×5 + `POST /v2/sync/uuid-mapping` | ✅ **done + deployed** |
| **S3** pairing | device-flow (user_code + device_code), revoke, legacy bind | ✅ **done + deployed** |
| **S4** full sync | `server_seq`/`updated_at`/`deleted_at`, pull, dual UNIQUE (+ drop) | 🟡 **code-done + tested** (deploy pending) |
| **S5** web cabinet | read-only account view | ⏳ not started |

Migrations live on prod: `0004` (auth), `0005` (client_uuid), `0006` (pairing).
S4 adds `0007` (server_seq + trigger + dual UNIQUE + updated_at/deleted_at) —
**not yet deployed to prod.** Data intact (devices=2, trips=50, snapshots=1315).
94 server tests green.

**S4 scope note:** the old per-device UNIQUEs are NOT dropped in `0007` — that's a
later revision (`0008`), gated on backfill confirmed from BOTH live devices
(server-status §5a B2 gate: +117 must run on both installs). `0007` adds the new
`(vehicle_id, client_uuid)` partial UNIQUE alongside the old ones.

---

## 2. Live endpoints (code against these now)

Error body is always `{"detail": {"error": {"code","message"}}}` (FastAPI wraps
one level). Success shapes below.

### Account auth (phone) — `/v2/auth/*`
- `POST /v2/auth/otp/request` `{email}` → `200 {"ok":true}` (always, when
  configured — anti-enumeration; only permitted addresses get a code).
  `429 rate_limited` (5/h per email, 20/h per IP), `503 auth_not_configured`.
- `POST /v2/auth/otp/verify` `{email, code}` →
  `200 {access_token, refresh_token, token_type:"bearer", expires_in:900}`.
  `401 invalid_code`, `403 not_allowed`, `503 auth_not_configured`.
- `POST /v2/auth/refresh` `{refresh_token}` → `200` new pair.
  `401 invalid_refresh`; `401 refresh_reused` (replay → **session revoked**,
  re-login).
- `POST /v2/auth/logout` (Bearer **access JWT**) → `200 {"ok":true}`.

**Token model:** access = HS256 **JWT, 15 min**, stateless — send as
`Authorization: Bearer` on `/v2` account calls. refresh = **opaque, single-use,
rotating**: every refresh returns a NEW refresh token; the old one is dead;
**persist the newest, never retry an old one** (replay revokes the whole
session). Store refresh in secure storage.

### Sync backfill (head unit) — `/v2/sync/uuid-mapping`
- `POST /v2/sync/uuid-mapping` (Bearer **device_token**) `{entity, items[]}` →
  `{received, matched, unmatched, already_set, conflicts}`.
- `entity ∈ trips|snapshots|sweeps|livelogs|canmonitor`; `items` =
  `[{client_id:int, client_uuid:"<lowercase uuid>"}]`; ≤1000/POST.
- Idempotent (replay → `already_set`), unmatched is fine, conflicts are
  first-write-wins (no overwrite). Full contract:
  `cloud-v2/c1-mapping-contract-review.md`. Also in served `CLIENT_API.md` §3.8.

### Sync pull (restore) — `/v2/sync/pull` — NEW (S4, deploy pending)
- `GET /v2/sync/pull?vehicle=<uuid>&since=<server_seq>&limit=<n>` (auth: device
  token bound to that vehicle **or** account JWT of the owner **or** admin) →
  `{items:[{entity,server_seq,client_uuid,deleted_at,data}], next_since, has_more}`.
- Ordered by a **single global `server_seq`** (total order, no ties). Full
  restore = pages from `since=0` until `has_more=false`. Covers **trips +
  snapshots** only (restore scope). Apply idempotently by `client_uuid` with an
  overlap window (D8, client half). `limit` 1–1000, default 500. Full contract:
  served `CLIENT_API.md` §3.9. **Not live on prod until S4 is deployed.**

### Pairing (head unit ↔ account) — `/v2/pair/*`, `/v2/devices` — NEW (S3)
Device-flow, two secrets (D9): `device_code` (long, held by the head unit,
releases the token) + `user_code` (short, shown on screen, typed on the phone).
- `POST /v2/pair/start` (Bearer device_token for live device / no auth for fresh)
  → `{device_code, user_code, expires_in, interval}`.
- `POST /v2/pair/claim` (Bearer account JWT) `{user_code, vehicle_id?}` →
  `{"ok":true}`. `404 pairing_invalid`, `400 no_vehicle`.
- `POST /v2/pair/status` (no auth — device_code is the secret) `{device_code}` →
  `{status: pending|paired|expired, device_id?, client_token?, interval?}`.
  Fresh-device token is in `client_token`, released **exactly once**.
- `GET /v2/devices` (account JWT) → your devices. `POST /v2/devices/{id}/revoke`
  (account JWT). Full shapes in served `CLIENT_API.md` §1.2/§1.3.

### Owner-side (not for the client) — `/v1/admin/allowlist`
`GET/POST/DELETE` (admin token). Owner manages who may sign in.

Unchanged: all v1 device auth, ingest, command, diag surfaces work exactly as
before. Device tokens are untouched (spec D5).

---

## 3. Config / operational state

- `OWNER_EMAIL` set on prod (Alex's address). First `otp/verify` from it claims
  the seed owner (bootstrap). **Bootstrap not yet performed** — seed
  `users.email` is still NULL until that first verify.
- `JWT_SECRET` set (rotating it = global logout).
- ⚠️ **Email delivery is NOT live yet.** `EMAIL_BACKEND=log` → OTP codes are
  written to the server log, not emailed. Real delivery (Resend/Postmark/SES +
  SPF/DKIM/DMARC) is pending on Alex. **Implication for C2 testing:** until the
  relay is on, only the owner can complete a login (by reading the code from the
  server log). Plan client auth-UI testing around that, or wait for the relay.
- Retention (auto): otp_codes 1d, auth_events 365d, sessions 60d idle.

---

## 4. Readiness per client stage

- **C1 (Drift 13→14 + mapping)** — ✅ **server ready & live.** `client_uuid`
  columns + `/v2/sync/uuid-mapping` deployed; the 404-before-deploy window is
  effectively gone. Contract (Q1–Q8) confirmed in `c1-mapping-contract-review.md`.
  You can ship +117 on Alex's go.
- **C2 (Auth UI, phone)** — ✅ **server ready.** Endpoints in §2. Caveat: real
  email relay pending (§3) → end-to-end login testing limited to owner-via-logs
  until then.
- **C3 (Pairing UI)** — ✅ **server ready & live (S3).** Wire `pair/start` (with
  device_token for the current install, without for a fresh one), show
  `user_code`+QR, poll `pair/status` at `interval`; "My devices" via
  `GET /v2/devices` + revoke. Scenario (b) delivers the new token once — persist
  it immediately.
- **C4 (Push v2)** — 🟡 **partially unblocked.** The `(vehicle_id, client_uuid)`
  partial UNIQUE now exists (S4 code-done, deploy pending). BUT ingest endpoints
  still target the OLD `(device_id, client_*_id)` conflict key — switching the
  push path to conflict on `(vehicle_id, client_uuid)` is a small server follow-up
  (call it S4b/C4-server) not yet done. Coordinate before wiring +client push v2.
- **C5 (Restore)** — 🟡 **server ready once S4 deploys.** `GET /v2/sync/pull`
  (§2) delivers `server_seq`-ordered pages of trips+snapshots with `client_uuid`.
  Wire the restore master to pull from `since=0`, apply idempotently by
  `client_uuid`, keep a cursor with overlap. Not callable until S4 is on prod.
- **C6 (Graceful 401)** — server-independent; the token-revoke behavior it
  targets already exists.

---

## 5. Notes / gotchas for the client

- **Two separate credentials.** Device token (v1, head-unit ingest/command) is
  unchanged and permanent. Account access/refresh (v2, phone) is a new, separate
  layer. Don't cross them: device traffic stays on the device token.
- **Bootstrap/allowlist.** First account login must be `OWNER_EMAIL`. After that
  only allowlisted addresses receive codes (owner adds them). A non-allowlisted
  address silently gets no code (200, no email) and `403 not_allowed` if it
  reaches verify.
- **uuid-mapping is one-time & device-scoped.** Send all local rows; the server
  matches only this device's rows by `(device_id, client_id)`. Set your
  `uuid_mapping_pushed` flag only after all 5 entities return 2xx. Replays are
  safe.
- **The wipe defect isn't closed by C1 alone** (per spec §2.5) — it closes with
  full S4 (`(vehicle_id, client_uuid)` active) + C4. Keep the "don't wipe Drift
  on the head unit" operational rule until then.

---

## 5a. Client-side deviations (noted from +117 — no server impact)

Recorded so paper matches code:
- **mapping-push runs at the END of `syncOnce`** (after ingest pushes), not
  before (spec §1.4 said before). Reason: a fresh device identity would push
  mapping "into the void" before data is loaded. Server is idempotent → order is
  irrelevant to the contract. ✓
- **Per-entity watermarks** instead of a single one-shot flag → the client can
  delta-remap rows created during the C1→C4 window. Server handles this natively
  (`matched` for the new rows, `already_set` for replays). The spec's "set flag
  after all 5 entities" is a special case. ✓
- **e2e confirmation pending:** after the first real sync, +117 will report
  actual `matched/unmatched/conflicts` back — that closes C1 verification.
- **B2 gate (reminder, server-side):** prod has `devices=2`. The old per-device
  UNIQUEs are dropped (full S4) only after mapping has arrived from **both** live
  installs — i.e. +117 must run on both, not just the head unit. This is the
  §3.5 NULL-remainder check, now with the operational note that it's per-device.

## 6. What Друг 2 does next (server)

S4 (server_seq + pull + dual UNIQUE) is **code-done + tested; awaiting `make
deploy`** (adds migration `0007`). After deploy: (1) **S4b/C4-server** — switch
ingest conflict target to `(vehicle_id, client_uuid)` so client push v2 dedups on
uuid; (2) **`0008`** — drop old per-device UNIQUEs once backfill is confirmed on
both devices (B2 gate); (3) **S5 (web cabinet)**. The pull payload already
includes `client_uuid`, so the restore path (§1.5 of the C1 plan) can adopt
server uuids instead of regenerating — which is what makes post-reinstall restore
conflict-free.

Reviews & contracts for reference (same dir): `spec-v1.3-FINAL.md`,
`spec-v1.0/1.1/1.2-server-review.md`, `c1-mapping-contract-review.md`.
