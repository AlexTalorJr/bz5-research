# Client-side observations after Cycle 2

Reported by owner after returning from drive (~16:43 UTC, ~9 min
after POST'ing bleStopActiveOperation).

## What the head unit Settings → BridgeDiag screen shows

> `last: BleStartLiveLog (39m ago)`

Interpretation: the client UI's "last operation" field was last
updated when it picked up command id=3 (bleStartLiveLog) at
2026-05-25T16:02:43Z (39 minutes before the observation, give or
take). It was **not** updated when the client picked up command
id=4 (bleStopActiveOperation) at 2026-05-25T16:34:50Z.

Combined with the server-side facts already captured in the parent
commit (`c4d61a5`):

- Command 4 reached `dispatched` (long-poll returned it to the
  client) but the client never POSTed `/v1/commands/4/result`.
- Sweeper marked it `timeout` at 16:40:44Z.
- Heartbeats (`POST /v1/data/ingest/heartbeat` on token_fp
  `bf9d006d`) continued every ~60s throughout — so the app process
  was alive the entire time.

This means the client's `commands/next` long-poll was alive and
delivered cmd 4 to BridgeDiagService, but BridgeDiagService either:

- crashed / hung in some thread that owns both the live-log timer
  AND the command handler (so it stopped collecting entries AND
  stopped responding to subsequent commands), OR
- silently dropped cmd 4 (e.g. internal state was "no active
  operation" so it treated the stop as a no-op, but then didn't
  POST a result either way), OR
- was waiting for a BLE response that never came (long-blocked on
  a BLE call that hung mid-flight when the underlying transport
  died).

Strong indicator that the failure mode is **not** "BLE
disconnected and the client adapter cleaned up" — if it were, we'd
expect cmd 4 to have returned an error result like
`{ok: false, error: "no active session", error_kind: "noop"}` or
similar.

## Drive context

Owner confirms the drive lasted **longer than 32 minutes** — i.e.
the 33 entries captured between 16:02:52Z and 16:03:07Z are NOT
the full drive cut short by an early return. The client really did
stop ingesting at 19 seconds into a >32-minute trip while the rest
of the app kept doing heartbeats.

## What I (bridge Claude) did not check / cannot check

- The actual BridgeDiagService state on the client (active session?
  thread alive? BLE handle valid?). Friend 1 has the source.
- Whether the live-log timer thread caught an exception that was
  swallowed by a broad `try/except` somewhere.
- Whether the BLE adapter underneath (flutter_blue_plus or
  whichever) emits a connection-lost stream that BridgeDiag
  ignores.

These are companion-side investigations that benefit from looking
at logs on the head unit (`bz5-snap.sh` flow if logs are exported
that way, or Settings → Logs in the app).
