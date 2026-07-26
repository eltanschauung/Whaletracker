#define WT_MIN_ONLINE_UPDATE_INTERVAL 1.0
#define WT_DEFAULT_ONLINE_UPDATE_INTERVAL "10.0"
#define WT_MAX_ONLINE_UPDATE_INTERVAL 300.0
#define WT_INITIAL_RECONNECT_DELAY 1.0
#define WT_RUNTIME_QUICK_RECONNECT_DELAY 2.0

public Plugin myinfo =
{
    name = "WhaleTracker",
    author = "Hombre",
    description = "Cumulative player stats system",
    version = "1.0.3",
    url = "https://kogasa.tf"
};

public Database GetSyncDatabaseHandle()
{
    return g_hSyncDatabase;
}

public DBResultSet SQLQuerySync(const char[] query)
{
    Database db = GetSyncDatabaseHandle();
    if (db == null)
    {
        return null;
    }

    return SQL_Query(db, query);
}

public bool SQLFastQuerySync(const char[] query)
{
    Database db = GetSyncDatabaseHandle();
    if (db == null)
    {
        return false;
    }

    return SQL_FastQuery(db, query);
}

public void GetSyncDatabaseError(char[] error, int maxlen)
{
    Database db = GetSyncDatabaseHandle();
    if (db == null)
    {
        strcopy(error, maxlen, "No sync database handle");
        return;
    }

    SQL_GetError(db, error, maxlen);
}

float WhaleTracker_GetOnlineUpdateInterval()
{
    float interval = StringToFloat(WT_DEFAULT_ONLINE_UPDATE_INTERVAL);
    if (g_hOnlineUpdateInterval != null)
    {
        interval = GetConVarFloat(g_hOnlineUpdateInterval);
    }
    if (interval < WT_MIN_ONLINE_UPDATE_INTERVAL)
    {
        interval = WT_MIN_ONLINE_UPDATE_INTERVAL;
    }
    return interval;
}

void WhaleTracker_RestartOnlineTimer()
{
    if (g_hOnlineTimer != null)
    {
        CloseHandle(g_hOnlineTimer);
        g_hOnlineTimer = null;
    }

    if (g_bShuttingDown)
    {
        return;
    }

    g_hOnlineTimer = CreateTimer(WhaleTracker_GetOnlineUpdateInterval(), Timer_UpdateOnlineStats, _, TIMER_REPEAT);
}

public void ConVarChanged_OnlineUpdateInterval(ConVar convar, const char[] oldValue, const char[] newValue)
{
    WhaleTracker_RestartOnlineTimer();
}

public void OnPluginStart()
{
    LoadTranslations("common.phrases");
    if (g_SaveQueue != null)
    {
        delete g_SaveQueue;
    }
    g_SaveQueue = new ArrayList();
    g_PendingSaveQueries = 0;
    g_bShuttingDown = false;
    g_hReconnectTimer = null;
    g_hSavePumpTimer = null;
    WhaleTracker_ResetJoinLeaderboardCache();

    g_CvarDatabase = CreateConVar("sm_whaletracker_database", DB_CONFIG_DEFAULT, "Databases.cfg entry to use for WhaleTracker");
    g_CvarDatabase.GetString(g_sDatabaseConfig, sizeof(g_sDatabaseConfig));
    g_hGameName = CreateConVar("sm_whaletracker_game", "TF2", "Game label stored in WhaleTracker server snapshots.");
    g_hGameUrl = CreateConVar("sm_whaletracker_game_url", "440", "Steam store app ID used for WhaleTracker server snapshots.");
    g_hOnlineUpdateInterval = CreateConVar(
        "sm_whaletracker_online_update_interval",
        WT_DEFAULT_ONLINE_UPDATE_INTERVAL,
        "Seconds between whaletracker_online and whaletracker_servers updates.",
        FCVAR_NONE,
        true,
        WT_MIN_ONLINE_UPDATE_INTERVAL,
        true,
        WT_MAX_ONLINE_UPDATE_INTERVAL
    );
    g_hOnlineUpdateInterval.AddChangeHook(ConVarChanged_OnlineUpdateInterval);

    g_hEnableMatchLogs = CreateConVar(
        "sm_whaletracker_enable_matchlogs",
        "1",
        "Enable match logs table writes (1 = enabled, 0 = disabled).",
        FCVAR_NONE,
        true,
        0.0,
        true,
        1.0
    );
    g_hDeferredSavePump = CreateConVar(
        "sm_whaletracker_deferred_save_pump",
        "1",
        "Use timer-deferred save queue pumping (1 = deferred, 0 = immediate).",
        FCVAR_NONE,
        true,
        0.0,
        true,
        1.0
    );
    g_hMultikillWindow = CreateConVar(
        "sm_multikill_window",
        "3.0",
        "Seconds allowed for double/triple/quadra/penta kill tracking.",
        FCVAR_NOTIFY,
        true,
        0.1
    );
    g_hBonusDefaultDelay = CreateConVar(
        "sm_whaletracker_bonus_default_delay",
        "3.0",
        "Seconds to delay gameplay currency awards by default.",
        FCVAR_NONE,
        true,
        0.0
    );
    g_hRankMinKdSum = CreateConVar(
        "sm_whaletracker_rank_min_kd_sum",
        "200",
        "Minimum lifetime kills plus deaths required to appear ranked.",
        FCVAR_NONE,
        true,
        0.0
    );
    g_hRankMinPlaytimeSeconds = CreateConVar(
        "sm_whaletracker_rank_min_playtime_seconds",
        "10800",
        "Minimum lifetime playtime in seconds required to appear ranked.",
        FCVAR_NONE,
        true,
        0.0
    );
    g_hKillstreakBonusInterval = CreateConVar(
        "sm_whaletracker_killstreak_bonus_interval",
        "5",
        "Killstreak interval used for WhaleTracker killstreak forwards and awards.",
        FCVAR_NONE,
        true,
        1.0
    );
    g_hSyncKillConfirmWindow = CreateConVar(
        "sm_whaletracker_sync_kill_confirm_window",
        "0.25",
        "Seconds after a sync kill candidate to confirm the kill.",
        FCVAR_NONE,
        true,
        0.0
    );
    g_hTopScoreMinPlayers = CreateConVar(
        "sm_whaletracker_top_score_min_players",
        "10",
        "Minimum real players required for top-scoring player kill awards.",
        FCVAR_NONE,
        true,
        0.0
    );
    g_hTopScorePerMapLimit = CreateConVar(
        "sm_whaletracker_top_score_per_map_limit",
        "15",
        "Per-map award cap for top-scoring player kills; 0 disables the cap.",
        FCVAR_NONE,
        true,
        0.0
    );
    g_hDamageTrackingGate = CreateConVar(
        "sm_whaletracker_damage_tracking_gate",
        "200",
        "Damage threshold before a client is considered track-eligible.",
        FCVAR_NONE,
        true,
        0.0
    );
    g_hDamageSanityMax = CreateConVar(
        "sm_whaletracker_damage_sanity_max",
        "500",
        "Maximum single damage event accepted for WhaleTracker damage stats.",
        FCVAR_NONE,
        true,
        0.0
    );
    g_hMinMatchRateMinutes = CreateConVar(
        "sm_whaletracker_min_match_rate_minutes",
        "1.0",
        "Minimum match playtime minutes before rate stats like damage per minute are shown.",
        FCVAR_NONE,
        true,
        0.0
    );
    g_hLogMatchKillstreaks = CreateConVar(
        "sm_whaletracker_log_match_killstreaks",
        "1",
        "Record match-log best killstreak values for frontend weekly killstreak stats.",
        FCVAR_NONE,
        true,
        0.0,
        true,
        1.0
    );
    g_hAirshotMinHeight = CreateConVar(
        "sm_whaletracker_airshot_min_height",
        "100.0",
        "Minimum height above ground required for airshot tracking.",
        FCVAR_NONE,
        true,
        0.0
    );
    g_hAirborneBackstabMinHeight = CreateConVar(
        "sm_whaletracker_airborne_backstab_min_height",
        "100.0",
        "Minimum attacker height above ground required for an airborne backstab gem.",
        FCVAR_NONE,
        true,
        0.0
    );
    g_hDemoSyncWindow = CreateConVar(
        "sm_whaletracker_demo_sync_window",
        "0.5",
        "Seconds between sticky damage and grenade direct kill for demo sync awards.",
        FCVAR_NONE,
        true,
        0.0
    );
    g_hSoldierSyncWindow = CreateConVar(
        "sm_whaletracker_soldier_sync_window",
        "1.0",
        "Seconds between rocket damage and rocket kill for soldier sync awards.",
        FCVAR_NONE,
        true,
        0.0
    );
    g_hDemoSyncPerMap = CreateConVar(
        "sm_whaletracker_demo_sync_per_map",
        "0",
        "Per-map award cap for demo sync kills; 0 disables the cap.",
        FCVAR_NONE,
        true,
        0.0
    );
    g_hSoldierSyncPerMap = CreateConVar(
        "sm_whaletracker_soldier_sync_per_map",
        "0",
        "Per-map award cap for soldier sync kills; 0 disables the cap.",
        FCVAR_NONE,
        true,
        0.0
    );
    g_hHitscanAccuracyHitDebounce = CreateConVar(
        "sm_whaletracker_hitscan_accuracy_hit_debounce",
        "0.05",
        "Seconds to debounce hitscan accuracy hit tracking.",
        FCVAR_NONE,
        true,
        0.0
    );
    g_hMarketGardenKillWindow = CreateConVar(
        "sm_whaletracker_market_garden_kill_window",
        "0.25",
        "Seconds after a market garden hit to confirm a market garden kill.",
        FCVAR_NONE,
        true,
        0.0
    );
    g_hPeriodicSaveInterval = CreateConVar(
        "sm_whaletracker_periodic_save_interval",
        "30.0",
        "Seconds between periodic WhaleTracker save passes.",
        FCVAR_NONE,
        true,
        1.0
    );

    AutoExecConfig(true, "whaletracker");

    if (g_hVisibleMaxPlayers == null)
    {
        g_hVisibleMaxPlayers = FindConVar("sv_visiblemaxplayers");
    }

    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("player_healed", Event_PlayerHealed, EventHookMode_Post);
    HookEvent("player_chargedeployed", Event_UberDeployed, EventHookMode_Post);
    HookEvent("rocket_jump", Event_ExplosiveJump, EventHookMode_Pre);
    HookEvent("sticky_jump", Event_ExplosiveJump, EventHookMode_Pre);
    HookEvent("rocket_jump_landed", Event_ExplosiveJumpLanded, EventHookMode_Pre);
    HookEvent("sticky_jump_landed", Event_ExplosiveJumpLanded, EventHookMode_Pre);
    HookEvent("teamplay_round_win", Event_RoundWin, EventHookMode_PostNoCopy);
    HookEvent("teamplay_round_start", Event_ResetMultikillAll, EventHookMode_PostNoCopy);

    RegConsoleCmd("sm_whalestats", Command_ShowStats, "Show your Whale Tracker statistics.");
    RegConsoleCmd("sm_stats", Command_ShowStats, "Show your Whale Tracker statistics.");
    RegConsoleCmd("sm_points", Command_ShowPoints, "Show your WhalePoints total.");
    RegConsoleCmd("sm_pos", Command_ShowPoints, "Show your WhalePoints total.");
    RegConsoleCmd("sm_pts", Command_ShowPoints, "Show your WhalePoints total.");
    RegConsoleCmd("sm_ptsme", Command_ShowPointsMe, "Show your WhalePoints only to yourself.");
    RegConsoleCmd("sm_rank", Command_ShowPoints, "Show your WhalePoints total.");
    RegConsoleCmd("sm_ps", Command_ShowPoints, "Show your WhalePoints total.");
    RegConsoleCmd("sm_calc", Command_ShowPointsCalculation, "Show how WhalePoints are calculated.");
    RegConsoleCmd("sm_seen", Command_ShowLastSeen, "Search cached names and show a player's last seen time.");
    RegConsoleCmd("sm_fav", Command_SetFavoriteClass, "Set your favorite class for WhaleTracker.");
    RegConsoleCmd("sm_favorite", Command_SetFavoriteClass, "Set your favorite class for WhaleTracker.");
    RegConsoleCmd("sm_country", Command_ToggleCountryVisibility, "Toggle country flag visibility on kogasa.tf/stats.");
    RegConsoleCmd("sm_markets", Command_ShowMarketGardens, "Show your market garden total.");
    RegConsoleCmd("sm_mg", Command_ShowMarketGardens, "Show your market garden total.");
    RegConsoleCmd("sm_gardens", Command_ShowMarketGardens, "Show your market garden total.");
    RegConsoleCmd("sm_as", Command_ShowMarketGardens, "Show your market garden total.");
    RegConsoleCmd("sm_airshots", Command_ShowMarketGardens, "Show your market garden total.");
    RegConsoleCmd("sm_ranks", Command_ShowLeaderboard, "Show WhaleTracker leaderboard page.");
    RegAdminCmd("sm_savestats", Command_SaveAllStats, ADMFLAG_GENERIC, "Manually save all WhaleTracker stats");
    RegAdminCmd("sm_whaletracker_historical", Command_RecordHistoricalSnapshot, ADMFLAG_GENERIC, "Record a ranked-client historical snapshot.");
    WhaleTracker_InitMotdCommands();

    EnsureMatchStorage();

    if (GetClientCount(true) > 0 && !g_sCurrentLogId[0])
    {
        BeginMatchTracking();
    }

    RefreshCurrentOnlineMapName();
    RefreshHostAddress();
    RefreshServerFlags();
    WhaleTracker_RustInit();

    WhaleTracker_SQLConnect();

    WhaleTracker_RestartOnlineTimer();
    if (g_hPeriodicSaveTimer != null)
    {
        CloseHandle(g_hPeriodicSaveTimer);
    }
    g_hPeriodicSaveTimer = CreateTimer(WT_GetPeriodicSaveInterval(), Timer_GlobalSave, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

    g_hAirshotForward = CreateGlobalForward("WhaleTracker_OnAirshot", ET_Ignore, Param_Cell, Param_Cell);
    g_hProjectileDirectHitForward = CreateGlobalForward("WhaleTracker_OnProjectileDirectHit", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_hMedicDropForward = CreateGlobalForward("WhaleTracker_OnMedicDrop", ET_Ignore, Param_Cell, Param_Cell);
    g_hKillstreakForward = CreateGlobalForward("WhaleTracker_OnKillstreak", ET_Ignore, Param_Cell, Param_Cell);
    g_hKillstreakEndForward = CreateGlobalForward("WhaleTracker_OnKillstreakEnd", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_hMultikillForward = CreateGlobalForward("WhaleTracker_OnMultikill", ET_Ignore, Param_Cell, Param_Cell);

    for (int i = 1; i <= MaxClients; i++)
    {
        ResetAllStats(i);
        ResetMapStats(i);
        g_KillSaveCounter[i] = 0;
        g_bStatsDirty[i] = false;
        if (IsClientInGame(i))
        {
            OnClientPutInServer(i);
            RequestClientStateLoads(i);
        }
    }
}

public void OnMapStart()
{
    if (!WhaleTracker_IsDatabaseHealthy())
    {
        WhaleTracker_ScheduleReconnect(WT_INITIAL_RECONNECT_DELAY);
    }

    FinalizeCurrentMatch(false);
    if (GetClientCount(true) > 1)
    {
        BeginMatchTracking();
    }
    RefreshCurrentOnlineMapName();
    RefreshHostAddress();
    ClearOnlineStats();
    ResetMultikillAll();
    for (int i = 1; i <= MaxClients; i++)
    {
        ResetMapStats(i);
        if (IsClientInGame(i))
        {
            ResetClientCommandCaches(i);
            g_MapStats[i].connectTime = GetEngineTime();
        }
        g_KillSaveCounter[i] = 0;
    }
}

public void OnMapEnd()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i) && !IsFakeClient(i))
        {
            SaveClientStats(i, false, true, true);
        }
    }

    FlushSaveQueueSync();
    FinalizeCurrentMatch(false);
    WhaleTracker_RustFlushSqlBatch();
}

public void OnPluginEnd()
{
    if (g_bDatabaseReady && g_hDatabase != null)
    {
        RefreshCurrentOnlineMapName();
        RefreshHostAddress();
        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsValidClient(i) || IsFakeClient(i))
            {
                continue;
            }

            SaveClientStats(i, false, true, true);
        }

        int now = GetTime();
        float engineNow = GetEngineTime();
        int playerCount = GetClientCount(false);
        int visibleMax = GetMaxHumanPlayers();
        if (g_hVisibleMaxPlayers != null)
        {
            int conVarValue = GetConVarInt(g_hVisibleMaxPlayers);
            if (conVarValue > 0 && visibleMax > conVarValue)
            {
                visibleMax = conVarValue;
            }
        }

        char escapedMapName[256];
        char mapName[128];
        if (g_sOnlineMapName[0])
        {
            strcopy(mapName, sizeof(mapName), g_sOnlineMapName);
        }
        else
        {
            strcopy(mapName, sizeof(mapName), "unknown");
        }
        SQL_EscapeString(g_hDatabase, mapName, escapedMapName, sizeof(escapedMapName));

        char escapedHostIp[64];
        char hostIp[64];
        if (g_sPublicHostIp[0])
        {
            strcopy(hostIp, sizeof(hostIp), g_sPublicHostIp);
        }
        else if (g_sHostIp[0])
        {
            strcopy(hostIp, sizeof(hostIp), g_sHostIp);
        }
        else
        {
            strcopy(hostIp, sizeof(hostIp), "0.0.0.0");
        }
        SQL_EscapeString(g_hDatabase, hostIp, escapedHostIp, sizeof(escapedHostIp));

        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsValidClient(i) || IsFakeClient(i))
            {
                continue;
            }

            QueueClientOnlineSnapshot(i, now, engineNow, playerCount, visibleMax, escapedMapName, escapedHostIp, true);
        }
    }

    FinalizeCurrentMatch(true);

    FlushSaveQueueSync();
    WhaleTracker_RustShutdown();
    g_bShuttingDown = true;

    // These timers are plugin-owned and will be cleaned up on unload. Avoid
    // closing them here because mapchange/no-mapchange timers can already be
    // invalid by the time OnPluginEnd runs.
    g_hOnlineTimer = null;
    g_hPeriodicSaveTimer = null;
    g_hReconnectTimer = null;
    g_hSchemaRetryTimer = null;
    g_hSavePumpTimer = null;

    if (g_hAirshotForward != null)
    {
        delete g_hAirshotForward;
        g_hAirshotForward = null;
    }

    if (g_hProjectileDirectHitForward != null)
    {
        delete g_hProjectileDirectHitForward;
        g_hProjectileDirectHitForward = null;
    }

    if (g_hMedicDropForward != null)
    {
        delete g_hMedicDropForward;
        g_hMedicDropForward = null;
    }

    if (g_hKillstreakForward != null)
    {
        delete g_hKillstreakForward;
        g_hKillstreakForward = null;
    }

    if (g_hKillstreakEndForward != null)
    {
        delete g_hKillstreakEndForward;
        g_hKillstreakEndForward = null;
    }

    if (g_hMultikillForward != null)
    {
        delete g_hMultikillForward;
        g_hMultikillForward = null;
    }

    if (g_SaveQueue != null)
    {
        delete g_SaveQueue;
        g_SaveQueue = null;
    }

    if (g_hDatabase != null)
    {
        delete g_hDatabase;
        g_hDatabase = null;
    }

    if (g_hSyncDatabase != null)
    {
        delete g_hSyncDatabase;
        g_hSyncDatabase = null;
    }

    g_bDatabaseReady = false;
    g_bAsyncDatabaseConnected = false;
    g_bSyncDatabaseConnected = false;
    g_bDatabaseConnectInFlight = false;
    g_bSchemaReady = false;
    g_bSchemaCheckInFlight = false;
    g_hVisibleMaxPlayers = null;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            SDKUnhook(i, SDKHook_OnTakeDamage, OnTakeDamage);
        }
    }
}

public void OnClientPutInServer(int client)
{
    if (IsFakeClient(client))
    {
        SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
        return;
    }

    if (GetClientCount(true) == 1 && !g_sCurrentLogId[0])
    {
        BeginMatchTracking();
    }

    ResetRuntimeStats(client);
    ResetClientCommandCaches(client);
    g_Stats[client].connectTime = GetEngineTime();
    g_MapStats[client].connectTime = GetEngineTime();
    g_KillSaveCounter[client] = 0;
    g_bStatsDirty[client] = false;

    ResetMapStats(client);
    EnsureMatchStorage();
    EnsureClientSteamId(client);

    char steamId[STEAMID64_LEN];
    strcopy(steamId, sizeof(steamId), g_MapStats[client].steamId);

    if (steamId[0])
    {
        int snapshot[MATCH_STAT_COUNT];
        if (ExtractSnapshotForSteamId(steamId, snapshot))
        {
            ApplySnapshotToStats(g_MapStats[client], snapshot);
            RemoveSnapshotForSteamId(steamId);
        }

        char name[MAX_NAME_LENGTH];
        ResolveMatchPlayerName(client, steamId, name, sizeof(name));
        RememberMatchPlayerName(steamId, name);
    }

    if (IsValidClient(client) && IsClientInGame(client))
    {
        SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    }
    TouchClientLastSeen(client);

    RequestClientStateLoads(client);
    WhaleTracker_RefreshClientTrackingState(client);
    g_iDamageGate[client] = 0;
}

public void OnClientCookiesCached(int client)
{
    if (IsFakeClient(client))
        return;

    RequestClientStateLoads(client);
    TouchClientLastSeen(client);
}

public void OnClientDisconnect(int client)
{
    ResetMultikillClient(client);

    if (IsFakeClient(client))
    {
        SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
        return;
    }

    bool lastHuman = !WhaleTracker_HasHumanClientsExcept(client);

    if (IsClientInGame(client))
    {
        UpdateRoundTopScoringPlayerCandidate(client);
        SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    }

    SaveClientStats(client, true, true);
    CacheWhalePointsOnDisconnect(client);
    RemoveOnlineStats(client);
    ResetAllStats(client);
    ResetClientCommandCaches(client);
    g_KillSaveCounter[client] = 0;
    g_bTrackEligible[client] = false;
    g_iDamageGate[client] = 0;

    if (lastHuman)
    {
        FinalizeCurrentMatch(false);
    }

}

public void OnClientAuthorized(int client, const char[] auth)
{
    if (!IsValidClient(client) || IsFakeClient(client))
        return;

    EnsureClientSteamId(client);
    if (g_Stats[client].steamId[0] != '\0')
    {
        return;
    }

    if (!auth[0])
    {
        return;
    }

    // Fallback only; EnsureClientSteamId() will overwrite with SteamID64 when available.
    strcopy(g_Stats[client].steamId, sizeof(g_Stats[client].steamId), auth);
    strcopy(g_MapStats[client].steamId, sizeof(g_MapStats[client].steamId), auth);
}

public void OnClientPostAdminCheck(int client)
{
    if (!IsValidClient(client))
        return;

    if (IsFakeClient(client))
    {
        return;
    }

    WhaleTracker_UpdateClientAdminStatus(client);
    if (!WhaleTracker_ConsumePrefetchedJoinLeaderboard(client))
    {
        RequestClientJoinLeaderboardQuery(client);
    }
    RequestFavoriteClassLoad(client);
    RequestShowCountryLoad(client);
}

public bool OnClientPreConnectEx(const char[] name, char password[255], const char[] ip, const char[] steamID, char rejectReason[255])
{
    if (!g_bDatabaseReady || g_hDatabase == null)
    {
        return true;
    }

    char steamId64[STEAMID64_LEN];
    if (!WhaleTracker_NormalizeSteamId64(steamID, steamId64, sizeof(steamId64)))
    {
        return true;
    }

    int unused;
    if (g_JoinLeaderboardPending.GetValue(steamId64, unused)
        || g_JoinLeaderboardRanks.GetValue(steamId64, unused))
    {
        return true;
    }

    g_JoinLeaderboardPending.SetValue(steamId64, 1);

    DataPack pack = new DataPack();
    pack.WriteString(steamId64);

    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT points, rank FROM whaletracker_points_cache WHERE steamid = '%s' LIMIT 1",
        steamId64);
    g_hDatabase.Query(WhaleTracker_PreConnectLeaderboardQueryCallback, query, pack);
    return true;
}

public void WhaleTracker_PreConnectLeaderboardQueryCallback(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    char steamId64[STEAMID64_LEN];
    pack.ReadString(steamId64, sizeof(steamId64));
    delete pack;

    g_JoinLeaderboardPending.Remove(steamId64);

    if (error[0] != '\0')
    {
        LogError("[WhaleTracker] Failed to prefetch points cache for join message: %s", error);
        if (WhaleTracker_IsConnectionLostError(error))
        {
            WhaleTracker_ScheduleReconnect(WT_RUNTIME_QUICK_RECONNECT_DELAY);
        }
        return;
    }

    if (results == null || !results.FetchRow())
    {
        return;
    }

    int points = results.FetchInt(0);
    int rank = results.FetchInt(1);
    g_JoinLeaderboardPoints.SetValue(steamId64, points > 0 ? points : 0);
    g_JoinLeaderboardRanks.SetValue(steamId64, rank > 0 ? rank : 0);

    int client = WhaleTracker_FindClientBySteamId64(steamId64);
    if (client > 0)
    {
        WhaleTracker_ConsumePrefetchedJoinLeaderboard(client);
        return;
    }

    DataPack expiryPack = new DataPack();
    expiryPack.WriteString(steamId64);
    CreateTimer(30.0, Timer_ExpireJoinLeaderboardPrefetch, expiryPack, TIMER_DATA_HNDL_CLOSE | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ExpireJoinLeaderboardPrefetch(Handle timer, DataPack pack)
{
    pack.Reset();
    char steamId64[STEAMID64_LEN];
    pack.ReadString(steamId64, sizeof(steamId64));
    g_JoinLeaderboardPoints.Remove(steamId64);
    g_JoinLeaderboardRanks.Remove(steamId64);
    return Plugin_Stop;
}

void WhaleTracker_ResetJoinLeaderboardCache()
{
    delete g_JoinLeaderboardPending;
    delete g_JoinLeaderboardPoints;
    delete g_JoinLeaderboardRanks;
    g_JoinLeaderboardPending = new StringMap();
    g_JoinLeaderboardPoints = new StringMap();
    g_JoinLeaderboardRanks = new StringMap();
}

bool WhaleTracker_ConsumePrefetchedJoinLeaderboard(int client)
{
    if (!IsValidClient(client) || !IsClientInGame(client) || IsFakeClient(client))
    {
        return false;
    }

    EnsureClientSteamId(client);
    char steamId64[STEAMID64_LEN];
    strcopy(steamId64, sizeof(steamId64), g_Stats[client].steamId);
    if (!steamId64[0])
    {
        return false;
    }

    int points;
    int rank;
    if (g_JoinLeaderboardPoints.GetValue(steamId64, points)
        && g_JoinLeaderboardRanks.GetValue(steamId64, rank))
    {
        g_JoinLeaderboardPoints.Remove(steamId64);
        g_JoinLeaderboardRanks.Remove(steamId64);
        WhaleTracker_PrintJoinLeaderboardMessage(client, points, rank);
        return true;
    }

    int unused;
    return g_JoinLeaderboardPending.GetValue(steamId64, unused);
}

int WhaleTracker_FindClientBySteamId64(const char[] steamId64)
{
    char currentSteamId[STEAMID64_LEN];
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client)
            || !GetClientAuthId(client, AuthId_SteamID64, currentSteamId, sizeof(currentSteamId)))
        {
            continue;
        }

        if (StrEqual(currentSteamId, steamId64))
        {
            return client;
        }
    }
    return 0;
}

void RequestClientJoinLeaderboardQuery(int client)
{
    if (!IsValidClient(client) || !IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    if (!g_bDatabaseReady || g_hDatabase == null)
    {
        return;
    }

    EnsureClientSteamId(client);
    if (g_Stats[client].steamId[0] == '\0')
    {
        return;
    }

    char escapedSteamId[STEAMID64_LEN * 2];
    EscapeSqlString(g_Stats[client].steamId, escapedSteamId, sizeof(escapedSteamId));

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));

    char query[512];
    Format(query, sizeof(query),
        "SELECT points, rank FROM whaletracker_points_cache WHERE steamid = '%s' LIMIT 1",
        escapedSteamId);
    g_hDatabase.Query(WhaleTracker_JoinLeaderboardQueryCallback, query, pack);
}

public void WhaleTracker_JoinLeaderboardQueryCallback(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    delete pack;

    if (!IsValidClient(client) || !IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    if (error[0] != '\0')
    {
        LogError("[WhaleTracker] Failed to query points cache for join message: %s", error);
        if (WhaleTracker_IsConnectionLostError(error))
        {
            WhaleTracker_ScheduleReconnect(WT_RUNTIME_QUICK_RECONNECT_DELAY);
        }
        return;
    }

    int points = 0;
    int rank = 0;

    if (results == null || !results.FetchRow())
    {
        return;
    }

    points = results.FetchInt(0);
    rank = results.FetchInt(1);
    if (points < 0)
    {
        points = 0;
    }
    if (rank < 0)
    {
        rank = 0;
    }

    WhaleTracker_PrintJoinLeaderboardMessage(client, points, rank);
}

void WhaleTracker_PrintJoinLeaderboardMessage(int client, int points, int rank)
{
    char displayName[128];
    if (GetFeatureStatus(FeatureType_Native, "Filters_GetChatName") == FeatureStatus_Available
        && Filters_GetChatName(client, displayName, sizeof(displayName)) && displayName[0] != '\0')
    {
        TrimString(displayName);

        if (StrContains(displayName, "{teamcolor}", false) == 0)
        {
            ReplaceString(displayName, sizeof(displayName), "{teamcolor}", "{gold}", false);
        }
    }
    else
    {
        char rawName[MAX_NAME_LENGTH];
        GetClientName(client, rawName, sizeof(rawName));
        FormatEx(displayName, sizeof(displayName), "{gold}%s", rawName);
    }

    if (rank > 0)
    {
        CPrintToChatAll("%s{default} (%d Points, Rank #%d) joined the game", displayName, points, rank);
        PrintToServer("[WhaleTracker] %s (%d Points, Rank #%d) joined the game", displayName, points, rank);
    }
    else
    {
        CPrintToChatAll("%s{default} (Unranked) joined the game", displayName);
        PrintToServer("[WhaleTracker] %s (Unranked) joined the game", displayName);
    }
}
