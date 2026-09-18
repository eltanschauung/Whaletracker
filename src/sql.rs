//! Routing and the existing log plausibility guard. This is NOT a SQL security
//! sandbox: the outlet is a trusted, authenticated database writer.
use crate::config::MAX_LOG_DAMAGE_PER_MINUTE;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Lane {
    Online = 0,
    Stats = 1,
    Logs = 2,
}

impl Lane {
    pub const ALL: [Self; 3] = [Self::Online, Self::Stats, Self::Logs];
    pub fn label(self) -> &'static str {
        match self {
            Self::Online => "online",
            Self::Stats => "stats",
            Self::Logs => "logs",
        }
    }
}

// Read only the statement header. Table names inside player names, string
// literals, SELECT subqueries, and comments must not choose a writer lane.
fn head_tokens(sql: &str) -> Vec<String> {
    let bytes = sql.as_bytes();
    let mut result = Vec::new();
    let mut at = 0;
    while at < bytes.len() && result.len() < 32 {
        let c = bytes[at];
        if c.is_ascii_whitespace() {
            at += 1;
            continue;
        }
        if c == b'#'
            || (c == b'-'
                && bytes.get(at + 1) == Some(&b'-')
                && bytes.get(at + 2).is_some_and(u8::is_ascii_whitespace))
        {
            while at < bytes.len() && bytes[at] != b'\n' {
                at += 1;
            }
            continue;
        }
        if c == b'/' && bytes.get(at + 1) == Some(&b'*') {
            at += 2;
            while at + 1 < bytes.len() && !(bytes[at] == b'*' && bytes[at + 1] == b'/') {
                at += 1;
            }
            at = (at + 2).min(bytes.len());
            continue;
        }
        if c == b'\'' || c == b'"' {
            let quote = c;
            at += 1;
            while at < bytes.len() {
                if bytes[at] == b'\\' {
                    at = (at + 2).min(bytes.len());
                    continue;
                }
                if bytes[at] == quote {
                    at += 1;
                    if bytes.get(at) == Some(&quote) {
                        at += 1;
                        continue;
                    }
                    break;
                }
                at += 1;
            }
            result.push("<literal>".into());
            continue;
        }
        if c == b'`' {
            let start = at + 1;
            at = start;
            while at < bytes.len() && bytes[at] != b'`' {
                at += 1;
            }
            result.push(sql[start..at].to_ascii_lowercase());
            at = (at + 1).min(bytes.len());
            continue;
        }
        if c.is_ascii_alphanumeric() || c == b'_' {
            let start = at;
            while at < bytes.len() && (bytes[at].is_ascii_alphanumeric() || bytes[at] == b'_') {
                at += 1;
            }
            result.push(sql[start..at].to_ascii_lowercase());
            continue;
        }
        if c == b'(' {
            break;
        }
        if c == b'.' {
            result.push(".".into());
        }
        at += 1;
    }
    result
}

pub fn target_table(sql: &str) -> Option<String> {
    let words = head_tokens(sql);
    let first = words.first()?.as_str();
    let mut index = match first {
        "insert" | "replace" => words
            .iter()
            .position(|word| word == "into")
            .map(|at| at + 1)
            .unwrap_or(1),
        "update" => 1,
        "delete" => words.iter().position(|word| word == "from")? + 1,
        "alter" | "truncate" => {
            if words.get(1).is_some_and(|word| word == "table") {
                2
            } else {
                1
            }
        }
        "create" | "drop" => {
            if let Some(at) = words.iter().position(|word| word == "table") {
                at + 1
            } else {
                words.iter().position(|word| word == "on")? + 1
            }
        }
        _ => return None,
    };
    while words.get(index).is_some_and(|word| {
        matches!(
            word.as_str(),
            "if" | "not" | "exists" | "low_priority" | "ignore"
        )
    }) {
        index += 1;
    }
    if words.get(index + 1).is_some_and(|word| word == ".") {
        index += 2;
    }
    words.get(index).cloned()
}

pub fn lane_for(sql: &str) -> Lane {
    match target_table(sql).as_deref() {
        Some("whaletracker_online" | "whaletracker_online_meta" | "whaletracker_servers") => {
            Lane::Online
        }
        Some(
            "whaletracker"
            | "whaletracker_points_cache"
            | "whaletracker_points_cache_state"
            | "whaletracker_points_cache_build",
        ) => Lane::Stats,
        _ => Lane::Logs,
    }
}

pub fn invalidates_points_cache(sql: &str) -> bool {
    sql.contains("wt_points_cache_finalize")
}

pub fn validate_write(sql: &str) -> Result<(), String> {
    if sql.trim().is_empty() {
        return Err("empty SQL write".into());
    }
    let head = head_tokens(sql);
    let temporary_table = head
        .first()
        .is_some_and(|word| word == "create" || word == "drop")
        && head.get(1).is_some_and(|word| word == "temporary");
    if target_table(sql).is_none() || temporary_table {
        return Err("outlet accepts table writes, not session or transaction control".into());
    }
    validate_single_statement(sql)?;
    if target_table(sql).as_deref() == Some("whaletracker_log_players") {
        validate_log_player_write(sql)?;
    }
    Ok(())
}

fn validate_single_statement(sql: &str) -> Result<(), String> {
    let bytes = sql.as_bytes();
    let mut at = 0;
    let mut ended = false;
    while at < bytes.len() {
        let byte = bytes[at];
        if byte == 0 {
            return Err("NUL in SQL write".into());
        }
        if byte.is_ascii_whitespace() {
            at += 1;
            continue;
        }
        if byte == b'#'
            || (byte == b'-'
                && bytes.get(at + 1) == Some(&b'-')
                && bytes.get(at + 2).is_some_and(u8::is_ascii_whitespace))
        {
            while at < bytes.len() && bytes[at] != b'\n' {
                at += 1;
            }
            continue;
        }
        if byte == b'/' && bytes.get(at + 1) == Some(&b'*') {
            if bytes.get(at + 2) == Some(&b'!') {
                return Err("executable SQL comments are not accepted".into());
            }
            at += 2;
            while at + 1 < bytes.len() && !(bytes[at] == b'*' && bytes[at + 1] == b'/') {
                at += 1;
            }
            if at + 1 >= bytes.len() {
                return Err("unterminated SQL comment".into());
            }
            at += 2;
            continue;
        }
        if ended {
            return Err("multiple SQL statements are not accepted".into());
        }
        if byte == b';' {
            ended = true;
            at += 1;
            continue;
        }
        if byte == b'\'' || byte == b'"' || byte == b'`' {
            let quote = byte;
            at += 1;
            let mut closed = false;
            while at < bytes.len() {
                if bytes[at] == b'\\' && quote != b'`' {
                    at = (at + 2).min(bytes.len());
                    continue;
                }
                if bytes[at] == quote {
                    at += 1;
                    if bytes.get(at) == Some(&quote) {
                        at += 1;
                        continue;
                    }
                    closed = true;
                    break;
                }
                at += 1;
            }
            if !closed {
                return Err("unterminated SQL quoted value".into());
            }
            continue;
        }
        at += 1;
    }
    Ok(())
}

fn validate_log_player_write(sql: &str) -> Result<(), String> {
    let Some((columns, values)) = parse_insert_columns_values(sql) else {
        return Ok(());
    };
    let damage =
        int_column(&columns, &values, "damage").ok_or("missing log-player damage column")?;
    let damage_taken = int_column(&columns, &values, "damage_taken")
        .ok_or("missing log-player damage_taken column")?;
    let playtime =
        int_column(&columns, &values, "playtime").ok_or("missing log-player playtime column")?;
    if !is_log_rate_plausible(damage, playtime) || !is_log_rate_plausible(damage_taken, playtime) {
        return Err(format!("implausible log-player rate: damage={damage} damage_taken={damage_taken} playtime={playtime} max_dpm={MAX_LOG_DAMAGE_PER_MINUTE}"));
    }
    Ok(())
}

pub fn is_log_rate_plausible(amount: i64, playtime: i64) -> bool {
    if amount < 0 || playtime < 0 {
        return false;
    }
    if amount == 0 {
        return true;
    }
    playtime > 0 && (amount as f64 * 60.0 / playtime as f64) <= MAX_LOG_DAMAGE_PER_MINUTE
}

fn parse_insert_columns_values(sql: &str) -> Option<(Vec<String>, Vec<String>)> {
    if !head_tokens(sql)
        .first()
        .is_some_and(|word| word == "insert" || word == "replace")
    {
        return None;
    }
    let open = sql.find('(')?;
    let close = matching_paren(sql, open)?;
    let after = close + 1;
    let values_at = sql[after..].to_ascii_lowercase().find("values")? + after;
    let values_open = sql[values_at..].find('(')? + values_at;
    let values_close = matching_paren(sql, values_open)?;
    let columns = split_list(&sql[open + 1..close])
        .into_iter()
        .map(|column| column.trim().trim_matches('`').trim().to_ascii_lowercase())
        .collect::<Vec<_>>();
    let values = split_list(&sql[values_open + 1..values_close]);
    (columns.len() == values.len()).then_some((columns, values))
}

fn matching_paren(sql: &str, open: usize) -> Option<usize> {
    let mut quote = false;
    let mut escaped = false;
    let mut depth = 0;
    for (at, ch) in sql.char_indices().skip_while(|(at, _)| *at < open) {
        if quote {
            if escaped {
                escaped = false;
            } else if ch == '\\' {
                escaped = true;
            } else if ch == '\'' {
                quote = false;
            }
            continue;
        }
        if ch == '\'' {
            quote = true;
        } else if ch == '(' {
            depth += 1;
        } else if ch == ')' {
            depth -= 1;
            if depth == 0 {
                return Some(at);
            }
        }
    }
    None
}

fn split_list(input: &str) -> Vec<String> {
    let mut result = Vec::new();
    let mut start = 0;
    let mut quote = false;
    let mut escaped = false;
    let mut depth = 0;
    for (at, ch) in input.char_indices() {
        if quote {
            if escaped {
                escaped = false;
            } else if ch == '\\' {
                escaped = true;
            } else if ch == '\'' {
                quote = false;
            }
            continue;
        }
        match ch {
            '\'' => quote = true,
            '(' => depth += 1,
            ')' => depth -= 1,
            ',' if depth == 0 => {
                result.push(input[start..at].trim().to_string());
                start = at + 1;
            }
            _ => {}
        }
    }
    result.push(input[start..].trim().to_string());
    result
}

fn int_column(columns: &[String], values: &[String], name: &str) -> Option<i64> {
    let index = columns.iter().position(|column| column == name)?;
    let value = values.get(index)?.trim();
    if value.eq_ignore_ascii_case("null") {
        Some(0)
    } else {
        value.trim_matches('\'').parse().ok()
    }
}

#[cfg(test)]
pub fn preview(sql: &str, max_bytes: usize) -> String {
    if sql.len() <= max_bytes {
        return sql.to_string();
    }
    let mut end = max_bytes;
    while !sql.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}...", &sql[..end])
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn player_strings_and_comments_do_not_route_writes() {
        assert_eq!(
            lane_for("INSERT INTO whaletracker (personaname) VALUES ('whaletracker_online')"),
            Lane::Stats
        );
        assert_eq!(
            lane_for("/* whaletracker_online */ UPDATE `db`.`whaletracker` SET kills=5"),
            Lane::Stats
        );
        assert_eq!(
            lane_for("INSERT INTO whaletracker_historical SELECT * FROM whaletracker"),
            Lane::Logs
        );
        assert_eq!(
            lane_for("ALTER TABLE whaletracker ADD COLUMN IF NOT EXISTS x INT"),
            Lane::Stats
        );
        assert_eq!(
            lane_for("CREATE INDEX x ON whaletracker_online (steamid)"),
            Lane::Online
        );
        assert_eq!(
            lane_for("DELETE FROM whaletracker_online WHERE host_port=27015"),
            Lane::Online
        );
    }
    #[test]
    fn only_explicit_finalization_invalidates_points() {
        assert!(!invalidates_points_cache(
            "UPDATE whaletracker SET kills=kills+1"
        ));
        assert!(!invalidates_points_cache(
            "INSERT INTO whaletracker_logs (finalized) VALUES (0)"
        ));
        assert!(invalidates_points_cache(
            "/* wt_points_cache_finalize */ INSERT INTO whaletracker_logs (finalized) VALUES (1)"
        ));
    }
    #[test]
    fn preserves_plausibility_thresholds() {
        assert!(is_log_rate_plausible(2400, 120));
        assert!(!is_log_rate_plausible(4738, 22));
        assert!(!is_log_rate_plausible(1, 0));
        assert!(!is_log_rate_plausible(-1, 5));
        assert!(is_log_rate_plausible(3000, 60));
        assert!(validate_write("INSERT INTO whaletracker_log_players (damage, damage_taken, playtime) VALUES (2400, 1200, 120)").is_ok());
        assert!(validate_write("INSERT INTO `whaletracker_log_players` (damage, damage_taken, playtime) VALUES (4738, 0, 22)").is_err());
    }
    #[test]
    fn preview_does_not_split_utf8() {
        assert_eq!(preview("abé界", 3), "ab...");
        assert_eq!(preview("界", 0), "...");
    }
}

#[cfg(test)]
mod statement_tests {
    use super::*;
    #[test]
    fn pooled_sessions_reject_transaction_and_session_control() {
        for sql in [
            "BEGIN",
            "COMMIT",
            "SET autocommit=0",
            "USE other",
            "SELECT 1",
            "CREATE TEMPORARY TABLE x (id INT)",
            "UPDATE whaletracker SET kills=1; DELETE FROM whaletracker",
            "UPDATE whaletracker SET kills=1 /*!; COMMIT */",
        ] {
            assert!(validate_write(sql).is_err(), "accepted {sql}");
        }
        assert!(validate_write(
            "UPDATE whaletracker SET personaname='semi;colon' /* regular comment */;"
        )
        .is_ok());
    }
}
