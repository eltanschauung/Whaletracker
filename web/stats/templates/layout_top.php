<?php
$pageTitle = $pageTitle ?? 'Kogasatopia · WhaleTracker';
$activePage = $activePage ?? 'cumulative';
$navOnlineCount = $navOnlineCount ?? 'Loading...';
$tabRevision = $tabRevision ?? null;
$tabRoutes = [
    ['key' => 'cumulative', 'desktop' => 'All Time Stats', 'mobile' => 'Stats', 'href' => '/stats/'],
    ['key' => 'online', 'desktop' => 'Online Now', 'mobile' => 'Online', 'href' => '/stats/online/'],
    ['key' => 'logs', 'desktop' => 'Match Logs', 'mobile' => 'Logs', 'href' => '/stats/logs/'],
    ['key' => 'chat', 'desktop' => 'Chat', 'mobile' => 'Chat', 'href' => '/stats/chat/'],
    ['key' => 'mapsdb', 'desktop' => 'MapsDB', 'mobile' => 'Maps', 'href' => '/mapsdb'],
];
?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title><?= htmlspecialchars($pageTitle, ENT_QUOTES, 'UTF-8') ?></title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Heebo:wght@400;500;600&display=swap">
    <link rel="stylesheet" href="/stats/css/whaletracker.css">
    <?php if (!empty($isMotdEmbed)): ?>
    <style>
        .header {
            display: none !important;
        }
        .page {
            padding-top: 1.5rem;
        }
    </style>
    <?php endif; ?>
</head>
<body<?= !empty($isMotdEmbed) ? ' class="motd-embed"' : '' ?>>
<div class="page">
    <header class="header">
        <div class="brand">
            <img src="/stats/assets/whaletracker_logo.png" style="width:50%" alt="WhaleTracker logo">
        </div>
        <div class="animation">
            <img src="/stats/assets/wholesome2.gif" alt="Wholesome">
        </div>
        <div class="header-actions">
            <?php if (WT_STEAM_API_KEY === ''): ?>
                <small class="muted">Set <code>STEAM_API_KEY</code> to enable avatars and names.</small>
            <?php endif; ?>
            <?php if (!empty($currentUserDisplay)): ?>
                <div class="header-user">
                    <img class="header-user-avatar" src="<?= htmlspecialchars($currentUserDisplay['avatar'], ENT_QUOTES, 'UTF-8') ?>" alt="">
                    <div class="header-user-meta">
                        <div class="header-user-name"><?= htmlspecialchars($currentUserDisplay['name'], ENT_QUOTES, 'UTF-8') ?></div>
                        <a class="steam-logout" href="/stats/steam_login.php?action=logout" title="Sign out of WhaleTracker">Sign out</a>
                    </div>
                </div>
            <?php else: ?>
                <a class="steam-login" href="/stats/steam_login.php?action=login">Sign in through Steam</a>
            <?php endif; ?>
        </div>
    </header>

    <div class="tabs">
        <div class="tab-controls">
            <?php foreach ($tabRoutes as $route): ?>
                <a class="tab-button <?= $activePage === $route['key'] ? 'active' : '' ?>" href="<?= htmlspecialchars($route['href'], ENT_QUOTES, 'UTF-8') ?>">
                    <span class="tab-button-label tab-button-label--desktop"><?= htmlspecialchars($route['desktop'], ENT_QUOTES, 'UTF-8') ?></span>
                    <span class="tab-button-label tab-button-label--mobile"><?= htmlspecialchars($route['mobile'], ENT_QUOTES, 'UTF-8') ?></span>
                    <?php if ($route['key'] === 'online'): ?>
                        <span class="tab-button-count" id="nav-online-count" aria-live="polite"><?= htmlspecialchars($navOnlineCount, ENT_QUOTES, 'UTF-8') ?></span>
                    <?php elseif ($route['key'] === 'chat'): ?>
                        <span class="tab-button-count" id="nav-chat-label" aria-live="polite">Last msg. --</span>
                    <?php endif; ?>
                </a>
            <?php endforeach; ?>
            <?php if (!empty($tabRevision)): ?>
                <span class="tab-hash" title="Build Hash">#<?= htmlspecialchars($tabRevision, ENT_QUOTES, 'UTF-8') ?></span>
            <?php endif; ?>
        </div>
