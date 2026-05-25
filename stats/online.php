<?php
require_once __DIR__ . '/functions.php';

header('Content-Type: application/json');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');

function wt_resolve_map_image(string $mapName): ?string
{
    $mapName = trim($mapName);
    if ($mapName === '') {
        return null;
    }
    $safe = preg_replace('/[^a-zA-Z0-9_\-]/', '', $mapName);
    if ($safe === null || $safe === '') {
        $safe = $mapName;
    }
    $localDir = __DIR__ . '/../playercount_widget';
    $localPath = $localDir . '/' . $safe . '.jpg';
    if (file_exists($localPath)) {
        return '/playercount_widget/' . rawurlencode($safe) . '.jpg';
    }
    return sprintf('https://image.gametracker.com/images/maps/160x120/tf2/%s.jpg', rawurlencode($safe));
}

$cacheKey = 'wt:online:latest';
$cacheTtlSeconds = 300;
$now = time();

$weaponSelectParts = [];
for ($slot = 1; $slot <= WT_MAX_WEAPON_SLOTS; $slot++) {
    $weaponSelectParts[] = sprintf(
        'weapon%d_name, weapon%d_accuracy, weapon%d_shots, weapon%d_hits',
        $slot,
        $slot,
        $slot,
        $slot
    );
}
$weaponSelectSql = implode(', ', $weaponSelectParts);
$weaponSelectClause = $weaponSelectSql !== '' ? ', ' . $weaponSelectSql : '';

$weaponCategoryParts = [];
foreach (WT_WEAPON_CATEGORY_METADATA as $slug => $meta) {
    $weaponCategoryParts[] = sprintf('shots_%s', $slug);
    $weaponCategoryParts[] = sprintf('hits_%s', $slug);
}
$weaponCategorySql = implode(', ', $weaponCategoryParts);
$weaponCategoryClause = $weaponCategorySql !== '' ? ', ' . $weaponCategorySql : '';

try {
    $pdo = wt_pdo();
    wt_clear_online_cache_flag($pdo, $cacheKey);
    $sqlExtended = sprintf(
        'SELECT steamid, personaname, class, team, alive, is_spectator, COALESCE(is_admin, 0) AS is_admin, kills, deaths, assists, damage, damage_taken, healing, headshots, backstabs, shots, hits%s%s, '
        . 'playtime, total_ubers, classes_mask, time_connected, visible_max, last_update '
        . 'FROM whaletracker_online ORDER BY last_update DESC',
        $weaponCategoryClause,
        $weaponSelectClause
    );
    try {
        $stmt = $pdo->query($sqlExtended);
    } catch (Throwable $e) {
        $sqlLegacy = sprintf(
            'SELECT steamid, personaname, class, team, alive, is_spectator, 0 AS is_admin, kills, deaths, assists, damage, damage_taken, healing, headshots, backstabs, shots, hits%s%s, '
            . 'playtime, total_ubers, time_connected, visible_max, last_update '
            . 'FROM whaletracker_online ORDER BY last_update DESC',
            $weaponCategoryClause,
            $weaponSelectClause
        );
        $stmt = $pdo->query($sqlLegacy);
    }
    $players = $stmt->fetchAll();

    foreach ($players as &$row) {
        $row['shots'] = (int)($row['shots'] ?? 0);
        $row['hits'] = (int)($row['hits'] ?? 0);
        $steamId = (string)($row['steamid'] ?? '');
        if ($steamId !== '') {
            $steamIds[] = $steamId;
        }
        $row['classes_mask'] = (int)($row['classes_mask'] ?? 0);
    }
    unset($row);

    $visibleMax = 32;
    $playerCount = 0;
    $mapName = '';
    if (!empty($players)) {
        $candidate = (int)($players[0]['visible_max'] ?? 0);
        if ($candidate > 0) {
            $visibleMax = $candidate;
        }
        $playerCount = (int)($players[0]['playercount'] ?? count($players));
        $mapName = (string)($players[0]['map_name'] ?? '');
    }

    $serverRows = [];
    try {
        $cutoff = $now - 180;
        $stmtServers = $pdo->prepare(
            'SELECT ip, port, playercount, visible_max, map, city, country, flags, last_update '
            . 'FROM whaletracker_servers WHERE last_update >= :cutoff ORDER BY port ASC'
        );
        $stmtServers->bindValue(':cutoff', $cutoff, PDO::PARAM_INT);
        $stmtServers->execute();
        $serverRows = $stmtServers->fetchAll(PDO::FETCH_ASSOC);
    } catch (Throwable $e) {
        $serverRows = [];
    }
    $servers = [];
        foreach ($serverRows as $server) {
            $hostIp = (string)($server['ip'] ?? '');
            $hostPort = (int)($server['port'] ?? 0);
            $name = (string)($server['map'] ?? '');
            $count = (int)($server['playercount'] ?? 0);
            $max = (int)($server['visible_max'] ?? $visibleMax);
            $image = wt_resolve_map_image($name);
            $rawFlags = (string)($server['flags'] ?? '');
            $extraFlags = array_values(array_filter(array_map('trim', explode(',', $rawFlags))));
            $servers[] = [
                'host_ip' => $hostIp,
                'host_port' => $hostPort,
                'map_name' => $name,
                'player_count' => $count,
                'visible_max' => $max,
                'map_image' => $image,
                'city' => (string)($server['city'] ?? ''),
                'country_code' => strtolower((string)($server['country'] ?? '')),
                'extra_flags' => $extraFlags,
                'last_update' => (int)($server['last_update'] ?? 0),
            ];
        }

    if (!empty($steamIds)) {
        $steamIds = array_values(array_unique($steamIds));
        $profiles = wt_fetch_steam_profiles($steamIds);
        $adminFlags = wt_fetch_admin_flags($steamIds);
        $defaultAvatar = WT_DEFAULT_AVATAR_URL;

        foreach ($players as &$row) {
            $steamId = (string)($row['steamid'] ?? '');
            if ($steamId === '') {
                $row['avatar'] = $defaultAvatar;
                $row['is_admin'] = 0;
                $row['weapon_category_summary'] = [];
                $row['active_weapon_accuracy'] = null;
                $row['weapon_accuracy_summary'] = [];
                continue;
            }

            $profile = $profiles[$steamId] ?? null;
            if ($profile !== null) {
                if (!empty($profile['personaname'])) {
                    $row['personaname'] = $profile['personaname'];
                }
                if (!empty($profile['profileurl'])) {
                    $row['profileurl'] = $profile['profileurl'];
                }
            }

            $avatar = ($profile['avatarfull'] ?? '') ?: ($profile['avatarmedium'] ?? '') ?: ($profile['avatar'] ?? '');
            $row['avatar'] = $avatar ?: $defaultAvatar;
            $row['is_admin'] = !empty($adminFlags[$steamId]) ? 1 : (int)($row['is_admin'] ?? 0);

            $weaponSummary = [];
            for ($slot = 1; $slot <= WT_MAX_WEAPON_SLOTS; $slot++) {
                $name = trim((string)($row[sprintf('weapon%d_name', $slot)] ?? ''));
                $accuracy = $row[sprintf('weapon%d_accuracy', $slot)] ?? null;
                $shotsValue = (int)($row[sprintf('weapon%d_shots', $slot)] ?? 0);
                $hitsValue = (int)($row[sprintf('weapon%d_hits', $slot)] ?? 0);
                if ($name === '' || $accuracy === null || $shotsValue <= 0) {
                    continue;
                }
                $weaponSummary[] = [
                    'name' => $name,
                    'accuracy' => (float)$accuracy,
                    'shots' => $shotsValue,
                    'hits' => $hitsValue,
                ];
            }
            $row['weapon_accuracy_summary'] = $weaponSummary;
            wt_assign_weapon_category_summary($row, 'weapon_category_summary', 'active_weapon_accuracy');

            for ($slot = 1; $slot <= WT_MAX_WEAPON_SLOTS; $slot++) {
                unset($row[sprintf('weapon%d_name', $slot)], $row[sprintf('weapon%d_accuracy', $slot)], $row[sprintf('weapon%d_shots', $slot)], $row[sprintf('weapon%d_hits', $slot)]);
            }
        }
        unset($row);
    }

    if (!empty($servers)) {
        $aggregatePlayers = array_sum(array_map(static fn($srv) => $srv['player_count'] ?? 0, $servers));
        $aggregateVisible = array_sum(array_map(static fn($srv) => $srv['visible_max'] ?? 0, $servers));
        if ($playerCount === 0 && $aggregatePlayers > 0) {
            $playerCount = $aggregatePlayers;
        }
        if ($aggregateVisible > 0) {
            $visibleMax = $aggregateVisible;
        }
        if ($mapName === '') {
            $mapName = $servers[0]['map_name'] ?? '';
        }
        $mapImage = $servers[0]['map_image'] ?? wt_resolve_map_image($mapName);
    } else {
        $servers[] = [
            'host_ip' => '',
            'host_port' => 0,
            'map_name' => $mapName,
            'player_count' => $playerCount,
            'visible_max' => $visibleMax,
            'map_image' => wt_resolve_map_image($mapName),
            'last_update' => $now,
        ];
        $mapImage = $servers[0]['map_image'];
    }

    $response = [
        'success' => true,
        'updated' => $now,
        'visible_max_players' => $visibleMax,
        'player_count' => $playerCount > 0 ? $playerCount : count($players),
        'map_name' => $mapName,
        'map_image' => $mapImage,
        'servers' => $servers,
        'players' => $players,
    ];

    if (!empty($players)) {
        wt_cache_set($cacheKey, [
            'timestamp' => $now,
            'response' => $response,
        ], $cacheTtlSeconds);
    }

    echo json_encode($response, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'internal_error',
    ]);
}
