# BZ5 Cloud spec v1.2 — server-side review (Друг 2 / bz5-bridge)

Date: 2026-07-03 · Reviewer: Друг 2 (bz5-bridge, this VPS) · Target: **BZ5 Cloud —
спецификация v1.2 (хэндофф)** by Друг 1 (v1.1 + resolutions of
`cloud-v2/spec-v1.1-server-review.md`).

**Verdict: green light, ready to implement.** All six N-flags from the v1.1
review (N1–N6) are closed correctly; no new load-bearing problems. Below: a
per-flag confirmation, a few implementation-time refinements (not blockers), and
one stale line in §1.

---

## N1–N6 — closed correctly

- **N1 → D8.** The advisory lock around "assign seq + commit" gives the hard
  guarantee: the next transaction can't take the lock until the previous one
  commits → **commit order == seq order**, no gap. Client-side overlap +
  idempotency by client_uuid is retry insurance. Correct. (See R1.)
- **N2 → D9.** Device-flow with `user_code` (approval) + `device_code` (token
  issuance); the short code never yields a token. Correct.
- **N3 → D7 + D10.** Gate on `otp/request` + allowlist until public launch. Relay
  protected on both sides. Correct.
- **N4.** JWT secret in env + refresh-rotation reuse-detection (§5). Correct.
- **N5.** 15-min JWT window documented as expected. Correct.
- **N6.** Connection-pool watch in S4. OK.
- **S1 offsite.** Marked done with the right script references. OK.

---

## Implementation-time refinements (fold into stages, not blockers)

### R1 — advisory lock: take it late, hold it briefly (S4, re D8)
The lock serializes *all* synced writes through one global mutex. Free at current
volume, as stated. But: acquire `pg_advisory_xact_lock` **immediately before
`nextval(server_seq)` and commit right after** — not at the start of a long
transaction. Otherwise a large/slow batch holding the lock blocks every other
synced write, and — together with N6 (`max_connections=20`) — waiting writers
hold connections → pool-exhaustion risk as data grows. Not an issue now, but bake
in the "assign seq late, commit fast" pattern so the lock doesn't become a
throughput ceiling.

### R2 — bootstrap/allowlist fail-closed (S2)
If `OWNER_EMAIL` is unset in env, `otp/request` must **reject everything**
(fail-closed), not open up. Spell it out: no OWNER_EMAIL and seed unclaimed → 4xx
for any email. Otherwise a config mistake = open mail relay.

### R3 — "joint dedup" wording (clarification only, no action)
`client_uuid` (UUIDv7) is globally unique, so `(vehicle_id, client_uuid)` is in
practice per-uuid dedup within a vehicle. Two devices "dedup jointly" **only if
they shared a uuid — they don't** (each generates its own). So no real
cross-device collapsing happens (and none is needed) — just a shared vehicle
namespace. Nothing to change; the §3.1 phrasing is slightly misleading.

---

## Stale line

§1 context: "pg_dump daily/weekly локально, **offsite нет**" — no longer true
(offsite on Scaleway exists, cron 04:00). S1 reflects it, but the §1 line should
be fixed so the "verified live" block doesn't contradict itself.

---

## Verdict
**Ready to implement, no blockers.** Stage order S1→S2→S3→S4 confirmed. R1/R2 —
add as a line in S4/S2 during coding; R3 — cosmetic; §1 — fix the offsite fact.
Start with **C1** (client) and the **S1 remainder** (test-DB + `docker prune`):
they depend on nothing, and they remove the active harm (trips corruption on
wipe) and the hygiene precondition.
