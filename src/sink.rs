//! Three independently progressing FIFO writers. An accepted failure remains at
//! the head of its lane; retries never evict work or let a later snapshot pass it.
use crate::{
    admission::{Admission, Completion, Dedupe, Permit, Spec, Usage},
    config::{now_ms, Config},
    database::connection,
    journal::{DeadLetters, Journal, StoredWrite},
    points_cache::PointsCache,
    sql::{self, Lane},
};
use mysql::{prelude::Queryable, Pool};
use std::{
    collections::VecDeque,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Condvar, Mutex,
    },
    thread,
    time::{Duration, Instant},
};

#[derive(Default)]
pub struct Counters {
    pub accepted: AtomicU64,
    pub executed: AtomicU64,
    pub db_errors: AtomicU64,
    pub parse_errors: AtomicU64,
    pub rejected: AtomicU64,
    pub journal_pending_startup: AtomicU64,
    pub journal_replayed_startup: AtomicU64,
    pub journal_done_startup: AtomicU64,
    pub compactions: AtomicU64,
    completed_since_check: AtomicU64,
}

struct Job {
    write: StoredWrite,
    _permit: Permit,
    completion: Arc<Completion>,
}
struct LaneQueue {
    jobs: Mutex<VecDeque<Job>>,
    changed: Condvar,
}

pub struct SqlSink {
    cfg: Config,
    pool: Pool,
    lanes: [LaneQueue; 3],
    admission: Arc<Admission>,
    // Serializes journal append + publication, NOT execution or queue inspection.
    publish: Mutex<()>,
    pub counters: Counters,
    pub dedupe: Dedupe,
    journal: Journal,
    dead_letters: DeadLetters,
    cache: Arc<PointsCache>,
}

pub struct Accepted {
    pub count: usize,
    pub completion: Arc<Completion>,
}

impl SqlSink {
    pub fn new(pool: Pool, cfg: Config, cache: Arc<PointsCache>) -> Result<Arc<Self>, String> {
        if !cfg.journal_path.is_empty() && cfg.journal_path == cfg.dead_letter_path {
            return Err("pending and dead-letter journals must use different paths".into());
        }
        Ok(Arc::new(Self {
            admission: Admission::new(cfg.max_queue_rows, cfg.max_queue_bytes),
            dedupe: Dedupe::new(cfg.dedupe_events),
            journal: Journal::open(&cfg.journal_path)?,
            dead_letters: DeadLetters::open(&cfg.dead_letter_path)?,
            lanes: std::array::from_fn(|_| LaneQueue {
                jobs: Mutex::new(VecDeque::new()),
                changed: Condvar::new(),
            }),
            publish: Mutex::new(()),
            counters: Counters::default(),
            pool,
            cfg,
            cache,
        }))
    }

    pub fn usage(&self) -> Usage {
        self.admission.usage()
    }

    pub fn replay(&self) -> Result<(), String> {
        let replay = self.journal.replay(
            self.cfg.dedupe_events,
            self.cfg.max_queue_rows,
            self.cfg.max_queue_bytes,
        )?;
        if replay.pending.len() > self.cfg.max_queue_rows
            || replay
                .pending
                .iter()
                .try_fold(0usize, |sum, write| sum.checked_add(write_size(write)))
                .is_none_or(|bytes| bytes > self.cfg.max_queue_bytes)
        {
            return Err("journal exceeds configured admission capacity; no records were removed; increase the limits before recovery".into());
        }
        for id in &replay.done {
            self.dedupe.remember(id);
        }
        let count = replay.pending.len();
        self.counters
            .journal_pending_startup
            .store(count as u64, Ordering::Relaxed);
        self.counters
            .journal_done_startup
            .store(replay.done_records as u64, Ordering::Relaxed);
        // Validate ALL replay records before publishing any. Invalid records stay
        // on disk for explicit operator repair instead of being marked done.
        for write in &replay.pending {
            sql::validate_write(&write.sql)?;
        }
        self.publish_writes(replay.pending, false)
            .map_err(str::to_string)?;
        self.counters
            .journal_replayed_startup
            .store(count as u64, Ordering::Relaxed);
        Ok(())
    }

    pub fn enqueue(&self, writes: Vec<StoredWrite>) -> Result<Accepted, &'static str> {
        for write in &writes {
            if let Err(reason) = sql::validate_write(&write.sql) {
                self.dead_letters.record("invalid_write", &reason, write);
                return Err("invalid SQL write; entire batch rejected");
            }
        }
        self.publish_writes(writes, true)
    }

    fn publish_writes(
        &self,
        writes: Vec<StoredWrite>,
        append: bool,
    ) -> Result<Accepted, &'static str> {
        let _publisher = self.publish.lock().expect("publication mutex poisoned");
        let writes: Vec<_> = writes
            .into_iter()
            .filter(|write| !self.dedupe.contains(&write.event_id))
            .collect();
        let specs: Vec<_> = writes
            .iter()
            .map(|write| Spec {
                id: &write.event_id,
                bytes: write_size(write),
                lane: sql::lane_for(&write.sql),
            })
            .collect();
        let permits = self.admission.reserve(&specs)?;
        drop(specs);
        if append {
            if let Err(err) = self.journal.append_pending(&writes) {
                // Dropping every permit rolls back the entire reservation.
                eprintln!("[sql-sink] admission journal failed; batch not published: {err}");
                return Err("journal write failed");
            }
        }
        let accepted = writes.len();
        let completion = Completion::new(accepted);
        for (write, permit) in writes.into_iter().zip(permits) {
            let lane = sql::lane_for(&write.sql) as usize;
            self.lanes[lane]
                .jobs
                .lock()
                .expect("lane mutex poisoned")
                .push_back(Job {
                    write,
                    _permit: permit,
                    completion: Arc::clone(&completion),
                });
        }
        self.counters
            .accepted
            .fetch_add(accepted as u64, Ordering::Relaxed);
        for lane in &self.lanes {
            lane.changed.notify_one();
        }
        Ok(Accepted {
            count: accepted,
            completion,
        })
    }

    pub fn spawn_workers(self: &Arc<Self>) -> Result<(), String> {
        for lane in Lane::ALL {
            let sink = Arc::clone(self);
            thread::Builder::new()
                .name(format!("sql-{}", lane.label()))
                .spawn(move || {
                    if std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                        sink.worker_loop(lane)
                    }))
                    .is_err()
                    {
                        // Do not leave a live listener admitting work to a dead lane.
                        eprintln!(
                            "fatal: SQL lane {} panicked; restart and recover the journal",
                            lane.label()
                        );
                        std::process::abort();
                    }
                })
                .map_err(|err| err.to_string())?;
        }
        Ok(())
    }

    fn take_batch(&self, lane: Lane) -> VecDeque<Job> {
        let queue = &self.lanes[lane as usize];
        let mut jobs = queue.jobs.lock().expect("lane mutex poisoned");
        while jobs.is_empty() {
            jobs = queue.changed.wait(jobs).expect("lane wait poisoned");
        }
        // Coalesce very small bursts for at most the configured flush interval;
        // predicate loops tolerate spurious wakeups and producer notifications.
        let deadline = Instant::now() + self.cfg.flush_interval;
        while jobs.len() < self.cfg.max_batch_rows {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                break;
            }
            jobs = queue
                .changed
                .wait_timeout(jobs, remaining)
                .expect("lane wait poisoned")
                .0;
        }
        let count = jobs.len().min(self.cfg.max_batch_rows);
        jobs.drain(..count).collect()
    }

    fn worker_loop(&self, lane: Lane) {
        loop {
            let mut batch = self.take_batch(lane);
            let mut delay = Duration::from_millis(250);
            let mut reported_head: Option<String> = None;
            while !batch.is_empty() {
                let mut conn = match connection(&self.pool) {
                    Ok(conn) => conn,
                    Err(err) => {
                        self.counters.db_errors.fetch_add(1, Ordering::Relaxed);
                        eprintln!(
                            "[sql-sink:{}] connection unavailable; work retained: {err}",
                            lane.label()
                        );
                        thread::sleep(delay);
                        delay = (delay * 2).min(Duration::from_secs(10));
                        continue;
                    }
                };
                let mut committed = Vec::new();
                let mut failure = None;
                while let Some(job) = batch.front() {
                    // Closes the narrow completed-cache/admission race. The ID is
                    // still reserved, so no second worker can execute it now.
                    let result = if self.dedupe.contains(&job.write.event_id) {
                        Ok(())
                    } else {
                        conn.query_drop(&job.write.sql)
                    };
                    match result {
                        Ok(()) => {
                            if sql::invalidates_points_cache(&job.write.sql) {
                                self.cache.mark_dirty();
                            }
                            self.counters.executed.fetch_add(1, Ordering::Relaxed);
                            committed.push(batch.pop_front().expect("batch front exists"));
                        }
                        Err(err) => {
                            failure = Some(err.to_string());
                            break;
                        }
                    }
                }
                // Discard a failed session rather than reusing possible transaction
                // or protocol state. Successful sessions return to the bounded pool.
                if failure.is_some() {
                    drop(conn.unwrap());
                } else {
                    drop(conn);
                }
                self.confirm_committed(committed);
                if let Some(err) = failure {
                    let head = &batch.front().expect("failed head retained").write;
                    self.counters.db_errors.fetch_add(1, Ordering::Relaxed);
                    if reported_head.as_deref() != Some(head.event_id.as_str()) {
                        eprintln!(
                            "[sql-sink:{}] retrying {} (age_ms={}): {err}",
                            lane.label(),
                            head.event_id,
                            now_ms().saturating_sub(head.ts_ms)
                        );
                        self.dead_letters
                            .record("db_retry_not_discarded", &err, head);
                        reported_head = Some(head.event_id.clone());
                    }
                    thread::sleep(delay);
                    delay = (delay * 2).min(Duration::from_secs(10));
                } else {
                    delay = Duration::from_millis(250);
                }
            }
        }
    }

    fn confirm_committed(&self, jobs: Vec<Job>) {
        if jobs.is_empty() {
            return;
        }
        let ids: Vec<_> = jobs.iter().map(|job| job.write.event_id.as_str()).collect();
        let mut delay = Duration::from_millis(250);
        // A journal failure AFTER SQL success is not a reason to execute SQL again.
        // Hold permits and ACKs, retry ONLY the completion marker write.
        while let Err(err) = self.journal.append_done(&ids) {
            eprintln!("[sql-sink] SQL committed; retaining ACKs until done markers persist: {err}");
            thread::sleep(delay);
            delay = (delay * 2).min(Duration::from_secs(10));
        }
        let count = jobs.len() as u64;
        drop(ids);
        for job in jobs {
            self.dedupe.remember(&job.write.event_id);
            job.completion.finish();
            // job and its capacity permit are dropped exactly once here.
        }
        let previous = self
            .counters
            .completed_since_check
            .fetch_add(count, Ordering::Relaxed);
        if previous / 1024 != previous.saturating_add(count) / 1024 {
            match self.journal.compact(
                self.cfg.dedupe_events,
                self.cfg.compact_bytes,
                self.cfg.max_queue_rows,
                self.cfg.max_queue_bytes,
            ) {
                Ok(true) => {
                    self.counters.compactions.fetch_add(1, Ordering::Relaxed);
                }
                Ok(false) => {}
                Err(err) => eprintln!(
                    "[sql-sink] journal compaction deferred; active journal retained: {err}"
                ),
            }
        }
    }
}

pub fn write_size(write: &StoredWrite) -> usize {
    write
        .sql
        .len()
        .saturating_add(write.event_id.len())
        .saturating_add(256)
}
