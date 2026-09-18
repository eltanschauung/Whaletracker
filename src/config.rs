//! Environment configuration. Existing variable names and defaults are retained.
use std::{
    env,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

pub const SCHEMA_VERSION: u32 = 6;
pub const MAX_LOG_DAMAGE_PER_MINUTE: f64 = 3000.0;
pub const RANK_MAX_MATCHES: usize = 300;
pub const RANK_MIN_MATCHES: usize = 50;
pub const RANK_MIN_MATCH_DURATION: i32 = 300;
pub const RANK_MIN_KILLS_ASSISTS: i32 = 5;

#[derive(Clone)]
pub struct Config {
    pub bind: String,
    pub flush_interval: Duration,
    pub max_batch_rows: usize,
    pub max_queue_rows: usize,
    pub max_queue_bytes: usize,
    pub dedupe_events: usize,
    pub journal_path: String,
    pub dead_letter_path: String,
    pub compact_bytes: u64,
    pub max_frame_bytes: usize,
    pub max_inbound_writes: usize,
    pub max_sql_bytes: usize,
    pub max_clients: usize,
    pub frame_timeout: Duration,
    pub ack_timeout: Duration,
    pub auth_token: String,
    pub require_localhost: bool,
    pub debug: bool,
    pub cache_owner_port: u16,
    pub cache_debounce: Duration,
    pub cache_poll: Duration,
    pub cache_touch: Duration,
}

impl Config {
    pub fn from_env() -> Self {
        Self {
            bind: env::var("WT_RUST_BIND").unwrap_or_else(|_| "127.0.0.1:28017".into()),
            flush_interval: Duration::from_millis(number("WT_RUST_FLUSH_MS", 100).clamp(1, 60_000)),
            max_batch_rows: number("WT_RUST_MAX_BATCH_ROWS", 256).clamp(1, 4096) as usize,
            max_queue_rows: number("WT_RUST_MAX_QUEUE_ROWS", 8192).clamp(1, 1_000_000) as usize,
            max_queue_bytes: number("WT_RUST_MAX_QUEUE_BYTES", 64 * 1024 * 1024)
                .clamp(1024 * 1024, 1024 * 1024 * 1024) as usize,
            dedupe_events: number("WT_RUST_DEDUPE_EVENTS", 65_536).min(1_000_000) as usize,
            journal_path: env::var("WT_RUST_PENDING_JOURNAL_PATH")
                .unwrap_or_else(|_| "sql_pending_journal.log".into()),
            dead_letter_path: env::var("WT_RUST_DEAD_LETTER_PATH")
                .unwrap_or_else(|_| "sql_dead_letters.log".into()),
            compact_bytes: number("WT_RUST_PENDING_JOURNAL_COMPACT_BYTES", 16 * 1024 * 1024),
            max_frame_bytes: number("WT_RUST_MAX_FRAME_BYTES", 32_768).clamp(1024, 1024 * 1024)
                as usize,
            max_inbound_writes: number("WT_RUST_MAX_INBOUND_WRITES", 256).clamp(1, 4096) as usize,
            max_sql_bytes: number("WT_RUST_MAX_SQL_BYTES", 8192).clamp(256, 1024 * 1024) as usize,
            max_clients: number("WT_RUST_MAX_CLIENTS", 32).clamp(1, 1024) as usize,
            frame_timeout: Duration::from_secs(
                number("WT_RUST_FRAME_TIMEOUT_SECS", 90).clamp(1, 3600),
            ),
            ack_timeout: Duration::from_secs(number("WT_RUST_ACK_TIMEOUT_SECS", 30).clamp(1, 3600)),
            auth_token: env::var("WT_RUST_AUTH_TOKEN").unwrap_or_default(),
            require_localhost: boolean("WT_RUST_REQUIRE_LOCALHOST", true),
            debug: boolean("WT_RUST_DEBUG", false),
            cache_owner_port: number("WT_POINTS_CACHE_OWNER_PORT", 28017).clamp(1, 65535) as u16,
            cache_debounce: Duration::from_millis(
                number("WT_POINTS_CACHE_DEBOUNCE_MS", 3000).clamp(1, 3_600_000),
            ),
            cache_poll: Duration::from_millis(
                number("WT_POINTS_CACHE_POLL_MS", 1000).clamp(1, 60_000),
            ),
            cache_touch: Duration::from_millis(
                number("WT_POINTS_CACHE_TOUCH_MS", 1000).clamp(1, 60_000),
            ),
        }
    }

    pub fn bind_port(&self) -> u16 {
        self.bind
            .rsplit(':')
            .next()
            .and_then(|part| part.parse().ok())
            .unwrap_or(0)
    }
}

pub fn number(key: &str, default: u64) -> u64 {
    env::var(key)
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(default)
}

pub fn boolean(key: &str, default: bool) -> bool {
    env::var(key)
        .ok()
        .map(|value| matches!(value.as_str(), "1" | "true" | "TRUE" | "yes" | "YES"))
        .unwrap_or(default)
}

pub fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .min(u64::MAX as u128) as u64
}
