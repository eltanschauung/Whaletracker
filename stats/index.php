<?php
require_once __DIR__ . '/includes/bootstrap.php';

$search = trim($_GET['q'] ?? '');
$focusedPlayer = $_GET['player'] ?? null;
$perPage = 50;
$page = max(1, (int)($_GET['page'] ?? 1));

$summaryCache = wt_get_cached_summary();
$summary = $summaryCache['summary'] ?? [];
$performanceAverages = $summaryCache['performanceAverages'] ?? [];
$summaryHtml = $summaryCache['html'] ?? '';

$defaultAvatarUrl = WT_DEFAULT_AVATAR_URL;

if ($focusedPlayer === null && wt_is_logged_in()) {
    $focusedPlayer = wt_current_user_id();
}

$focused = null;
if ($focusedPlayer !== null && $focusedPlayer !== '') {
    $focused = wt_fetch_player($focusedPlayer);
}

$pageTitle = 'Kogasatopia · WhaleTracker';
$activePage = 'cumulative';
$cumulativeRevision = wt_cumulative_revision();
$tabRevision = $cumulativeRevision ? substr(md5((string)$cumulativeRevision), 0, 6) : null;

include __DIR__ . '/templates/layout_top.php';

include __DIR__ . '/templates/tab-cumulative.php';
?>

<script>
const cumulativeFragmentEndpoint = '/stats/cumulative_fragment.php';

function attachSortingToTable(table) {
    if (!table || table.dataset.sortBound === '1') {
        return;
    }
    const tbody = table.querySelector('tbody');
    if (!tbody) {
        return;
    }
    const headers = table.querySelectorAll('th[data-key]');
    const sortState = { key: null, direction: 1 };
    headers.forEach(header => {
        header.addEventListener('click', () => {
            const key = header.dataset.key;
            const type = header.dataset.type || 'text';
            if (sortState.key === key) {
                sortState.direction *= -1;
            } else {
                sortState.key = key;
                sortState.direction = 1;
            }
            const rows = Array.from(tbody.querySelectorAll('tr'));
            rows.sort((a, b) => {
                let av = a.dataset[key] ?? '';
                let bv = b.dataset[key] ?? '';
                if (type === 'number') {
                    av = Number(av);
                    bv = Number(bv);
                }
                if (av < bv) return -1 * sortState.direction;
                if (av > bv) return 1 * sortState.direction;
                return 0;
            });
            rows.forEach(row => tbody.appendChild(row));
            headers.forEach(h => h.classList.remove('sorted-asc', 'sorted-desc'));
            header.classList.add(sortState.direction === 1 ? 'sorted-asc' : 'sorted-desc');
        });
    });
    table.dataset.sortBound = '1';
}

function initSorting() {
    document.querySelectorAll('.stats-table').forEach(table => attachSortingToTable(table));
}

let cumulativeLoading = false;
let cumulativeAbortController = null;

function cancelCumulativeRequest() {
    if (cumulativeAbortController) {
        try {
            cumulativeAbortController.abort();
        } catch (err) {
            console.warn('[WhaleTracker] Failed to abort cumulative request', err);
        }
        cumulativeAbortController = null;
    }
    cumulativeLoading = false;
    const container = document.getElementById('cumulative-fragment');
    if (container) {
        container.classList.remove('is-loading');
    }
}

function initCumulativeFragment() {
    const container = document.getElementById('cumulative-fragment');
    if (!container) {
        return;
    }
    container.addEventListener('click', event => {
        const link = event.target.closest('.table-pagination-button[href]');
        if (!link) {
            return;
        }
        if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || link.target === '_blank') {
            return;
        }
        event.preventDefault();
        loadCumulativePage(link.getAttribute('href'));
    });
    const initialUrl = container.dataset.initialUrl || window.location.href;
    if (initialUrl) {
        loadCumulativePage(initialUrl);
    }
}

function initTabNavigationCancel() {
    const navTriggers = document.querySelectorAll('.tab-button, .steam-login');
    if (!navTriggers.length) {
        return;
    }
    navTriggers.forEach(element => {
        element.addEventListener('click', () => {
            if (cumulativeLoading) {
                cancelCumulativeRequest();
            }
        });
    });
}

async function loadCumulativePage(targetUrl) {
    const container = document.getElementById('cumulative-fragment');
    if (!container || !targetUrl) {
        return;
    }
    cancelCumulativeRequest();
    cumulativeAbortController = new AbortController();
    cumulativeLoading = true;
    container.classList.add('is-loading');
    try {
        const linkUrl = new URL(targetUrl, window.location.href);
        const endpoint = container.dataset.fragment || cumulativeFragmentEndpoint;
        const fetchUrl = new URL(endpoint, window.location.href);
        const perPage = container.dataset.perPage || '50';
        const focusedPlayer = container.dataset.player || '';
        linkUrl.searchParams.forEach((value, key) => {
            if (value !== null) {
                fetchUrl.searchParams.set(key, value);
            }
        });
        if (!fetchUrl.searchParams.has('page')) {
            fetchUrl.searchParams.set('page', linkUrl.searchParams.get('page') || '1');
        }
        fetchUrl.searchParams.set('perPage', perPage);
        if (focusedPlayer && !fetchUrl.searchParams.has('player')) {
            fetchUrl.searchParams.set('player', focusedPlayer);
        }
        const response = await fetch(fetchUrl.toString(), {
            headers: { 'X-Requested-With': 'XMLHttpRequest' },
            cache: 'no-store',
            signal: cumulativeAbortController.signal,
        });
        if (!response.ok) {
            throw new Error('Failed to fetch cumulative fragment');
        }
        const payload = await response.json();
        if (!payload || payload.ok !== true) {
            throw new Error('Invalid fragment payload');
        }
        container.innerHTML = payload.html || '';
        if (typeof payload.page !== 'undefined') {
            container.dataset.page = String(payload.page);
        }
        if (typeof payload.totalPages !== 'undefined') {
            container.dataset.totalPages = String(payload.totalPages);
        }
        const cumulativeTable = container.querySelector('#stats-table-cumulative');
        if (cumulativeTable) {
            attachSortingToTable(cumulativeTable);
        }
        const finalUrl = linkUrl.pathname + linkUrl.search;
        if (window.history && window.history.replaceState) {
            window.history.replaceState({}, '', finalUrl);
        }
    } catch (err) {
        if (err.name === 'AbortError') {
            return;
        }
        console.error('[WhaleTracker] Failed to load cumulative page', err);
        window.location.href = targetUrl;
    } finally {
        if (cumulativeAbortController) {
            cumulativeAbortController = null;
        }
        cumulativeLoading = false;
        container.classList.remove('is-loading');
    }
}

document.addEventListener('DOMContentLoaded', () => {
    initSorting();
    initCumulativeFragment();
    initTabNavigationCancel();
});
</script>

<?php include __DIR__ . '/templates/layout_bottom.php'; ?>
