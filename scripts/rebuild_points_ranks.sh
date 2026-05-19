#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/home/gameserver/hlserver/tf2/tf/addons/sourcemod/configs/databases.cfg}"
DB_SECTION="${DB_SECTION:-default}"

read_db_value() {
    local key="$1"
    awk -v section="$DB_SECTION" -v key="$key" '
        BEGIN {
            in_section = 0;
            depth = 0;
        }

        $0 ~ "\"" section "\"" {
            in_section = 1;
            next;
        }

        in_section && /\{/ {
            depth++;
            next;
        }

        in_section && depth > 0 && $1 == "\"" key "\"" {
            value = $2;
            gsub(/^"/, "", value);
            gsub(/"$/, "", value);
            print value;
            exit;
        }

        in_section && /\}/ {
            depth--;
            if (depth <= 0) {
                exit;
            }
        }
    ' "$CONFIG_FILE"
}

HOST="$(read_db_value host)"
DATABASE="$(read_db_value database)"
USER="$(read_db_value user)"
PASS="$(read_db_value pass)"
PORT="$(read_db_value port)"

if [ -z "$HOST" ] || [ -z "$DATABASE" ] || [ -z "$USER" ]; then
    echo "failed to read MySQL credentials from $CONFIG_FILE section \"$DB_SECTION\"" >&2
    exit 1
fi

if [ -z "$PORT" ]; then
    PORT="3306"
fi

read -r -d '' SQL <<'SQL' || true
START TRANSACTION;

UPDATE whaletracker_points_cache
SET points = 0,
    rank = 0,
    updated_at = 0;

INSERT INTO whaletracker_points_cache (steamid, points, rank, name, name_color, prename, updated_at)
SELECT
    ranked.steamid,
    ranked.points,
    ranked.rank,
    ranked.name,
    ranked.color,
    ranked.prename,
    UNIX_TIMESTAMP()
FROM (
    SELECT
        w.steamid,
        ROW_NUMBER() OVER (
            ORDER BY
                CEIL((((GREATEST(w.damage_dealt,0) / 300.0)
                    + (GREATEST(w.healing,0) / 400.0)
                    + FLOOR((GREATEST(w.kills,0) * 1.5) + (GREATEST(w.assists,0) * 0.5))
                    + GREATEST(w.backstabs,0)
                    + GREATEST(w.headshots,0)
                    + (GREATEST(w.airshots,0) * 3)
                    + GREATEST(w.medicKills,0)
                    + GREATEST(w.heavyKills,0)
                    + (GREATEST(w.marketGardenHits,0) * 5)
                    + (GREATEST(w.total_ubers,0) * 10)) * 10000.0)
                    / GREATEST(GREATEST(w.deaths,0) + (GREATEST(w.damage_taken,0) / 500.0), 1)
                ) DESC,
                w.steamid ASC
        ) AS rank,
        CEIL((((GREATEST(w.damage_dealt,0) / 300.0)
            + (GREATEST(w.healing,0) / 400.0)
            + FLOOR((GREATEST(w.kills,0) * 1.5) + (GREATEST(w.assists,0) * 0.5))
            + GREATEST(w.backstabs,0)
            + GREATEST(w.headshots,0)
            + (GREATEST(w.airshots,0) * 3)
            + GREATEST(w.medicKills,0)
            + GREATEST(w.heavyKills,0)
            + (GREATEST(w.marketGardenHits,0) * 5)
            + (GREATEST(w.total_ubers,0) * 10)) * 10000.0)
            / GREATEST(GREATEST(w.deaths,0) + (GREATEST(w.damage_taken,0) / 500.0), 1)
        ) AS points,
        COALESCE(NULLIF(w.cached_personaname,''), w.steamid) AS name,
        COALESCE(NULLIF(f.color,''), COALESCE(NULLIF(c.name_color,''), 'gold')) AS color,
        COALESCE((SELECT p.newname FROM prename_rules p WHERE p.pattern = w.steamid LIMIT 1), '') AS prename
    FROM whaletracker w
    LEFT JOIN filters_namecolors f ON f.steamid = w.steamid
    LEFT JOIN whaletracker_points_cache c ON c.steamid = w.steamid
    WHERE (GREATEST(w.kills,0) + GREATEST(w.deaths,0)) > 1000
) AS ranked
ON DUPLICATE KEY UPDATE
    points = VALUES(points),
    rank = VALUES(rank),
    name = VALUES(name),
    name_color = VALUES(name_color),
    prename = VALUES(prename),
    updated_at = VALUES(updated_at);

COMMIT;

SELECT COUNT(*) AS ranked_rows,
       MIN(rank) AS min_rank,
       MAX(rank) AS max_rank,
       MIN(updated_at) AS min_updated_at,
       MAX(updated_at) AS max_updated_at
FROM whaletracker_points_cache
WHERE rank > 0;
SQL

MYSQL_PWD="$PASS" mysql \
    --batch \
    --raw \
    --host="$HOST" \
    --port="$PORT" \
    --user="$USER" \
    "$DATABASE" \
    -e "$SQL"
