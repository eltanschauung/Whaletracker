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

MYSQL_PWD="$PASS" mysql --batch --raw \
    --host="$HOST" --port="$PORT" --user="$USER" "$DATABASE" -e "
SELECT
    pc.rank,
    pc.points,
    COALESCE(NULLIF(pr.newname, ''), NULLIF(fs.last_name, ''),
             NULLIF(w.cached_personaname, ''), pc.steamid) AS name,
    COALESCE(NULLIF(pr.newname, ''), '') AS prename,
    COALESCE(NULLIF(pc.name_color, ''), 'gold') AS color
FROM whaletracker_points_cache pc
LEFT JOIN prename_rules pr
       ON pr.pattern COLLATE utf8mb4_uca1400_ai_ci = pc.steamid
LEFT JOIN filters_steam_names fs ON fs.steamid64 = pc.steamid
LEFT JOIN whaletracker w ON w.steamid = pc.steamid
WHERE pc.rank > 0
ORDER BY pc.rank
LIMIT $LIMIT;
"
