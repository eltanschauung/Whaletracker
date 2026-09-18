#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/home/kogasa/hlserver/tf2/tf/addons/sourcemod/configs/databases.cfg}"
DB_SECTION="${DB_SECTION:-default}"

read_db_value() {
    local key="$1"
    awk -v section="$DB_SECTION" -v key="$key" '
        BEGIN { in_section = 0; depth = 0 }
        $0 ~ "\"" section "\"" { in_section = 1; next }
        in_section && /\{/ { depth++; next }
        in_section && depth > 0 && $1 == "\"" key "\"" {
            value = $2
            gsub(/\r/, "", value)
            gsub(/^"/, "", value)
            gsub(/"$/, "", value)
            print value
            exit
        }
        in_section && /\}/ {
            depth--
            if (depth <= 0) exit
        }
    ' "$CONFIG_FILE"
}

HOST="$(read_db_value host)"
DATABASE="$(read_db_value database)"
USER="$(read_db_value user)"
PASS="$(read_db_value pass)"
PORT="$(read_db_value port)"
PORT="${PORT:-3306}"

if [ -z "$HOST" ] || [ -z "$DATABASE" ] || [ -z "$USER" ]; then
    echo "failed to read MySQL credentials from $CONFIG_FILE section \"$DB_SECTION\"" >&2
    exit 1
fi

mysql_query() {
    MYSQL_PWD="$PASS" mysql --batch --raw --skip-column-names \
        --host="$HOST" --port="$PORT" --user="$USER" "$DATABASE" -e "$1"
}

mysql_query "
INSERT INTO whaletracker_points_cache_state
    (cache_key, dirty, dirty_updated_at, last_reason, last_rebuilt_at,
     dirty_generation, dirty_since)
VALUES
    ('global', 1, CAST(UNIX_TIMESTAMP(CURRENT_TIMESTAMP(3))*1000 AS UNSIGNED),
     'manual_rebuild', 0, 1,
     CAST(UNIX_TIMESTAMP(CURRENT_TIMESTAMP(3))*1000 AS UNSIGNED))
ON DUPLICATE KEY UPDATE
    dirty_since = CASE
        WHEN dirty = 0 OR dirty_since = 0 THEN VALUES(dirty_updated_at)
        ELSE dirty_since
    END,
    dirty = 1,
    dirty_updated_at = VALUES(dirty_updated_at),
    last_reason = VALUES(last_reason),
    dirty_generation = dirty_generation + 1;
"

for _ in $(seq 1 60); do
    read -r dirty rebuilt < <(mysql_query "
        SELECT dirty, last_rebuilt_at
        FROM whaletracker_points_cache_state
        WHERE cache_key = 'global'
        LIMIT 1;
    ")

    if [ "$dirty" = "0" ]; then
        mysql_query "
            SELECT COUNT(*), COALESCE(SUM(rank > 0), 0), MAX(updated_at)
            FROM whaletracker_points_cache;
        " | awk '{ printf "cache_rows=%s ranked_rows=%s updated_at=%s\n", $1, $2, $3 }'
        exit 0
    fi

    sleep 1
done

echo "points-cache rebuild did not finish within 60 seconds" >&2
exit 1
