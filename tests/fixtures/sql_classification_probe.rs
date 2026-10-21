// Compiled by perf_refactor_probe.py with current and pinned baseline modules.
// Kept under fixtures so Cargo does not discover it as an integration crate.
use std::{hint::black_box, time::Instant};

fn fixtures() -> Vec<String> {
    let mut cases = vec![
        "REPLACE INTO whaletracker_online (steamid, personaname) VALUES ('76561198000000000', 'fixture')".into(),
        "UPDATE whaletracker SET kills=42 WHERE steamid='76561198000000000'".into(),
        "INSERT INTO whaletracker_log_players (damage, damage_taken, playtime, personaname) VALUES (2400, 1200, 120, 'fixture') ON DUPLICATE KEY UPDATE damage=VALUES(damage)".into(),
        "/* wt_points_cache_round_end */ UPDATE whaletracker_logs SET points_snapshot_at=123 WHERE log_id='fixture'".into(),
    ];
    for prefix in ["", "  ", "/* unrelated */ ", "-- comment\n", "# comment\n", "/* wt_points_cache_finalize */ "] {
        for table in ["whaletracker", "whaletracker_online", "whaletracker_logs", "whaletracker_log_players", "`db`.`whaletracker_online`", "`whaletracker_logs`"] {
            for statement in [
                format!("INSERT INTO {table} (damage, damage_taken, playtime, personaname) VALUES (2400, 0, 120, 'whaletracker_online; \\\'')"),
                format!("UPDATE {table} SET personaname='whaletracker_logs'"),
                format!("DELETE FROM {table} WHERE steamid='1'; /* end */"),
                format!("CREATE TEMPORARY TABLE {table} (x INT)"),
                format!("DROP TABLE IF EXISTS {table}"),
                format!("ALTER TABLE {table} ADD COLUMN x INT"),
                format!("INSERT INTO {table} (damage, damage_taken, playtime) VALUES (4738, 0, 22)"),
                format!("UPDATE {table} SET kills=1; DELETE FROM whaletracker"),
            ] {
                cases.push(format!("{prefix}{statement}"));
            }
        }
    }
    cases.extend(["", "SELECT 1", "BEGIN", "SET autocommit=0", "UPDATE whaletracker SET x='unterminated", "UPDATE whaletracker SET x=1 /*!; COMMIT */", "UPDATE whaletracker SET x=1\0", "INSERT IGNORE INTO `db`.`whaletracker` (x) VALUES ('é界')", "CREATE INDEX idx ON whaletracker_online (steamid)"] .map(str::to_owned));
    cases
}

#[test]
fn differential_validation_and_metadata() {
    let cases = fixtures();
    for text in &cases {
        let old = legacy::validate_write(text);
        let new = sql::validate_and_classify(text);
        assert_eq!(old.as_ref().err(), new.as_ref().err(), "validation: {text:?}");
        assert_eq!(sql::validate_write(text), old);
        assert_eq!(format!("{:?}", sql::lane_for(text)), format!("{:?}", legacy::lane_for(text)));
        assert_eq!(sql::target_table(text), legacy::target_table(text));
        assert_eq!(sql::invalidates_points_cache(text), legacy::invalidates_points_cache(text));
        if let Ok(metadata) = new {
            assert_eq!(format!("{:?}", metadata.lane), format!("{:?}", legacy::lane_for(text)));
            assert_eq!(metadata.invalidates_points, legacy::invalidates_points_cache(text));
        }
    }
    println!("differential cases={}", cases.len());
}

#[test]
fn differential_deterministic_mutations() {
    let seeds = fixtures();
    let mut random = 0x210c2026_u64;
    for n in 0..10_000 {
        random = random.wrapping_mul(6364136223846793005).wrapping_add(1);
        let mut text = seeds[n % seeds.len()].as_bytes().to_vec();
        let at = random as usize % (text.len() + 1);
        let alphabet = b"'\"`;/*#-()= \\\n\0";
        text.insert(at, alphabet[(random >> 32) as usize % alphabet.len()]);
        let text = String::from_utf8_lossy(&text);
        let old = legacy::validate_write(&text);
        let new = sql::validate_and_classify(&text);
        assert_eq!(old.as_ref().err(), new.as_ref().err(), "case={n}: {text:?}");
        if let Ok(metadata) = new {
            assert_eq!(format!("{:?}", metadata.lane), format!("{:?}", legacy::lane_for(&text)));
            assert_eq!(metadata.invalidates_points, legacy::invalidates_points_cache(&text));
        }
    }
}

fn main() {
    let cases = fixtures();
    let iterations = 50_000;
    for round in 0..5 {
        // Alternate order to reduce systematic warm-up/order bias.
        for old in if round % 2 == 0 { [true, false] } else { [false, true] } {
            let start = Instant::now();
            for _ in 0..iterations {
                for text in &cases[..4] {
                    let text = black_box(text.as_str());
                    if old {
                        black_box(legacy::validate_write(text).unwrap());
                        black_box(legacy::lane_for(text)); // admission
                        black_box(legacy::lane_for(text)); // publication
                        black_box(legacy::invalidates_points_cache(text));
                    } else {
                        let metadata = sql::validate_and_classify(text).unwrap();
                        black_box(metadata.lane);
                        black_box(metadata.lane);
                        black_box(metadata.invalidates_points);
                    }
                }
            }
            println!("sql round={round} variant={} writes={} ns_per_write={:.1}", if old { "before" } else { "after" }, iterations * 4, start.elapsed().as_nanos() as f64 / (iterations * 4) as f64);
        }
    }
}
