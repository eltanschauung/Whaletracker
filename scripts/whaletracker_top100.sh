#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/home/kogasa/hlserver/tf2/tf/addons/sourcemod/configs/databases.cfg}"
DB_SECTION="${DB_SECTION:-default}"
LIMIT="${1:-100}"

if ! [[ "$LIMIT" =~ ^[0-9]+$ ]] || [ "$LIMIT" -le 0 ]; then
    echo "usage: $0 [positive_limit]" >&2
    exit 1
fi

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

read -r -d '' SQL <<SQL || true
WITH scored AS (
    SELECT
        w.steamid,
        ROUND(1000.0 * SQRT(((CASE WHEN ((CASE WHEN w.kills > 0 THEN w.kills ELSE 0 END) + (CASE WHEN w.deaths > 0 THEN w.deaths ELSE 0 END)) > 0 THEN ((CASE WHEN w.kills > 0 THEN w.kills ELSE 0 END) + (CASE WHEN w.deaths > 0 THEN w.deaths ELSE 0 END)) ELSE 1 END)) / (((CASE WHEN ((CASE WHEN w.kills > 0 THEN w.kills ELSE 0 END) + (CASE WHEN w.deaths > 0 THEN w.deaths ELSE 0 END)) > 0 THEN ((CASE WHEN w.kills > 0 THEN w.kills ELSE 0 END) + (CASE WHEN w.deaths > 0 THEN w.deaths ELSE 0 END)) ELSE 1 END)) + 400.0)) * (((CASE WHEN w.playtime > 0 THEN w.playtime ELSE 0 END) / 3600.0) / (((CASE WHEN w.playtime > 0 THEN w.playtime ELSE 0 END) / 3600.0) + 20.0)) * ((5.0 * (((CASE WHEN w.kills > 0 THEN w.kills ELSE 0 END) + ((CASE WHEN w.assists > 0 THEN w.assists ELSE 0 END) * 0.35)) / ((CASE WHEN w.deaths > 0 THEN w.deaths ELSE 0 END) + 20.0))) + LN(1.0 + ((CASE WHEN w.damage_dealt > 0 THEN w.damage_dealt ELSE 0 END) / (150.0 * ((CASE WHEN ((CASE WHEN w.kills > 0 THEN w.kills ELSE 0 END) + (CASE WHEN w.deaths > 0 THEN w.deaths ELSE 0 END)) > 0 THEN ((CASE WHEN w.kills > 0 THEN w.kills ELSE 0 END) + (CASE WHEN w.deaths > 0 THEN w.deaths ELSE 0 END)) ELSE 1 END))))) + (0.60 * LN(1.0 + ((CASE WHEN w.healing > 0 THEN w.healing ELSE 0 END) / (100.0 * ((CASE WHEN ((CASE WHEN w.kills > 0 THEN w.kills ELSE 0 END) + (CASE WHEN w.deaths > 0 THEN w.deaths ELSE 0 END)) > 0 THEN ((CASE WHEN w.kills > 0 THEN w.kills ELSE 0 END) + (CASE WHEN w.deaths > 0 THEN w.deaths ELSE 0 END)) ELSE 1 END)))))) + (0.90 * LN(1.0 + ((60.0 * (CASE WHEN w.total_ubers > 0 THEN w.total_ubers ELSE 0 END)) / ((CASE WHEN ((CASE WHEN w.kills > 0 THEN w.kills ELSE 0 END) + (CASE WHEN w.deaths > 0 THEN w.deaths ELSE 0 END)) > 0 THEN ((CASE WHEN w.kills > 0 THEN w.kills ELSE 0 END) + (CASE WHEN w.deaths > 0 THEN w.deaths ELSE 0 END)) ELSE 1 END))))))) AS points,
        COALESCE(NULLIF(w.cached_personaname,''), w.steamid) AS name,
        COALESCE((SELECT p.newname FROM prename_rules p WHERE p.pattern = w.steamid LIMIT 1), '') AS prename,
        COALESCE(NULLIF(f.color,''), 'gold') AS color
    FROM whaletracker w
    LEFT JOIN filters_namecolors f ON f.steamid = w.steamid
    WHERE ((CASE WHEN w.kills > 0 THEN w.kills ELSE 0 END) + (CASE WHEN w.deaths > 0 THEN w.deaths ELSE 0 END)) >= 200
      AND (CASE WHEN w.playtime > 0 THEN w.playtime ELSE 0 END) >= 10800
),
ranked AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY points DESC, steamid ASC) AS rank,
        points,
        name,
        prename,
        color
    FROM scored
)
SELECT rank, points, name, prename, color
FROM ranked
ORDER BY rank ASC
LIMIT ${LIMIT};
SQL

MYSQL_PWD="$PASS" mysql \
    --batch \
    --raw \
    --host="$HOST" \
    --port="$PORT" \
    --user="$USER" \
    "$DATABASE" \
    -e "$SQL"
