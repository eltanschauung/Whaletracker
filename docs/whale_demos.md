# WhaleDemos

`scripting/whaletracker/whale_demos.sp` owns match demo creation. Keep
`tv_enable 1` and `tv_autorecord 0`, and install SourceTV Manager.

On a human client's post-admin check, DGM's real player count must exceed seven.
The module checks the current match's `demo_filename` in SQL before starting.
A missing summary row is treated as unassigned and created by the usual match
upsert after recording starts successfully. Non-null rows are never replaced.
The ordinary match-log writer preserves the assigned filename on subsequent
saves, finalization and database reconnection. No round-start capture hook or
adoption of recordings created by other plugins remains.

An outstanding eligible join request is retried through the existing online
update timer when the database or SourceTV is not ready. Concurrent joins queue
one check, and callbacks from a finalized match or previous map are ignored.
Map end, finalization, the last human leaving, and plugin unload stop only the
recording started for that match. A manual recording is not stopped or adopted.

Example filename: `koth_genbu_ravine_b1_sept_30_14-36.dem`.
Time follows the VPS's `America/New_York` timezone, including daylight saving.
SourceTV rejects colons, so the time uses a hyphen. Workshop prefixes and UGC
suffixes are removed; a numeric suffix avoids same-minute filename collisions.
Collision checks include both GAME and /var/www/fastdl/demos, since the
background publisher moves completed recordings out of the server directory.
The `.dem` filename stored in the row is the same one passed to the native.

Offline contracts: `python3 tests/test_whale_demos.py`. Compile the full plugin
with the live SourceMod includes. In-game acceptance requires eight real DGM
players: the next eligible post-admin check should create exactly one recording
and stamp its current log; further joins and round starts must not restart it.
