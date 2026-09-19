//! Historical migrations retain their columns and SQL semantics. Schema work is
//! serialized in MySQL so the SourceMod plugin only sees complete migrations.
use crate::{
    config::{now_ms, number, Config, SCHEMA_VERSION},
    database::{connection, with_named_lock},
};
use mysql::{params, prelude::Queryable, Pool, PooledConn};
use std::{
    thread,
    time::{Duration, Instant},
};

pub struct Migration {
    pub version: u32,
    pub name: &'static str,
    pub statements: Vec<String>,
}

pub fn prepare(pool: &Pool, cfg: &Config) -> Result<(), String> {
    if cfg.bind_port() == cfg.cache_owner_port {
        let conn = connection(pool)?;
        let applied = with_named_lock(conn, "wt-schema", 30, |conn| {
            ensure_version_table(conn)?;
            let current = current_version(conn)?;
            for migration in migrations()
                .into_iter()
                .filter(|migration| migration.version > current)
            {
                eprintln!("[schema] applying {} {}", migration.version, migration.name);
                for statement in &migration.statements {
                    conn.query_drop(statement).map_err(|err| err.to_string())?;
                }
                conn.exec_drop(
                    "INSERT INTO whaletracker_schema_migrations (version, name, applied_at) VALUES (:version, :name, :applied_at)",
                    params! {"version" => migration.version, "name" => migration.name, "applied_at" => now_ms()},
                ).map_err(|err| err.to_string())?;
            }
            Ok(())
        })?;
        if applied.is_none() {
            return Err("schema migration lock was not acquired".into());
        }
        return Ok(());
    }

    let deadline = Instant::now()
        + Duration::from_secs(number("WT_SCHEMA_WAIT_TIMEOUT_SECS", 120).clamp(1, 3600));
    loop {
        let result = connection(pool).and_then(|mut conn| current_version(&mut conn));
        if matches!(result, Ok(version) if version >= SCHEMA_VERSION) {
            return Ok(());
        }
        if Instant::now() >= deadline {
            return Err(format!(
                "schema owner did not publish version {SCHEMA_VERSION} before the deadline"
            ));
        }
        thread::sleep(Duration::from_secs(1));
    }
}

fn ensure_version_table(conn: &mut PooledConn) -> Result<(), String> {
    conn.query_drop("CREATE TABLE IF NOT EXISTS whaletracker_schema_migrations (version INTEGER PRIMARY KEY, name VARCHAR(128) NOT NULL, applied_at BIGINT DEFAULT 0) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")
        .map_err(|err| err.to_string())
}

fn current_version(conn: &mut PooledConn) -> Result<u32, String> {
    conn.query_first::<u32, _>(
        "SELECT COALESCE(MAX(version), 0) FROM whaletracker_schema_migrations",
    )
    .map(|value| value.unwrap_or(0))
    .map_err(|err| err.to_string())
}

fn columns(definitions: &[&str]) -> Vec<String> {
    definitions
        .iter()
        .map(|value| (*value).to_string())
        .collect()
}

fn class_columns() -> Vec<String> {
    let mut result = vec!["`classes_mask` INTEGER DEFAULT 0".into()];
    for class in [
        "scout", "sniper", "soldier", "demoman", "medic", "heavy", "pyro", "spy", "engineer",
    ] {
        result.push(format!("`shots_{class}` INTEGER DEFAULT 0"));
        result.push(format!("`hits_{class}` INTEGER DEFAULT 0"));
    }
    result
}

fn category_columns() -> Vec<String> {
    let mut result = Vec::new();
    for category in [
        "shotguns",
        "scatterguns",
        "pistols",
        "rocketlaunchers",
        "grenadelaunchers",
        "stickylaunchers",
        "snipers",
        "revolvers",
    ] {
        result.push(format!("`shots_{category}` INTEGER DEFAULT 0"));
        result.push(format!("`hits_{category}` INTEGER DEFAULT 0"));
    }
    result
}

fn create_table(name: &str, data: &[String], keys: &[&str]) -> String {
    let mut all = data.to_vec();
    all.extend(keys.iter().map(|value| (*value).to_string()));
    format!(
        "CREATE TABLE IF NOT EXISTS `{name}` ({}) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
        all.join(", ")
    )
}

pub fn migrations() -> Vec<Migration> {
    let mut lifetime = columns(&[
        "`steamid` VARCHAR(32) NOT NULL",
        "`first_seen` INTEGER DEFAULT NULL",
        "`kills` INTEGER DEFAULT 0",
        "`deaths` INTEGER DEFAULT 0",
        "`shots` INTEGER DEFAULT 0",
        "`hits` INTEGER DEFAULT 0",
        "`healing` INTEGER DEFAULT 0",
        "`total_ubers` INTEGER DEFAULT 0",
        "`best_ubers_life` INTEGER DEFAULT 0",
        "`medic_drops` INTEGER DEFAULT 0",
        "`uber_drops` INTEGER DEFAULT 0",
        "`airshots` INTEGER DEFAULT 0",
        "`telefrags` INTEGER DEFAULT 0",
        "`bonusPoints` INTEGER DEFAULT 0",
        "`totalCrossbowHits` INTEGER DEFAULT 0",
        "`marketGardenHits` INTEGER DEFAULT 0",
        "`headshots` INTEGER DEFAULT 0",
        "`backstabs` INTEGER DEFAULT 0",
        "`best_headshots_life` INTEGER DEFAULT 0",
        "`best_backstabs_life` INTEGER DEFAULT 0",
        "`best_kills_life` INTEGER DEFAULT 0",
        "`best_killstreak` INTEGER DEFAULT 0",
        "`best_score_life` INTEGER DEFAULT 0",
        "`assists` INTEGER DEFAULT 0",
        "`best_assists_life` INTEGER DEFAULT 0",
        "`playtime` INTEGER DEFAULT 0",
        "`is_admin` TINYINT DEFAULT 0",
        "`damage_dealt` INTEGER DEFAULT 0",
        "`damage_taken` INTEGER DEFAULT 0",
        "`last_seen` INTEGER DEFAULT 0",
        "`personaname` VARCHAR(128) DEFAULT ''",
        "`favorite_class` TINYINT DEFAULT 0",
        "`cached_personaname` VARCHAR(255) DEFAULT NULL",
        "`cached_personaname_lower` VARCHAR(255) DEFAULT NULL",
    ]);
    lifetime.extend(class_columns());
    lifetime.extend(category_columns());
    lifetime.push("`sort_weight` DOUBLE AS (CASE WHEN playtime >= 14400 THEN (kills + (0.5 * assists)) / GREATEST(deaths, 1) ELSE -1 END) STORED".into());

    let mut online = columns(&[
        "`steamid` VARCHAR(32) NOT NULL",
        "`personaname` VARCHAR(128) DEFAULT ''",
        "`class` TINYINT DEFAULT 0",
        "`team` TINYINT DEFAULT 0",
        "`alive` TINYINT DEFAULT 0",
        "`is_spectator` TINYINT DEFAULT 0",
        "`kills` INTEGER DEFAULT 0",
        "`deaths` INTEGER DEFAULT 0",
        "`assists` INTEGER DEFAULT 0",
        "`damage` INTEGER DEFAULT 0",
        "`damage_taken` INTEGER DEFAULT 0",
        "`healing` INTEGER DEFAULT 0",
        "`headshots` INTEGER DEFAULT 0",
        "`backstabs` INTEGER DEFAULT 0",
        "`medic_drops` INTEGER DEFAULT 0",
        "`uber_drops` INTEGER DEFAULT 0",
        "`airshots` INTEGER DEFAULT 0",
        "`marketGardenHits` INTEGER DEFAULT 0",
        "`playtime` INTEGER DEFAULT 0",
        "`total_ubers` INTEGER DEFAULT 0",
        "`best_streak` INTEGER DEFAULT 0",
        "`best_ubers_life` INTEGER DEFAULT 0",
        "`current_killstreak` INTEGER DEFAULT 0",
        "`current_ubers_life` INTEGER DEFAULT 0",
        "`visible_max` INTEGER DEFAULT 0",
        "`time_connected` INTEGER DEFAULT 0",
        "`shots` INTEGER DEFAULT 0",
        "`hits` INTEGER DEFAULT 0",
        "`host_ip` VARCHAR(64) DEFAULT ''",
        "`host_port` INTEGER DEFAULT 0",
        "`playercount` INTEGER DEFAULT 0",
        "`map_name` VARCHAR(128) DEFAULT ''",
        "`last_update` INTEGER DEFAULT 0",
    ]);
    online.extend(class_columns());
    online.extend(category_columns());
    for slot in 1..=6 {
        online.extend([
            format!("`weapon{slot}_name` VARCHAR(64) DEFAULT ''"),
            format!("`weapon{slot}_accuracy` FLOAT DEFAULT 0"),
            format!("`weapon{slot}_shots` INTEGER DEFAULT 0"),
            format!("`weapon{slot}_hits` INTEGER DEFAULT 0"),
        ]);
    }
    let online_meta = columns(&[
        "`id` TINYINT NOT NULL",
        "`map_name` VARCHAR(128) DEFAULT ''",
        "`playercount` INTEGER DEFAULT 0",
        "`updated_at` INTEGER DEFAULT 0",
        "`host_ip` VARCHAR(64) DEFAULT ''",
        "`host_port` INTEGER DEFAULT 0",
        "`visible_max` INTEGER DEFAULT 0",
    ]);
    let servers = columns(&[
        "`ip` VARCHAR(64) NOT NULL",
        "`port` INTEGER NOT NULL",
        "`playercount` INTEGER DEFAULT 0",
        "`visible_max` INTEGER DEFAULT 0",
        "`game` VARCHAR(64) DEFAULT ''",
        "`game_url` VARCHAR(32) DEFAULT ''",
        "`map` VARCHAR(128) DEFAULT ''",
        "`city` VARCHAR(128) DEFAULT ''",
        "`country` VARCHAR(8) DEFAULT ''",
        "`flags` VARCHAR(256) DEFAULT ''",
        "`last_update` INTEGER DEFAULT 0",
    ]);
    let logs = columns(&[
        "`log_id` VARCHAR(64) NOT NULL",
        "`map` VARCHAR(64) DEFAULT ''",
        "`gamemode` VARCHAR(64) DEFAULT 'Unknown'",
        "`started_at` INTEGER DEFAULT 0",
        "`ended_at` INTEGER DEFAULT 0",
        "`duration` INTEGER DEFAULT 0",
        "`player_count` INTEGER DEFAULT 0",
        "`created_at` INTEGER DEFAULT 0",
        "`updated_at` INTEGER DEFAULT 0",
        "`finalized` TINYINT NOT NULL DEFAULT 1",
    ]);
    let mut players = columns(&[
        "`log_id` VARCHAR(64) NOT NULL",
        "`steamid` VARCHAR(32) NOT NULL",
        "`personaname` VARCHAR(128) DEFAULT ''",
        "`kills` INTEGER DEFAULT 0",
        "`deaths` INTEGER DEFAULT 0",
        "`assists` INTEGER DEFAULT 0",
        "`damage` INTEGER DEFAULT 0",
        "`damage_taken` INTEGER DEFAULT 0",
        "`healing` INTEGER DEFAULT 0",
        "`headshots` INTEGER DEFAULT 0",
        "`backstabs` INTEGER DEFAULT 0",
        "`total_ubers` INTEGER DEFAULT 0",
        "`playtime` INTEGER DEFAULT 0",
        "`medic_drops` INTEGER DEFAULT 0",
        "`uber_drops` INTEGER DEFAULT 0",
        "`airshots` INTEGER DEFAULT 0",
        "`marketGardenHits` INTEGER DEFAULT 0",
        "`shots` INTEGER DEFAULT 0",
        "`hits` INTEGER DEFAULT 0",
        "`best_streak` INTEGER DEFAULT 0",
        "`best_headshots_life` INTEGER DEFAULT 0",
        "`best_backstabs_life` INTEGER DEFAULT 0",
        "`best_score_life` INTEGER DEFAULT 0",
        "`best_kills_life` INTEGER DEFAULT 0",
        "`best_assists_life` INTEGER DEFAULT 0",
        "`best_ubers_life` INTEGER DEFAULT 0",
        "`is_admin` TINYINT DEFAULT 0",
        "`last_updated` INTEGER DEFAULT 0",
    ]);
    players.extend(class_columns());
    players.extend(category_columns());
    for slot in 1..=6 {
        players.push(format!("`weapon{slot}_name` VARCHAR(128) DEFAULT ''"));
        for field in ["shots", "hits", "damage", "defindex"] {
            players.push(format!("`weapon{slot}_{field}` INTEGER DEFAULT 0"));
        }
    }
    for class in ["soldier", "demoman", "sniper", "medic"] {
        players.push(format!("`airshots_{class}` INTEGER DEFAULT 0"));
        players.push(format!("`airshots_{class}_height` INTEGER DEFAULT 0"));
    }
    let cache = columns(&[
        "`steamid` VARCHAR(32) NOT NULL",
        "`points` INTEGER DEFAULT 0",
        "`rank` INTEGER DEFAULT 0",
        "`name_color` VARCHAR(32) DEFAULT ''",
        "`updated_at` INTEGER DEFAULT 0",
        "`matches_used` INTEGER DEFAULT 0",
        "`rolling_kills` INTEGER DEFAULT 0",
        "`rolling_deaths` INTEGER DEFAULT 0",
        "`window_started_at` INTEGER DEFAULT 0",
        "`window_ended_at` INTEGER DEFAULT 0",
    ]);
    let create = vec![
        create_table("whaletracker", &lifetime, &[
            "PRIMARY KEY (`steamid`)", "KEY `idx_cached_personaname_lower` (`cached_personaname_lower`)",
            "KEY `idx_last_seen` (`last_seen`)", "KEY `idx_sort_weight` (`sort_weight` DESC, `kills` DESC)",
        ]),
        create_table("whaletracker_online", &online, &["PRIMARY KEY (`steamid`)"]),
        create_table("whaletracker_online_meta", &online_meta, &["PRIMARY KEY (`id`)"]),
        create_table("whaletracker_servers", &servers, &["PRIMARY KEY (`ip`, `port`)"]),
        create_table("whaletracker_logs", &logs, &["PRIMARY KEY (`log_id`)"]),
        create_table("whaletracker_log_players", &players, &["PRIMARY KEY (`log_id`, `steamid`)"]),
        create_table("whaletracker_points_cache", &cache, &["PRIMARY KEY (`steamid`)"]),
        "CREATE TABLE IF NOT EXISTS whaletracker_points_cache_build LIKE whaletracker_points_cache".into(),
        "CREATE TABLE IF NOT EXISTS whaletracker_points_cache_state (cache_key VARCHAR(64) PRIMARY KEY, dirty TINYINT DEFAULT 0, dirty_updated_at BIGINT DEFAULT 0, last_reason VARCHAR(64) DEFAULT '', last_rebuilt_at BIGINT DEFAULT 0) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4".into(),
    ];
    let tables = [
        ("whaletracker", &lifetime),
        ("whaletracker_online", &online),
        ("whaletracker_online_meta", &online_meta),
        ("whaletracker_servers", &servers),
        ("whaletracker_logs", &logs),
        ("whaletracker_log_players", &players),
        ("whaletracker_points_cache", &cache),
        ("whaletracker_points_cache_build", &cache),
    ];
    let mut upgrade = Vec::new();
    for (table, data) in &tables {
        for column in *data {
            upgrade.push(format!(
                "ALTER TABLE `{table}` ADD COLUMN IF NOT EXISTS {column}"
            ));
        }
    }
    upgrade.extend(columns(&[
        "CREATE INDEX IF NOT EXISTS idx_cached_personaname_lower ON whaletracker (cached_personaname_lower)",
        "CREATE INDEX IF NOT EXISTS idx_last_seen ON whaletracker (last_seen)",
        "CREATE INDEX IF NOT EXISTS idx_sort_weight ON whaletracker (sort_weight DESC, kills DESC)",
    ]));
    for (table, _) in &tables {
        upgrade.push(format!(
            "ALTER TABLE {table} CONVERT TO CHARACTER SET utf8mb4"
        ));
    }
    upgrade.push("DROP TABLE IF EXISTS whaletracker_mapstats".into());
    vec![
        Migration {version: 1, name: "create_whaletracker_schema", statements: create},
        Migration {version: 2, name: "upgrade_whaletracker_schema", statements: upgrade},
        Migration {version: 3, name: "remove_dead_whaletracker_columns", statements: columns(&[
            "ALTER TABLE whaletracker ADD COLUMN IF NOT EXISTS totalCrossbowHits INTEGER DEFAULT 0",
            "ALTER TABLE whaletracker DROP COLUMN IF EXISTS medicKills", "ALTER TABLE whaletracker DROP COLUMN IF EXISTS heavyKills",
        ])},
        Migration {version: 4, name: "add_whaletracker_telefrag_stat", statements: columns(&[
            "ALTER TABLE whaletracker ADD COLUMN IF NOT EXISTS telefrags INTEGER DEFAULT 0",
        ])},
        Migration {version: 5, name: "version_cache_invalidations", statements: columns(&[
            "ALTER TABLE whaletracker_points_cache_state ADD COLUMN IF NOT EXISTS dirty_generation BIGINT UNSIGNED NOT NULL DEFAULT 0",
            "ALTER TABLE whaletracker_points_cache_state ADD COLUMN IF NOT EXISTS dirty_since BIGINT UNSIGNED NOT NULL DEFAULT 0",
        ])},
        Migration {version: 6, name: "rolling_match_points", statements: columns(&[
            "ALTER TABLE whaletracker_logs ADD COLUMN IF NOT EXISTS finalized TINYINT NOT NULL DEFAULT 1",
            "ALTER TABLE whaletracker_points_cache ADD COLUMN IF NOT EXISTS matches_used INTEGER DEFAULT 0",
            "ALTER TABLE whaletracker_points_cache ADD COLUMN IF NOT EXISTS window_started_at INTEGER DEFAULT 0",
            "ALTER TABLE whaletracker_points_cache ADD COLUMN IF NOT EXISTS window_ended_at INTEGER DEFAULT 0",
            "ALTER TABLE whaletracker_points_cache_build ADD COLUMN IF NOT EXISTS matches_used INTEGER DEFAULT 0",
            "ALTER TABLE whaletracker_points_cache_build ADD COLUMN IF NOT EXISTS window_started_at INTEGER DEFAULT 0",
            "ALTER TABLE whaletracker_points_cache_build ADD COLUMN IF NOT EXISTS window_ended_at INTEGER DEFAULT 0",
            "CREATE INDEX IF NOT EXISTS idx_whaletracker_logs_rank_window ON whaletracker_logs (finalized, ended_at, duration, log_id)",
            "CREATE INDEX IF NOT EXISTS idx_whaletracker_log_players_steamid_log ON whaletracker_log_players (steamid, log_id)",
        ])},
        Migration {version: 7, name: "cache_rolling_kd_totals", statements: columns(&[
            "ALTER TABLE whaletracker_points_cache ADD COLUMN IF NOT EXISTS rolling_kills INTEGER DEFAULT 0",
            "ALTER TABLE whaletracker_points_cache ADD COLUMN IF NOT EXISTS rolling_deaths INTEGER DEFAULT 0",
            "ALTER TABLE whaletracker_points_cache_build ADD COLUMN IF NOT EXISTS rolling_kills INTEGER DEFAULT 0",
            "ALTER TABLE whaletracker_points_cache_build ADD COLUMN IF NOT EXISTS rolling_deaths INTEGER DEFAULT 0",
        ])},
    ]
}
