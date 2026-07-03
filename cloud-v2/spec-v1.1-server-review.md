# BZ5 Cloud spec v1.1 — server-side review (Друг 2 / bz5-bridge)

Date: 2026-07-03 · Reviewer: Друг 2 (bz5-bridge, this VPS) · Target: **BZ5 Cloud —
спецификация v1.1 (хэндофф)** by Друг 1 (v1.0 + resolutions of
`cloud-v2/spec-v1.0-server-review.md`).

TL;DR — **v1.1 converges.** Every load-bearing (A2, B1) and secondary (B4, A3,
A4, A5, C1, C2) point from the v1.0 review is closed correctly. D5/D7/pairing-(b)
are exactly the right shape. Below: one operational update (the spec is now stale
on S1), and a few **new** flags that only surfaced at v1.1's level of detail.
Stage order S1→S2→S3→S4 confirmed.

---

## Resolutions accepted (converged)

- **A2 → D5(v1.1) + §4.2(b):** existing device_tokens never invalidated; live
  device keeps token on pairing; fresh device (reinstall) → pairing = registration,
  new token at `pair/claim`. Correct.
- **B1 → D7:** first OTP login with `OWNER_EMAIL` claims the seed user (writes
  email into the seed row), no duplicate account. Correct.
- **B4 → D6(v1.1):** durable Postgres state for auth/OTP/sessions only; ingest
  rate-limit stays in-memory. Correct.
- **A3 → §2.5:** dedup defect hardened — trips = silent *overwrite* (corruption),
  others = silent drop; C1 first. Correct.
- **A4 → §3.2 / A5 → §1 / C2 → C6 / C1(audit) → §5 `auth_events`:** all correct.
- **B2 → §3.1 / B3 → §3.2:** dual UNIQUE during backfill; server_seq bumped on
  every insert/update (good catch — LWW updates must be visible to the cursor);
  updated_at/deleted_at scoped to the permanent tables (trips/snapshots), so
  tombstones can't be retention-swept before sync. Correct.

---

## Operational update — spec is stale on S1

**S1 offsite backup is already DONE (this session, 2026-07-03).** Alex confirmed
the reversal, provided Scaleway creds, and it is built + tested + scheduled:

- `pg_dump -Fc -Z9` → **age-encrypt** → `rclone` → `s3://ineedto-backups/bzcloud/{daily,weekly}/`
- cron 04:00 UTC, retention daily-14 / weekly-8w
- private age identity held **off-VPS by Alex**; the VPS holds only the
  encrypt-only recipient (cannot decrypt its own backups)
- verified end-to-end: dump → encrypt → upload → download → decrypt →
  `pg_restore --list` = 18 tables
- code: `bz5-bridge:scripts/backup-s3.sh` / `make backup-offsite`

→ Mark S1 offsite ✅. **Remaining S1 (not done):** dedicated test-DB for
`make test`, and `docker prune` (~12 GB reclaimable).

---

## New flags (surfaced by v1.1 detail)

### N1 — `server_seq` cursor race under concurrent commits (important; sync correctness)
`server_seq = nextval(global_seq)` is **assigned at statement time but the row
becomes visible at commit time** — the classic sequence-based CDC hole:

- T1 takes seq=100 at 10:00:00, commits at 10:00:05
- T2 takes seq=101 at 10:00:01, commits at 10:00:02
- pull at 10:00:03 (`since=0`) sees only seq=101, sets cursor=101
- next pull `since=101` → `server_seq > 101` → **seq=100 lost forever**

Low risk at our write volume (single owner, batched pushes), but real — more so
with joint dedup of two devices per vehicle (B2) + LWW updates from the phone.
Fixes, lightest first:

- **cheap + sufficient:** client applies pull **idempotently by `client_uuid`**
  (already the design) and pulls the cursor with a small **overlap window**
  (`since = last_seq − N`); re-fetch is harmless. Covers time-bounded txns.
- **strict:** serialize `server_seq` assignment (advisory lock around
  assign+commit — free at our write volume), or use an `xmin`-snapshot watermark
  (only emit rows below which nothing is uncommitted).

Recommend overlap + idempotency as the baseline; advisory lock if you want a hard
guarantee. Bake into S4 — otherwise incremental/restore can silently drop rows
under concurrency.

### N2 — token issuance in pairing (b) needs a device-held secret (important; security)
In §4.2(b) the fresh head unit polls `pair/status` and receives a **new
device_token**. If retrieval is authorized by the short 8-char code (shown on
screen / in the QR, observable), the token can be stolen by anyone who sees/
guesses the code. Use the OAuth device-flow split — **two distinct secrets**:

- `user_code` — short, human-readable, entered on the phone (authorizes the
  owner's *approval*);
- `device_code` — long random secret the head unit generates at `pair/start` and
  presents at `pair/status`; **the token is released only against this**
  (authorizes the *device's retrieval*).

Otherwise: token theft via shoulder-surfing / code brute force (8 chars in a
5-min TTL is itself borderline; a proper device_code removes the issue).

### N3 — bootstrap gate + relay abuse (medium)
- Apply the D7 gate at `otp/request`, not just `otp/verify`: until the seed is
  claimed, only send OTP to `OWNER_EMAIL` — otherwise the relay can be used to
  mail arbitrary addresses.
- After bootstrap, "new email = new user" = **open registration** for a personal
  system. Intended? If multi-user isn't needed yet, keep `OWNER_EMAIL`-only or an
  allowlist, else anyone can burn your relay quota/reputation. At minimum, hard
  IP rate-limit on `otp/request` (already in §4.1) + a captcha hook later.

### N4 — JWT secret & refresh reuse (minor; fold into S2)
- Access-JWT needs a signing secret in env; rotating it logs everyone out
  (same semantics as `APP_TOKEN_PEPPER`). Add the knob.
- Refresh rotation needs **reuse-detection**: an already-rotated refresh presented
  again → likely theft → revoke the whole session chain. Standard, state it
  explicitly.

### N5 — revoke vs the 15-min JWT window (minor)
Device revoke is immediate (device_token checked against `revoked_at` on every
request). An account session on a stateless JWT lives until expiry (≤15 min) even
after revoke. Fine for devices (ingest is token-based, not JWT); for accounts the
15-min window is acceptable — just record it as expected behavior.

### N6 — connection pool under new load (watch; not a blocker)
`max_connections=20`. S2 (auth + durable OTP/session writes) + S4 (pull pages) +
S5 (web cabinet reads) + existing client/admin all share 20. Async pooling
probably suffices (data is tiny — a full restore today is 50 trips + 1315
snapshots ≈ a few hundred KB; pagination is future-proofing). Keep an eye on it at
S4/S5; if it strains, raise `max_connections` or tune the pool.

---

## Verdict
v1.1 resolutions accepted; the review has converged. **Stage order S1→S2→S3→S4
confirmed** (S1 offsite already closed; test-DB + prune remain). Before coding,
close **N1** (cursor) and **N2** (device_code in pairing) — the two with real
consequences (data loss / token theft). Everything else is a one-line addition to
its stage.
