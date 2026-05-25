<?php if (!empty($logs)): ?>
    <?php $log = $logs[0];
    $playerCountRaw = (int)($log['player_count'] ?? 0);
    if ($playerCountRaw <= 0 && !empty($log['players']) && is_array($log['players'])) {
        $playerCountRaw = count($log['players']);
    }
    $gamemodeRaw = $log['gamemode'] ?? 'Unknown';
    $badgeLabel = wt_format_gamemode_label($gamemodeRaw);
    $mapNameRaw = (string)($log['map'] ?? 'Unknown');
    $mapName = $mapNameRaw !== '' ? basename($mapNameRaw) : 'Unknown';
    $durationSeconds = (int)($log['duration'] ?? 0);
    $durationText = wt_format_playtime($durationSeconds);
    $startedAt = (int)($log['started_at'] ?? 0);
    ?>
    <div class="log-entry log-current" data-player-count="<?= $playerCountRaw ?>" data-started-at="<?= $startedAt ?>">
        <div class="log-summary">
            <span class="gamemode-label" title="<?= htmlspecialchars($gamemodeRaw ?? 'Unknown', ENT_QUOTES, 'UTF-8') ?>"><?= htmlspecialchars($badgeLabel, ENT_QUOTES, 'UTF-8') ?></span>
            <span class="log-title"><?= htmlspecialchars($mapName, ENT_QUOTES, 'UTF-8') ?> — <?= htmlspecialchars(wt_format_log_datetime($startedAt), ENT_QUOTES, 'UTF-8') ?> — <?= htmlspecialchars($durationText, ENT_QUOTES, 'UTF-8') ?></span>
            <span class="log-meta"><?= $playerCountRaw ?> player<?= $playerCountRaw === 1 ? '' : 's' ?></span>
        </div>
        <div class="log-body">
            <?php if (!empty($log['players']) && is_array($log['players'])): ?>
                <table class="stats-table log-table">
                    <thead>
                    <tr>
                        <th title="Player">Player</th>
                        <th title="Kills">K</th>
                        <th title="Deaths">D</th>
                        <th title="Kill/Death Ratio">K/D</th>
                        <th title="Accuracy">Acc.</th>
                        <th title="Damage">Dmg</th>
                        <th title="Damage Per Minute">D/M</th>
                        <th title="Damage Taken Per Minute">DT/M</th>
                        <th title="Airshots">AS</th>
                        <th title="Headshots">HS</th>
                        <th title="Backstabs">BS</th>
                        <th title="Healing">Healing</th>
                        <th title="Total Ubers">Ubers</th>
                        <th title="Time Played">Time</th>
                    </tr>
                    </thead>
                    <tbody>
                    <?php foreach ($log['players'] as $player):
                        $steamId = (string)($player['steamid'] ?? '');
                        $personaname = (string)($player['personaname'] ?? $steamId);
                        $avatar = trim((string)($player['avatar'] ?? '')) ?: WT_DEFAULT_AVATAR_URL;
                        $profileUrl = $player['profileurl'] ?? null;
                        $isAdmin = !empty($player['is_admin']);
                        $kills = (int)($player['kills'] ?? 0);
                        $deaths = (int)($player['deaths'] ?? 0);
                        $damage = (int)($player['damage'] ?? 0);
                        $damageTaken = (int)($player['damage_taken'] ?? 0);
                        $healing = (int)($player['healing'] ?? 0);
                        $headshots = (int)($player['headshots'] ?? 0);
                        $backstabs = (int)($player['backstabs'] ?? 0);
                        $totalUbers = (int)($player['total_ubers'] ?? 0);
                        $playtime = (int)($player['playtime'] ?? 0);
                        $airshots = (int)($player['airshots'] ?? 0);
                        $shots = (int)($player['shots'] ?? 0);
                        $hits = (int)($player['hits'] ?? 0);
                        $minutes = $playtime > 0 ? ($playtime / 60.0) : 0.0;
                        $kdValue = $deaths > 0 ? $kills / $deaths : $kills;
                        $dpm = $minutes > 0 ? ($damage / $minutes) : $damage;
                        $dtpm = $minutes > 0 ? ($damageTaken / $minutes) : $damageTaken;
                        $accuracy = $shots > 0 ? ($hits / max($shots, 1)) * 100.0 : null;
                        ?>
                        <tr>
                            <td class="player-cell">
                                <img class="player-avatar" src="<?= htmlspecialchars($avatar, ENT_QUOTES, 'UTF-8') ?>" alt="" onerror="this.onerror=null;this.src='<?= htmlspecialchars(WT_DEFAULT_AVATAR_URL, ENT_QUOTES, 'UTF-8') ?>'">
                                <div class="log-player-info">
                                    <?php if ($profileUrl): ?>
                                        <a href="<?= htmlspecialchars((string)$profileUrl, ENT_QUOTES, 'UTF-8') ?>" target="_blank" rel="noopener"<?= $isAdmin ? ' class="admin-name"' : '' ?>><?= htmlspecialchars($personaname, ENT_QUOTES, 'UTF-8') ?></a>
                                    <?php else: ?>
                                        <span<?= $isAdmin ? ' class="admin-name"' : '' ?>><?= htmlspecialchars($personaname, ENT_QUOTES, 'UTF-8') ?></span>
                                    <?php endif; ?>
                                </div>
                            </td>
                            <td><?= number_format($kills) ?></td>
                            <td><?= number_format($deaths) ?></td>
                            <td><?= number_format($kdValue, 2) ?></td>
                            <td><?= $accuracy !== null ? number_format($accuracy, 1) . '%' : '—' ?></td>
                            <td><?= number_format($damage) ?></td>
                            <td><?= number_format($dpm, 1) ?></td>
                            <td><?= number_format($dtpm, 1) ?></td>
                            <td><?= number_format($airshots) ?></td>
                            <td><?= number_format($headshots) ?></td>
                            <td><?= number_format($backstabs) ?></td>
                            <td><?= number_format($healing) ?></td>
                            <td><?= number_format($totalUbers) ?></td>
                            <td><?= wt_format_playtime($playtime) ?></td>
                        </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
            <?php else: ?>
                <div class="empty-state">No player data recorded for this match.</div>
            <?php endif; ?>
        </div>
    </div>
<?php else: ?>
    <div class="empty-state">No logs available.</div>
<?php endif; ?>
