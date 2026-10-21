# WhaleTracker scoped performance implementation review

2026-10-21. Baseline: `4c68b84`. Implemented candidates **1, 2, 4 only**.
Parent approved the implementation and the final two adjustments. Deployed the
daemon and reloaded only WhaleTracker on tf2 on 2026-10-21; MGE was not reloaded.
No additional agents, game-server restarts, map changes, schema changes, synthetic
load, journal replacement, or unrelated source changes.

## Changed files

Production source:

- `src/sql.rs`: `validate_and_classify` returns transient lane/invalidation
  metadata after one header tokenization. Compatibility helpers are test-only,
  eliminating unused-helper warnings in production builds.
- `src/sink.rs`: classify every fresh/replayed write before publication, keep
  metadata aligned through dedupe filtering, use it for admission, queue routing,
  and successful-write invalidation. Durable `StoredWrite` is unchanged.
- `src/points_cache.rs`: unlocked eligibility probe; eligible polls acquire the
  existing lock and reread all five decision fields including database time.
  Existing rebuild and generation-guarded acknowledgment remain unchanged.
- `scripting/whaletracker/commands_whaletracker.sp`: native-first behavior stays;
  joined DB lookup returns row-presence columns and both colors. SourcePawn still
  fetches/trims in the original order. A failed joined query uses the legacy
  queries, preserving partial-schema and query-error behavior.
  Disconnect now delegates directly to metadata update with empty knownColor,
  avoiding a second resolution when the first color result is empty.

New verification/documentation files:

- `tests/perf_refactor_probe.py`
- `tests/fixtures/sql_classification_probe.rs`
- `tests/color_fallback_probe.py`
- `tests/mariadb_perf_fixtures.py`
- `docs/perf_refactor_review.md`

No changes to `src/config.rs`, `src/schema.rs`, ranking formula/allowlist/query,
35-match eligibility/latest-100 window, publication timing settings, match
snapshot/finalize semantics, reward code, or journal format/order. Existing dirty
main/runtime/gameplay and untracked join-name/include/probe work is preserved.

Before editing, all initially modified/untracked files were SHA-256 snapshotted
in `/tmp/whaletracker-perf-protected-20261021.sha256` on Kogasa. Every entry still
passes `sha256sum -c`. Manifest SHA-256:
`6dbbadf85c9de5f7536439c3838aa9a9c07a559dd7adc944dae9b16f2ec04fd9`.

## Verification results

All final checks passed:

- `cargo test --locked --all-targets -- --test-threads=1`: **26 passed**;
  frontend snapshot binary has zero tests. Includes actual eligibility-boundary
  tests and explicitly labeled query-count/interleaving models. Existing
  admission, dedupe, journal replay/compaction, transport and deadline tests pass.
- SQL differential probe: **12 passed**, including original baseline/current
  tests, 301 structured cases, and 10,000 deterministic mutated statements.
  Compares validation errors and lane/invalidation metadata against baseline.
- Color C++ proxy: **37,632 differential cases passed**, under ASan/UBSan.
  Executes mechanically translated old/new function bodies against DB/native
  stubs; covers missing/NULL/empty/whitespace/nonempty rows, query/table errors,
  joined-query-only errors, native success/failure/unavailable, short output
  buffers, empty IDs and database readiness. **Not a SourceMod runtime test.**
- Extracted color SELECT: **20 SQLite fixture combinations passed**.
- MariaDB: **16 color SELECT fixtures**, generation-guard invalidation, and
  real two-session named-lock exclusion/release passed. Uses the existing safe
  helper's `default` section; credentials are never printed. Only connection-local
  temporary tables are mutated, created with `LIKE` from real schema. Production
  rows are not read. Fixture query table names are substituted.
- Final SourcePawn compile: SourcePawn **1.12.0.7255**, zero warnings/errors;
  output `target/perf-activation-20261021/whaletracker.smx` (301172 code bytes).
  Built from staged live source/includes plus only the approved commands module.
  No auto-rewriter was run against the dirty includes.
- `python3 tests/round_points_snapshot_test.py`: passed; actual extracted ranking
  SQL preserves published-current-log and finalization identity behavior.
- `git diff --check`: passed.
- Final single-job separate-target Rust release build: passed without warnings,
  completed in 1m43s. The four compatibility helpers are now `#[cfg(test)]`;
  both the differential test build and optimized benchmark build still pass.
- Disconnect source contract verifies one color resolution and preserved
  SteamID, readiness, and user-ID handling.

During development, `cargo test --all-targets` initially failed because Cargo
auto-discovered the standalone Rust probe at the top level of `tests/`. Moving
it under `tests/fixtures/` fixed this; the final all-targets run passed. The first
MariaDB fixture setup used a temporary table's own name in `LIKE`, which MariaDB
rejected with 1066; distinct fixture names fixed it. Neither failure mutated
production rows. No unresolved test failures.

## Reproduce

Run from `/home/kogasa/Whaletracker`; use low priority, one build at a time:

```sh
CARGO_BUILD_JOBS=1 nice -n 10 ionice -c 3 /home/kogasa/.cargo/bin/cargo test --locked --all-targets -- --test-threads=1
CARGO_BUILD_JOBS=1 nice -n 10 ionice -c 3 /home/kogasa/.cargo/bin/cargo check --locked --bin whaletracker-rust
CARGO_TARGET_DIR=target/perf-release-20261021 CARGO_BUILD_JOBS=1 nice -n 10 ionice -c 3 /home/kogasa/.cargo/bin/cargo build --locked --release --bin whaletracker-rust
nice -n 10 ionice -c 3 python3 tests/perf_refactor_probe.py
nice -n 10 ionice -c 3 python3 tests/perf_refactor_probe.py --bench
nice -n 10 ionice -c 3 python3 tests/color_fallback_probe.py
nice -n 10 ionice -c 3 python3 tests/mariadb_perf_fixtures.py --helper /home/kogasa/Kogasatopia/tools/kogasa_db.py
CARGO_BUILD_JOBS=1 nice -n 10 ionice -c 3 /home/kogasa/.cargo/bin/cargo test --locked --bin whaletracker-rust points_cache::tests::poll_query_count_model -- --nocapture
python3 tests/round_points_snapshot_test.py
nice -n 10 ionice -c 3 /home/kogasa/hlserver/tf2/tf/addons/sourcemod/scripting/spcomp64 target/perf-activation-20261021/scripting/whaletracker.sp -itarget/perf-activation-20261021/scripting -itarget/perf-activation-20261021/scripting/include -otarget/perf-activation-20261021/whaletracker.smx
git diff --check
sha256sum -c /tmp/whaletracker-perf-protected-20261021.sha256
```

The SQL probe requires the pinned baseline commit in local Git history, rustc,
and no DB/network. It compiles only temporary probe executables with release
optimization (`rustc -C opt-level=3`), never the live daemon path. The color
proxy requires g++/clang++ and SQLite. MariaDB fixtures require temporary-table
permissions and the existing helper; do not substitute a general production
integration test for this script.

## Benchmarks and query counts

Classifier CPU microbenchmark: Rust 1.89, release optimization, five rounds,
200,000 writes/variant/round, alternating before/after order. Equal mixture of
compact online REPLACE, stats UPDATE, log-player INSERT/upsert, and marked log
UPDATE. Baseline runs validation, both lane lookups, and invalidation lookup;
new version validates/classifies once and reuses the fields. `black_box` keeps
results observable. No DB, sockets, journal I/O, or allocator counting.

| Round | Before ns/write | After ns/write |
|---|---:|---:|
| 0 | 1785.2 | 632.7 |
| 1 | 1837.1 | 622.8 |
| 2 | 1892.2 | 630.8 |
| 3 | 1796.9 | 641.4 |
| 4 | 1858.4 | 633.2 |
| Median | **1837.1** | **632.7** |

Final repeat: approximately **65.6% less classifier CPU time**, 2.90x classifier throughput.
This is not an end-to-end daemon throughput or latency claim, and does not
measure the metadata vector's small publication overhead.

Poll statement-count **model**, excluding pool/session reset/setup traffic:

| Poll scenario | Before | After |
|---|---:|---:|
| Missing state, clean, or debouncing | 3 | 1 |
| Due rebuild: four rebuild statements plus guarded ACK | 8 | 9 |
| Eligible probe, lock unavailable | 1 | 2 |
| Eligible probe, another owner cleaned before locked reread | 3 | 4 |

At the default one-second poll rate, a continuously clean owner goes from
259,200 to 86,400 application statements/day. Actual environment overrides were
not inspected. Same poll/debounce/max-wait settings; negative hints are never
retained between polls. Models exercise owner completion between reads, renewed
debounce, a new generation before lock, invalidation during rebuild, and next-poll
visibility. MariaDB fixture checks validate underlying lock/CAS primitives, not
the complete daemon poll/rebuild function or actual query-count tracing.

Color query-count proxy: missing/empty/whitespace filter fallback **2 -> 1**;
nonempty filter **1 -> 1**; native success **0 -> 0**. Error path costs one extra
failed joined query before the unchanged legacy path. No live frame-time or
MariaDB latency benchmark was performed. Joined successful queries may do an
extra indexed lookup when the filter color was already nonempty.

## Running paths and deployment boundary

- Service: `whaletracker-rust.service`.
- Source/working directory: `/home/kogasa/Whaletracker`.
- Launcher: `/home/kogasa/Whaletracker/whaletracker-rust.sh`.
- Active daemon executable: `/home/kogasa/Whaletracker/target/release/whaletracker-rust`;
  listeners 28017 and 28018. Built separately, then atomically replaced and
  restarted at **2026-10-21 12:54:55 UTC**. SHA-256:
  `1f648ca9d8d2a38dad132c036715d71ad9dd23991936f365953b38cbe6df8e41`.
- SourceMod entry: `/home/kogasa/hlserver/tf2/tf/addons/sourcemod/scripting/whaletracker.sp`.
- Loaded-plugin disk path: `/home/kogasa/hlserver/tf2/tf/addons/sourcemod/plugins/whaletracker.smx`.
- These SourceMod paths resolve under
  `/home/kogasa/Steam/steamapps/common/Team Fortress 2 Dedicated Server/tf/addons/sourcemod/`.
- Live source entry **matches the repo's existing dirty entry byte-for-byte**:
  SHA-256 `cdbc317785765748b97a995e1484ad7f082d314d64aa862c4619e6a962c25dd0`.
  Live source `commands_whaletracker.sp` matched HEAD before deployment, so the
  approved module was installed without overwriting any unrelated live changes.
  Its SHA-256 is now
  `1cdd6dfcb6e15a1c6e3763bab5e3815bc886a155bb3662f6c11e6464effb4aba`.
- New plugin artifact SHA-256:
  `b12da66ed9948460eb25512876ca3f90a9033d622c1a8350be1c12c05c697eb1`.
  Installed **2026-10-21 12:55:37 UTC**; tf2 confirmed successful reload and
  `Version: 1.1.2`, `Status: running`, followed by database readiness. No version
  bump was made in the protected dirty runtime module. Disk artifact identity
  plus successful reload was verified; no in-memory SMX byte hash is available.

## Actual deployment and rollback

Backups are under `/home/kogasa/backups/whaletracker-perf-20261021/` (directory
0700; backed-up artifacts 0600): `daemon.old`, `whaletracker.old.smx`, and
`commands_whaletracker.old.sp`, with `SHA256SUMS`. Restricted handover metadata
records original modes, installation times, before/after health, cache state,
and journal/lock inodes. No journals were copied back, deleted, or replaced.

The daemon was built in `target/perf-release-20261021`; the plugin was compiled
in `target/perf-activation-20261021` from the actual live source tree/includes.
Before handover, both queues were empty, accepted/executed counts matched, and
error counters were zero. Both listener process executable hashes now match the
installed daemon. After restart, a cache rebuild published and acknowledged
dirty with generation **8833**, rebuilt timestamp **1792587301808 ms**.

Immediately before plugin activation, tf2 reported **0 humans/0 bots**, SourceTV
inactive, and `sm_savestats` confirmed zero players to save. The normal plugin
unload path performs finalize/flush/shutdown; no demo rollover was necessary.
Only WhaleTracker was reloaded on tf2. MGE and both game-server screens were
left running; MGE's loaded plugin was not changed by a reload.

After activation, 28017 had **24 accepted/24 executed**, empty queues and zero
DB/parse/rejection errors; 28018 had zero writes and zero errors. Ordinary timer
writes progressed across batches; no synthetic writes were submitted to test
ACKs. Direct ACK timing/counters were not instrumented. Bounded new-log inspection
from pre-handover offsets found **zero Rust error lines and zero SourceMod
WhaleTracker error references**. All four journal/lock inodes stayed unchanged.

Rollback, if needed: validate the restricted backup hashes, drain queues, then
restore `daemon.old` atomically to the daemon path with its saved original mode
(`daemon-mode.txt`) and restart only `whaletracker-rust.service`. Keep the **current
journals and lock sidecars**. Restore the old commands source and plugin binary
atomically with modes recorded in `plugin-installed.json`; reload only WhaleTracker
on tf2 after rechecking human/recording state and using the existing save lifecycle.
Never rewind journals, discard accepted writes, or restore old DB rows. No rollback
was required in this deployment.

Known gaps: no loaded SourceMod runtime integration test; poll orchestration/races
are deterministic models rather than daemon-level MariaDB integration; no live
end-to-end load test or memory/allocation profile. None is concealed by a cache
TTL increase or a change to ranking semantics.
