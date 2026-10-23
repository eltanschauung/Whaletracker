# Calculated points gain notifications

Notifications compare actual accepted ranking-cache values; login/reload establishes
a baseline, and an individual increase must exceed nine points. Sound playback is
optional and respects Saysounds preferences; it cannot suppress the chat message.

## Round refresh coordination

Round end publishes a snapshot and starts a generation-tagged refresh using the
existing two-second retry/query path. While that refresh is outstanding, notices
are deferred. After all result rows have been accepted:

- If round start has not happened, gains wait for it as before.
- If round start has happened, schedule the notice for five seconds after that
  start. If that deadline has passed, schedule it for the next timer service
  (0.1 seconds), not the following round.
- A qualifying gain accepted during an already scheduled notice is folded into
  that notice instead of leaving another round's stale pending message.

Only the newest refresh generation can accept result rows, retry, or release the
gate. Map end invalidates outstanding generations and preserves connected clients'
unreported gains. Refresh timeout/invalid log/no clients releases the gate without
pretending a fresh calculation succeeded. Disconnect clears client-specific state.

No frame hooks, synchronous queries, or additional periodic timers are introduced.
Manual mid-round cache observations still wait for the next round-start event;
only completion of the round-end refresh can finish a deferred transition.

## Regression probe

```sh
bash tests/build_points_gain_probe.sh
```

The builder compiles the actual notification module and extracts the actual
`SQL_OnRoundPointsRefreshed` completion callback. The probe uses synthetic clients,
mock SQL results, and disposable handles; it never connects to a database, changes
real clients, emits audio, or sends client chat. It prints one server-console
summary when loaded on a test SourceMod instance. Unload it after the test.

Coverage includes the reported 9634-to-9655 late-publication race, refresh-before-
start, start-before-refresh, publication after the five-second deadline, manual
observation followed by the same automatic result, stale/duplicate callbacks,
overlapping rounds, empty/error retries, timeout/log change, map-end invalidation,
client serial reuse, thresholds/colors, opt-out, and absent Saysounds API.

Also run `python3 tests/round_points_snapshot_test.py` for the isolated ranking-SQL
fixture and compile the full production plugin. A probe pass does not substitute
for observing an ordinary human round transition after activation.
