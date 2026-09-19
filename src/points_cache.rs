//! Coalesced invalidations run on every sink instance. Only the configured owner
//! rebuilds, and MySQL serializes rebuilds even when two hosts claim that role.
use crate::{
    config::{
        now_secs, number, Config, RANK_MAX_MATCHES, RANK_MIN_KILLS_ASSISTS, RANK_MIN_MATCHES,
        RANK_MIN_MATCH_DURATION,
    },
    database::{connection, with_named_lock},
};
use mysql::{params, prelude::Queryable, Pool, PooledConn};
use std::{
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    thread,
    time::{Duration, Instant},
};

const WHALE_POINTS_SQL_EXPR: &str = r#"ROUND(
    1000.0
    * SQRT(GREATEST(a.kills + a.deaths, 1) / (GREATEST(a.kills + a.deaths, 1) + 400.0))
    * (
        5.0 * ((a.kills + (a.assists * 0.35)) / (a.deaths + 20.0))
        + LN(1.0 + (a.damage / (150.0 * GREATEST(a.kills + a.deaths, 1))))
        + 0.60 * LN(1.0 + (a.healing / (100.0 * GREATEST(a.kills + a.deaths, 1))))
        + 0.90 * LN(1.0 + ((60.0 * a.total_ubers) / GREATEST(a.kills + a.deaths, 1)))
    )
)"#;

// Grouped by game mode prefix, then alphabetically within each group.
const RANKED_MAPS: &[&str] = &[
    "2koth_abbey",
    "cp_badlands",
    "cp_coldfront",
    "cp_dustbowl_pro_b1",
    "cp_dustbowl_winter",
    "cp_granary",
    "cp_gullywash_final1",
    "cp_mercenarypark",
    "cp_metalworks",
    "cp_mossrock",
    "cp_nagae_b3",
    "cp_powerhouse_no_timer",
    "cp_snakewater_final1",
    "cp_steel_trad",
    "cp_sunshine",
    "ctf_doublecross_snowy",
    "ctf_frosty",
    "ctf_turbine",
    "ctf_turbine_festive",
    "ctf_well",
    "dm_congo_b1",
    "koth_aquaticruin_final2",
    "koth_bagel_rc11",
    "koth_bagel_rc13",
    "koth_brine_rc3a",
    "koth_candidfriend",
    "koth_cascade",
    "koth_citadel_a7",
    "koth_eientei_final1",
    "koth_eivent_final",
    "koth_factory",
    "koth_genbu_ravine_b1",
    "koth_genbu_ravine_v1",
    "koth_govan_rc2",
    "koth_harvest_final",
    "koth_harvest_winter_v3",
    "koth_highpass",
    "koth_icetower_rc7",
    "koth_kemptown_rc4",
    "koth_king",
    "koth_lakeside_final",
    "koth_lumberyard_pro",
    "koth_manjuu_final",
    "koth_minnesota_a2",
    "koth_namicott_j",
    "koth_nerve",
    "koth_nucleus",
    "koth_offblast_pro",
    "koth_product_pro",
    "koth_rocktop_rc2",
    "koth_slaughterhouse_72_rc1",
    "koth_soot_final1",
    "koth_suijin",
    "koth_sunnymilk",
    "koth_touhvest_b6",
    "koth_watermill_final",
    "pl_badwater",
    "pl_badwater_snowy2",
    "pl_bantwater2_a1",
    "pl_barnblitz",
    "pl_borneo",
    "pl_frontier_final",
    "pl_pier",
    "pl_silverline_rc12",
    "pl_snowycoast",
    "pl_swiftwater_final1",
    "pl_upward",
    "pl_vigil_rc10",
    "plr_bananabay",
    "plr_hightower",
];

pub struct PointsCache {
    pool: Pool,
    cfg: Config,
    pending: AtomicBool,
    max_wait: Duration,
}

impl PointsCache {
    pub fn new(pool: Pool, cfg: Config) -> Arc<Self> {
        Arc::new(Self {
            pool,
            cfg,
            pending: AtomicBool::new(true),
            max_wait: Duration::from_millis(
                number("WT_POINTS_CACHE_MAX_WAIT_MS", 30_000).clamp(1, 3_600_000),
            ),
        })
    }

    pub fn mark_dirty(&self) {
        // No database/network operation on a write-completion path. swap(false)
        // in the worker cannot erase an invalidation arriving during its write.
        self.pending.store(true, Ordering::Release);
    }

    pub fn worker_loop(self: Arc<Self>) {
        let mut last_touch: Option<Instant> = None;
        loop {
            if last_touch.is_none_or(|last| last.elapsed() >= self.cfg.cache_touch)
                && self.pending.swap(false, Ordering::AcqRel)
            {
                match self.persist_invalidation() {
                    Ok(()) => last_touch = Some(Instant::now()),
                    Err(err) => {
                        self.pending.store(true, Ordering::Release);
                        eprintln!("[points-cache] invalidation retained after error: {err}");
                    }
                }
            }
            if self.cfg.bind_port() == self.cfg.cache_owner_port {
                if let Err(err) = self.poll_and_rebuild() {
                    eprintln!("[points-cache] rebuild deferred: {err}");
                }
            }
            thread::sleep(self.cfg.cache_poll);
        }
    }

    fn persist_invalidation(&self) -> Result<(), String> {
        let mut conn = connection(&self.pool)?;
        conn.query_drop(
            "INSERT INTO whaletracker_points_cache_state \
             (cache_key, dirty, dirty_updated_at, last_reason, last_rebuilt_at, dirty_generation, dirty_since) \
             VALUES ('global', 1, CAST(UNIX_TIMESTAMP(CURRENT_TIMESTAMP(3))*1000 AS UNSIGNED), 'match_finalize', 0, 1, CAST(UNIX_TIMESTAMP(CURRENT_TIMESTAMP(3))*1000 AS UNSIGNED)) \
             ON DUPLICATE KEY UPDATE \
             dirty_since = CASE WHEN dirty = 0 OR dirty_since = 0 THEN VALUES(dirty_updated_at) ELSE dirty_since END, \
             dirty = 1, dirty_updated_at = VALUES(dirty_updated_at), \
             last_reason = VALUES(last_reason), dirty_generation = dirty_generation + 1"
        ).map_err(|err| err.to_string())
    }

    fn poll_and_rebuild(&self) -> Result<(), String> {
        let conn = connection(&self.pool)?;
        with_named_lock(conn, "wt-points-cache", 0, |conn| {
            let state: Option<(u8, u64, u64, u64, u64)> = conn.query_first(
                "SELECT dirty, dirty_updated_at, dirty_generation, dirty_since, \
                 CAST(UNIX_TIMESTAMP(CURRENT_TIMESTAMP(3))*1000 AS UNSIGNED) \
                 FROM whaletracker_points_cache_state WHERE cache_key = 'global' LIMIT 1"
            ).map_err(|err| err.to_string())?;
            let Some((dirty, updated, generation, since, now)) = state else { return Ok(()); };
            if dirty == 0 { return Ok(()); }
            let debounce_ms = self.cfg.cache_debounce.as_millis() as u64;
            let max_wait_ms = self.max_wait.as_millis() as u64;
            if now.saturating_sub(updated) < debounce_ms
                && now.saturating_sub(if since == 0 { updated } else { since }) < max_wait_ms
            { return Ok(()); }

            self.rebuild(conn)?;
            // A later invalidation has a different generation even if it happened
            // in the same millisecond. Never acknowledge the newer writer's work.
            conn.exec_drop(
                "UPDATE whaletracker_points_cache_state SET dirty = 0, dirty_since = 0, \
                 last_rebuilt_at = CAST(UNIX_TIMESTAMP(CURRENT_TIMESTAMP(3))*1000 AS UNSIGNED), last_reason = 'rebuilt' \
                 WHERE cache_key = 'global' AND dirty = 1 AND dirty_generation = :generation",
                params! { "generation" => generation },
            ).map_err(|err| err.to_string())?;
            Ok(())
        }).map(|_| ())
    }

    fn rebuild(&self, conn: &mut PooledConn) -> Result<(), String> {
        conn.query_drop("CREATE TABLE IF NOT EXISTS whaletracker_points_cache_build LIKE whaletracker_points_cache")
            .map_err(|err| err.to_string())?;
        conn.query_drop("TRUNCATE TABLE whaletracker_points_cache_build")
            .map_err(|err| err.to_string())?;
        let insert_sql = build_insert_sql(now_secs());
        conn.query_drop(insert_sql).map_err(|err| err.to_string())?;
        // Atomic publication: readers never observe an empty or half-built cache.
        conn.query_drop(
            "RENAME TABLE whaletracker_points_cache TO whaletracker_points_cache_swap, \
             whaletracker_points_cache_build TO whaletracker_points_cache, \
             whaletracker_points_cache_swap TO whaletracker_points_cache_build",
        )
        .map_err(|err| err.to_string())
    }
}

fn build_insert_sql(now: u64) -> String {
    let maps = RANKED_MAPS
        .iter()
        .map(|map| format!("'{map}'"))
        .collect::<Vec<_>>()
        .join(", ");

    format!(
        "INSERT INTO whaletracker_points_cache_build \
         (steamid, points, rank, name_color, updated_at, matches_used, rolling_kills, rolling_deaths, window_started_at, window_ended_at) \
         WITH recent_matches AS (\
             SELECT lp.steamid, \
                    GREATEST(COALESCE(lp.kills, 0), 0) AS kills, \
                    GREATEST(COALESCE(lp.deaths, 0), 0) AS deaths, \
                    GREATEST(COALESCE(lp.assists, 0), 0) AS assists, \
                    GREATEST(COALESCE(lp.damage, 0), 0) AS damage, \
                    GREATEST(COALESCE(lp.healing, 0), 0) AS healing, \
                    GREATEST(COALESCE(lp.total_ubers, 0), 0) AS total_ubers, \
                    l.started_at, l.ended_at, \
                    ROW_NUMBER() OVER (\
                        PARTITION BY lp.steamid \
                        ORDER BY l.ended_at DESC, l.log_id DESC\
                    ) AS recent_row \
             FROM whaletracker_log_players lp \
             INNER JOIN whaletracker_logs l ON l.log_id = lp.log_id \
             WHERE l.finalized = 1 \
               AND l.ended_at > 0 \
               AND l.duration > {min_duration} \
               AND (GREATEST(COALESCE(lp.kills, 0), 0) \
                    + GREATEST(COALESCE(lp.assists, 0), 0)) > {min_kills_assists} \
               AND LOWER(SUBSTRING_INDEX(SUBSTRING_INDEX(l.map, '/', -1), '.ugc', 1)) IN ({maps})\
         ), aggregates AS (\
             SELECT steamid, COUNT(*) AS matches_used, \
                    MIN(started_at) AS window_started_at, \
                    MAX(ended_at) AS window_ended_at, \
                    SUM(kills) AS kills, SUM(deaths) AS deaths, \
                    SUM(assists) AS assists, SUM(damage) AS damage, \
                    SUM(healing) AS healing, SUM(total_ubers) AS total_ubers \
             FROM recent_matches \
             WHERE recent_row <= {max_matches} \
             GROUP BY steamid\
         ), scored AS (\
             SELECT a.*, {expr} AS points \
             FROM aggregates a\
         ), ranked AS (\
             SELECT steamid, \
                    ROW_NUMBER() OVER (ORDER BY points DESC, steamid ASC) AS rank \
             FROM scored \
             WHERE matches_used >= {min_matches}\
         ) \
         SELECT w.steamid, COALESCE(s.points, 0), COALESCE(r.rank, 0), \
                COALESCE(NULLIF(f.color COLLATE utf8mb4_uca1400_ai_ci, ''), \
                         COALESCE(NULLIF(c.name_color, ''), 'gold')), \
                {now}, COALESCE(s.matches_used, 0), \
                COALESCE(s.kills, 0), COALESCE(s.deaths, 0), \
                COALESCE(s.window_started_at, 0), COALESCE(s.window_ended_at, 0) \
         FROM whaletracker w \
         LEFT JOIN scored s ON s.steamid = w.steamid \
         LEFT JOIN ranked r ON r.steamid = w.steamid \
         LEFT JOIN filters_namecolors f \
                ON f.steamid COLLATE utf8mb4_uca1400_ai_ci = w.steamid \
         LEFT JOIN whaletracker_points_cache c ON c.steamid = w.steamid",
        min_duration = RANK_MIN_MATCH_DURATION,
        min_kills_assists = RANK_MIN_KILLS_ASSISTS,
        max_matches = RANK_MAX_MATCHES,
        min_matches = RANK_MIN_MATCHES,
        expr = WHALE_POINTS_SQL_EXPR,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn ranked_maps_are_grouped_sorted_and_unique() {
        let mut previous = ("", "");
        let mut seen = HashSet::new();
        for map in RANKED_MAPS {
            let mode = map.split_once('_').map_or(*map, |(mode, _)| mode);
            let current = (mode, *map);
            assert!(current >= previous, "{map} is out of order");
            assert!(seen.insert(*map), "{map} is duplicated");
            previous = current;
        }
    }

    #[test]
    fn rolling_query_has_required_boundaries() {
        let sql = build_insert_sql(123);
        assert!(sql.contains("l.duration > 300"));
        assert!(sql.contains("recent_row <= 50"));
        assert!(sql.contains("matches_used >= 50"));
        assert!(sql.contains("SUBSTRING_INDEX(SUBSTRING_INDEX(l.map, '/', -1), '.ugc', 1)"));
        assert!(!sql.contains("playtime"));
    }
}
