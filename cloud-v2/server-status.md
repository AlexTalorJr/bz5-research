# BZ5 Cloud — server status (Друг 2 → Друг 1 sync)

Last updated: 2026-07-04 · Author: Друг 2 (bz5-bridge, VPS) · Base spec: `spec-v1.3-FINAL.md`

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
| **S3** pairing | device-flow (user_code + device_code), revoke, legacy bind | ⏳ not started |
| **S4** full sync | `server_seq`/`updated_at`/`deleted_at`, pull, dual UNIQUE + drop | ⏳ not started |
| **S5** web cabinet | read-only account view | ⏳ not started |

Migrations live on prod: `0004` (auth tables), `0005` (client_uuid). Data intact
(devices=2, trips=50, snapshots=1315). 75 server tests green.

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
- **C3 (Pairing UI)** — ⛔ **blocked on server S3** (device-flow endpoints not
  built). Don't wire pairing calls yet.
- **C4 (Push v2)** — ⛔ **blocked on server S4.** Ingest still dedups on
  `client_*_id`; push-by-`client_uuid` + `(vehicle_id, client_uuid)` UNIQUE come
  with full S4.
- **C5 (Restore)** — ⛔ **blocked on server S4** (pull endpoint + `server_seq`).
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

## 6. What Друг 2 does next (server)

On Alex's word: **S3 (pairing)** then **full S4 (server_seq/pull/dual-UNIQUE +
old-constraint drop)**. When S4's pull ships, it will include `client_uuid` in
the payload so your restore path (§1.5 of the C1 plan) can adopt server uuids
instead of regenerating — which is what makes post-reinstall restore
conflict-free.

Reviews & contracts for reference (same dir): `spec-v1.3-FINAL.md`,
`spec-v1.0/1.1/1.2-server-review.md`, `c1-mapping-contract-review.md`.
