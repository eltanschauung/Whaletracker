"""Run the actual Rust ranking SQL on an isolated in-memory fixture."""
from pathlib import Path
import re
import math
import sqlite3

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT/'src/points_cache.rs').read_text()
template = source.split('"INSERT INTO whaletracker_points_cache_build ',1)[1].split('",\n        min_duration',1)[0]
template = 'INSERT INTO whaletracker_points_cache_build ' + re.sub(r'\\\n\s*', '', template)
expr = source.split('const WHALE_POINTS_SQL_EXPR: &str = r#"',1)[1].split('"#;',1)[0]
sql = template.format(now=99999, min_duration=300, min_kills_assists=5, max_matches=100,
                      min_matches=35, expr=expr, maps="'koth_harvest_final'")
db = sqlite3.connect(':memory:')
db.create_function('GREATEST', -1, max)
db.create_function('SQRT', 1, math.sqrt)
db.create_function('LN', 1, math.log)
def substring(value, sep, count):
    parts = value.split(sep)
    return sep.join(parts[:count] if count >= 0 else parts[count:])
db.create_function('SUBSTRING_INDEX', 3, substring)
db.create_collation('utf8mb4_uca1400_ai_ci', lambda a,b:(a>b)-(a<b))
db.executescript('''
CREATE TABLE whaletracker (steamid TEXT);
CREATE TABLE whaletracker_logs (log_id TEXT PRIMARY KEY, map TEXT, started_at INTEGER, ended_at INTEGER, duration INTEGER, finalized INTEGER, points_snapshot_at INTEGER);
CREATE TABLE whaletracker_log_players (log_id TEXT, steamid TEXT, kills INTEGER, deaths INTEGER, assists INTEGER, damage INTEGER, healing INTEGER, total_ubers INTEGER, PRIMARY KEY(log_id,steamid));
CREATE TABLE filters_namecolors (steamid TEXT, color TEXT);
CREATE TABLE whaletracker_points_cache (steamid TEXT, name_color TEXT);
CREATE TABLE whaletracker_points_cache_build (steamid TEXT, points INTEGER, rank INTEGER, name_color TEXT, updated_at INTEGER, matches_used INTEGER, rolling_kills INTEGER, rolling_deaths INTEGER, window_started_at INTEGER, window_ended_at INTEGER);
INSERT INTO whaletracker VALUES ('test');
''')
for i in range(35):
    db.execute('INSERT INTO whaletracker_logs VALUES (?, ?, 1, ?, 301, ?, 0)', (str(i),'koth_harvest_final',1000+i, int(i<34)))
    db.execute('INSERT INTO whaletracker_log_players VALUES (?, ?, 10, 5, 2, 3000, 0, 0)', (str(i),'test'))
def rebuild():
    db.execute('DELETE FROM whaletracker_points_cache_build')
    db.execute(sql)
    return db.execute('SELECT points,rank,matches_used,rolling_kills FROM whaletracker_points_cache_build').fetchone()
assert rebuild()[1:] == (0,34,340), 'Unfinished/unpublished log must not qualify'
db.execute("UPDATE whaletracker_logs SET points_snapshot_at=123 WHERE log_id='34'")
ranked = rebuild()
assert ranked[0] > 0 and ranked[1:] == (1,35,350), ranked
assert rebuild() == ranked, 'Repeating the round snapshot cannot double-count'
db.execute("UPDATE whaletracker_logs SET finalized=1 WHERE log_id='34'")
assert rebuild() == ranked, 'Finalizing must not introduce a second match'
db.execute("UPDATE whaletracker_logs SET duration=300 WHERE log_id='34'")
assert rebuild()[1:] == (0,34,340), 'Duration eligibility must remain unchanged'
print('PASS: actual ranking SQL includes published current log once, preserves 35-match/duration rules and finalization identity')
