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
    float interval = 10.0;
    if (g_hOnlineUpdateInterval != null)
    {
        interval = GetConVarFloat(g_hOnlineUpdateInterval);
    }
    if (interval < 1.0)
    {
        interval = 1.0;
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
    if (g_MapMvpHistory == null)
    {
        g_MapMvpHistory = new StringMap();
    }
    else
    {
        g_MapMvpHistory.Clear();
    }
    g_PendingSaveQueries = 0;
    g_bShuttingDown = false;
    g_hReconnectTimer = null;
    g_hSavePumpTimer = null;

    g_CvarDatabase = CreateConVar("sm_whaletracker_database", DB_CONFIG_DEFAULT, "Databases.cfg entry to use for WhaleTracker");
    g_CvarDatabase.GetString(g_sDatabaseConfig, sizeof(g_sDatabaseConfig));
    g_hGameName = CreateConVar("sm_whaletracker_game", "TF2", "Game label stored in WhaleTracker server snapshots.");
    g_hGameUrl = CreateConVar("sm_whaletracker_game_url", "440", "Steam store app ID used for WhaleTracker server snapshots.");
    g_hOnlineUpdateInterval = CreateConVar(
        "sm_whaletracker_online_update_interval",
        "10.0",
        "Seconds between whaletracker_online and whaletracker_servers updates.",
        FCVAR_NONE,
        true,
        1.0,
        true,
        300.0
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
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);

    RegConsoleCmd("sm_whalestats", Command_ShowStats, "Show your Whale Tracker statistics.");
    RegConsoleCmd("sm_stats", Command_ShowStats, "Show your Whale Tracker statistics.");
    RegConsoleCmd("sm_points", Command_ShowPoints, "Show your WhalePoints total.");
    RegConsoleCmd("sm_pos", Command_ShowPoints, "Show your WhalePoints total.");
    RegConsoleCmd("sm_pts", Command_ShowPoints, "Show your WhalePoints total.");
    RegConsoleCmd("sm_ptsme", Command_ShowPointsMe, "Show your WhalePoints only to yourself.");
    RegConsoleCmd("sm_rank", Command_ShowPoints, "Show your WhalePoints total.");
    RegConsoleCmd("sm_ps", Command_ShowPoints, "Show your WhalePoints total.");
    RegConsoleCmd("sm_calc", Command_ShowPointsCalculation, "Show how WhalePoints are calculated.");
    RegConsoleCmd("sm_mvp", Command_ShowMvps, "Show current and last-round MVPs.");
    RegConsoleCmd("sm_seen", Command_ShowLastSeen, "Search cached names and show a player's last seen time.");
    RegConsoleCmd("sm_fav", Command_SetFavoriteClass, "Set your favorite class for WhaleTracker.");
    RegConsoleCmd("sm_favorite", Command_SetFavoriteClass, "Set your favorite class for WhaleTracker.");
    RegConsoleCmd("sm_markets", Command_ShowMarketGardens, "Show your market garden total.");
    RegConsoleCmd("sm_mg", Command_ShowMarketGardens, "Show your market garden total.");
    RegConsoleCmd("sm_gardens", Command_ShowMarketGardens, "Show your market garden total.");
    RegConsoleCmd("sm_as", Command_ShowMarketGardens, "Show your market garden total.");
    RegConsoleCmd("sm_airshots", Command_ShowMarketGardens, "Show your market garden total.");
    RegConsoleCmd("sm_bonus", Command_ShowBonusPoints, "Show your total Bonus Points.");
    RegConsoleCmd("sm_bonuspoints", Command_ShowBonusPoints, "Show your total Bonus Points.");
    RegConsoleCmd("sm_bp", Command_ShowBonusPoints, "Show your total Bonus Points.");
    RegConsoleCmd("sm_sendbp", Command_SendBonusPoints, "Send Bonus Points to another player.");
    RegConsoleCmd("sm_bpsend", Command_SendBonusPoints, "Send Bonus Points to another player.");
    RegConsoleCmd("sm_ranks", Command_ShowLeaderboard, "Show WhaleTracker leaderboard page.");
    RegAdminCmd("sm_savestats", Command_SaveAllStats, ADMFLAG_GENERIC, "Manually save all WhaleTracker stats");
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
    g_hPeriodicSaveTimer = CreateTimer(30.0, Timer_GlobalSave, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

    g_hAirshotForward = CreateGlobalForward("WhaleTracker_OnAirshot", ET_Ignore, Param_Cell, Param_Cell);

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
        WhaleTracker_ScheduleReconnect(1.0);
    }

    FinalizeCurrentMatch(false);
    if (GetClientCount(true) > 1)
    {
        BeginMatchTracking();
    }
    RefreshCurrentOnlineMapName();
    RefreshHostAddress();
    ClearOnlineStats();
    ClearCurrentRoundMvpState();
    ClearLastRoundMvpState();
    if (g_MapMvpHistory != null)
    {
        g_MapMvpHistory.Clear();
    }
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
            SaveClientStats(i, true, true, true);
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

    if (g_SaveQueue != null)
    {
        delete g_SaveQueue;
        g_SaveQueue = null;
    }

    if (g_MapMvpHistory != null)
    {
        delete g_MapMvpHistory;
        g_MapMvpHistory = null;
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
        GetClientName(client, name, sizeof(name));
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
    if (IsFakeClient(client))
    {
        SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
        return;
    }

    bool lastHuman = !WhaleTracker_HasHumanClientsExcept(client);

    if (IsClientInGame(client))
    {
        SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    }

    SaveClientStats(client, true, true);
    CacheWhalePointsOnDisconnect(client);
    RemoveOnlineStats(client);
    InvalidateClientRoundMvp(client);
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

    RequestClientJoinLeaderboardQuery(client);
    RequestFavoriteClassLoad(client);
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
        "SELECT points, rank, name_color, name, prename FROM whaletracker_points_cache WHERE steamid = '%s' LIMIT 1",
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
            WhaleTracker_ScheduleReconnect(2.0);
        }
        return;
    }

    int points = 0;
    int rank = 0;
    char colorTag[32];
    char cachedName[128];
    char cachedPrename[128];
    colorTag[0] = '\0';
    cachedName[0] = '\0';
    cachedPrename[0] = '\0';

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

    results.FetchString(2, colorTag, sizeof(colorTag));
    results.FetchString(3, cachedName, sizeof(cachedName));
    results.FetchString(4, cachedPrename, sizeof(cachedPrename));
    TrimString(colorTag);
    TrimString(cachedName);
    TrimString(cachedPrename);

    char displayName[128];
    bool useCachedDecorated = false;
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
        useCachedDecorated = (colorTag[0] != '\0' && (cachedPrename[0] != '\0' || cachedName[0] != '\0'));
        if (useCachedDecorated)
        {
            if (cachedPrename[0] != '\0')
            {
                strcopy(displayName, sizeof(displayName), cachedPrename);
            }
            else
            {
                strcopy(displayName, sizeof(displayName), cachedName);
            }
        }
        else
        {
            char rawName[MAX_NAME_LENGTH];
            char rawNameColor[32] = "gold";
            GetClientName(client, rawName, sizeof(rawName));
            EnsureClientSteamId(client);
            if (g_Stats[client].steamId[0] != '\0')
            {
                TryGetFiltersSteamIdColorTag(g_Stats[client].steamId, rawNameColor, sizeof(rawNameColor));
            }
            FormatEx(displayName, sizeof(displayName), "{%s}%s", rawNameColor, rawName);
        }
    }

    if (rank > 0)
    {
        if (useCachedDecorated)
        {
            CPrintToChatAll("{%s}%s{default} (%d Points, Rank #%d) joined the game", colorTag, displayName, points, rank);
        }
        else
        {
            CPrintToChatAll("%s{default} (%d Points, Rank #%d) joined the game", displayName, points, rank);
        }
        PrintToServer("[WhaleTracker] %s (%d Points, Rank #%d) joined the game", displayName, points, rank);
    }
    else
    {
        CPrintToChatAll("%s{default} (Unranked) joined the game", displayName);
        PrintToServer("[WhaleTracker] %s (Unranked) joined the game", displayName);
    }
}
