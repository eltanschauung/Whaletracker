void WhaleTracker_MaybeMarkDatabaseReady()
{
    if (g_bDatabaseReady
        || !g_bAsyncDatabaseConnected
        || !g_bSyncDatabaseConnected
        || !g_bSchemaReady
        || g_hDatabase == null
        || g_hSyncDatabase == null)
    {
        return;
    }

    g_bDatabaseConnectInFlight = false;
    g_bDatabaseReady = true;
    PrintToServer("[WhaleTracker] Database ready schema=%d players=%d round=%d",
        WHALETRACKER_SCHEMA_VERSION,
        GetClientCount(false),
        WhaleTracker_IsRoundRunning() ? 1 : 0);
    WhaleTracker_EnsureRoundStatisticsTable();
    PumpSaveQueue();
}

void WhaleTracker_ScheduleSchemaReadyCheck(float delay)
{
    if (g_bShuttingDown || g_hDatabase == null || g_bSchemaReady)
    {
        return;
    }

    if (g_hSchemaRetryTimer != null)
    {
        return;
    }

    g_hSchemaRetryTimer = CreateTimer(delay, WhaleTracker_SchemaReadyTimer);
}

public Action WhaleTracker_SchemaReadyTimer(Handle timer, any data)
{
    if (timer == g_hSchemaRetryTimer)
    {
        g_hSchemaRetryTimer = null;
    }

    if (!g_bShuttingDown)
    {
        WhaleTracker_RequestSchemaReadyCheck();
    }
    return Plugin_Stop;
}

void WhaleTracker_RequestSchemaReadyCheck()
{
    if (g_bDatabaseReady
        || g_bSchemaReady
        || g_bSchemaCheckInFlight
        || !g_bAsyncDatabaseConnected
        || !g_bSyncDatabaseConnected
        || g_hDatabase == null
        || g_hSyncDatabase == null)
    {
        return;
    }

    g_bSchemaCheckInFlight = true;
    g_hDatabase.Query(WhaleTracker_SchemaVersionCallback,
        "SELECT COALESCE(MAX(version), 0) FROM whaletracker_schema_migrations");
}

public void WhaleTracker_SQLConnect()
{
    if (g_hReconnectTimer != null)
    {
        CloseHandle(g_hReconnectTimer);
        g_hReconnectTimer = null;
    }

    if (g_hSchemaRetryTimer != null)
    {
        CloseHandle(g_hSchemaRetryTimer);
        g_hSchemaRetryTimer = null;
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
    g_bDatabaseConnectInFlight = true;
    g_bSchemaReady = false;
    g_bSchemaCheckInFlight = false;
    g_CvarDatabase.GetString(g_sDatabaseConfig, sizeof(g_sDatabaseConfig));
    g_bShuttingDown = false;
    Database.Connect(T_SQLConnect, g_sDatabaseConfig);
    Database.Connect(T_SQLSyncConnect, g_sDatabaseConfig);
}

public void T_SQLConnect(Database db, const char[] error, any data)
{
    if (db == null)
    {
        LogError("[WhaleTracker] Database connection failed: %s", error);
        g_bDatabaseReady = false;
        g_bAsyncDatabaseConnected = false;
        g_bDatabaseConnectInFlight = false;
        WhaleTracker_ScheduleReconnect(5.0);
        return;
    }

    g_hDatabase = db;
    g_bAsyncDatabaseConnected = true;

    if (!g_hDatabase.SetCharset("utf8mb4"))
    {
        LogError("[WhaleTracker] Failed to set database charset to utf8mb4, names may be truncated.");
    }
    WhaleTracker_RequestSchemaReadyCheck();
}

public void T_SQLSyncConnect(Database db, const char[] error, any data)
{
    if (db == null)
    {
        LogError("[WhaleTracker] Sync database connection failed: %s", error);
        g_bSyncDatabaseConnected = false;
        g_bDatabaseConnectInFlight = false;
        WhaleTracker_ScheduleReconnect(5.0);
        return;
    }

    if (g_hSyncDatabase != null)
    {
        delete g_hSyncDatabase;
        g_hSyncDatabase = null;
    }

    g_hSyncDatabase = db;
    g_bSyncDatabaseConnected = true;

    if (!g_hSyncDatabase.SetCharset("utf8mb4"))
    {
        LogError("[WhaleTracker] Failed to set sync database charset to utf8mb4.");
    }

    WhaleTracker_RequestSchemaReadyCheck();
}

public void WhaleTracker_SchemaVersionCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        g_bSchemaCheckInFlight = false;
        LogError("[WhaleTracker] Failed to verify schema version: %s", error);
        if (WhaleTracker_IsConnectionLostError(error))
        {
            WhaleTracker_ScheduleReconnect(5.0);
        }
        else
        {
            WhaleTracker_ScheduleSchemaReadyCheck(2.0);
        }
        return;
    }

    g_bSchemaCheckInFlight = false;

    int version = 0;
    if (results != null && results.FetchRow())
    {
        version = results.FetchInt(0);
    }

    if (version < WHALETRACKER_SCHEMA_VERSION)
    {
        WhaleTracker_ScheduleSchemaReadyCheck(2.0);
        return;
    }

    g_bSchemaReady = true;
    WhaleTracker_MaybeMarkDatabaseReady();

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
        {
            continue;
        }

        RequestClientStateLoads(i);
    }
}

void LoadClientStats(int client)
{
    if (!IsClientInGame(client) || !g_bDatabaseReady || g_hDatabase == null || g_bStatsLoadPending[client] || g_Stats[client].loaded)
    {
        return;
    }

    EnsureClientSteamId(client);
    if (g_Stats[client].steamId[0] == '\0')
    {
        return;
    }

    g_bStatsLoadPending[client] = true;

    char query[1024];
    Format(query, sizeof(query),
        "SELECT first_seen, kills, deaths, healing, total_ubers, best_ubers_life, medic_drops, uber_drops, airshots, medicKills, heavyKills, marketGardenHits, headshots, backstabs, best_killstreak, assists, playtime, damage_dealt, damage_taken, last_seen "
        ... ", shots_shotguns, hits_shotguns, shots_scatterguns, hits_scatterguns, shots_pistols, hits_pistols, shots_rocketlaunchers, hits_rocketlaunchers, shots_grenadelaunchers, hits_grenadelaunchers, shots_stickylaunchers, hits_stickylaunchers, shots_snipers, hits_snipers, shots_revolvers, hits_revolvers "
        ... "FROM whaletracker WHERE steamid = '%s'", g_Stats[client].steamId);

    g_hDatabase.Query(WhaleTracker_LoadCallback, query, GetClientUserId(client));
}

void LoadClientOnlineSnapshot(int client)
{
    if (!IsClientInGame(client) || !g_bDatabaseReady || g_hDatabase == null || g_bOnlineStateLoadPending[client] || g_MapStats[client].loaded)
    {
        return;
    }

    EnsureClientSteamId(client);
    if (g_Stats[client].steamId[0] == '\0')
    {
        return;
    }

    g_bOnlineStateLoadPending[client] = true;

    char escapedMapName[256];
    EscapeSqlString(g_sOnlineMapName, escapedMapName, sizeof(escapedMapName));

    char query[1024];
    Format(query, sizeof(query),
        "SELECT kills, deaths, assists, damage, damage_taken, healing, headshots, backstabs, medic_drops, uber_drops, airshots, marketGardenHits, playtime, total_ubers, best_streak, best_ubers_life, current_killstreak, current_ubers_life, "
        ... "shots_shotguns, hits_shotguns, shots_scatterguns, hits_scatterguns, shots_pistols, hits_pistols, shots_rocketlaunchers, hits_rocketlaunchers, shots_grenadelaunchers, hits_grenadelaunchers, shots_stickylaunchers, hits_stickylaunchers, shots_snipers, hits_snipers, shots_revolvers, hits_revolvers "
        ... "FROM whaletracker_online WHERE steamid = '%s' AND host_port = %d AND map_name = '%s' AND last_update >= %d LIMIT 1",
        g_Stats[client].steamId,
        g_iHostPort,
        escapedMapName,
        GetTime() - 120);

    g_hDatabase.Query(WhaleTracker_LoadOnlineSnapshotCallback, query, GetClientUserId(client));
}

public void RequestClientStateLoads(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client))
    {
        return;
    }

    if (!g_bDatabaseReady || g_hDatabase == null)
    {
        return;
    }

    if (g_Stats[client].loaded && g_MapStats[client].loaded)
    {
        return;
    }

    EnsureClientSteamId(client);
    if (g_Stats[client].steamId[0] == '\0')
    {
        return;
    }

    LoadClientStats(client);
    LoadClientOnlineSnapshot(client);
}

public void WhaleTracker_LoadCallback(Database db, DBResultSet results, const char[] error, any data)
{
    int index = GetClientOfUserId(data);
    if (!IsValidClient(index) || IsFakeClient(index))
    {
        return;
    }

    g_bStatsLoadPending[index] = false;

    if (error[0] != '\0')
    {
        LogError("[WhaleTracker] Failed to load stats for %N: %s", index, error);
        if (WhaleTracker_IsConnectionLostError(error))
        {
            WhaleTracker_ScheduleReconnect(2.0);
        }
        WhaleTracker_RefreshClientTrackingState(index);
        return;
    }

    if (results != null && results.FetchRow())
    {
        g_Stats[index].firstSeenTimestamp = results.FetchInt(0);
        FormatTime(g_Stats[index].firstSeen, sizeof(g_Stats[index].firstSeen), "%Y-%m-%d", g_Stats[index].firstSeenTimestamp);
        g_Stats[index].kills = results.FetchInt(1);
        g_Stats[index].deaths = results.FetchInt(2);
        g_Stats[index].totalHealing = results.FetchInt(3);
        g_Stats[index].totalUbers = results.FetchInt(4);
        g_Stats[index].bestUbersLife = results.FetchInt(5);
        g_Stats[index].totalMedicDrops = results.FetchInt(6);
        g_Stats[index].totalUberDrops = results.FetchInt(7);
        g_Stats[index].totalAirshots = results.FetchInt(8);
        g_Stats[index].totalMedicKills = results.FetchInt(9);
        g_Stats[index].totalHeavyKills = results.FetchInt(10);
        g_Stats[index].totalMarketGardenHits = results.FetchInt(11);
        g_Stats[index].totalHeadshots = results.FetchInt(12);
        g_Stats[index].totalBackstabs = results.FetchInt(13);
        g_Stats[index].bestKillstreak = results.FetchInt(14);
        g_Stats[index].totalAssists = results.FetchInt(15);
        g_Stats[index].playtime = results.FetchInt(16);
        g_Stats[index].totalDamage = results.FetchInt(17);
        g_Stats[index].totalDamageTaken = results.FetchInt(18);
        g_Stats[index].lastSeen = results.FetchInt(19);
        g_Stats[index].weaponShots[WeaponCategory_Shotguns] = results.FetchInt(20);
        g_Stats[index].weaponHits[WeaponCategory_Shotguns] = results.FetchInt(21);
        g_Stats[index].weaponShots[WeaponCategory_Scatterguns] = results.FetchInt(22);
        g_Stats[index].weaponHits[WeaponCategory_Scatterguns] = results.FetchInt(23);
        g_Stats[index].weaponShots[WeaponCategory_Pistols] = results.FetchInt(24);
        g_Stats[index].weaponHits[WeaponCategory_Pistols] = results.FetchInt(25);
        g_Stats[index].weaponShots[WeaponCategory_RocketLaunchers] = results.FetchInt(26);
        g_Stats[index].weaponHits[WeaponCategory_RocketLaunchers] = results.FetchInt(27);
        g_Stats[index].weaponShots[WeaponCategory_GrenadeLaunchers] = results.FetchInt(28);
        g_Stats[index].weaponHits[WeaponCategory_GrenadeLaunchers] = results.FetchInt(29);
        g_Stats[index].weaponShots[WeaponCategory_StickyLaunchers] = results.FetchInt(30);
        g_Stats[index].weaponHits[WeaponCategory_StickyLaunchers] = results.FetchInt(31);
        g_Stats[index].weaponShots[WeaponCategory_Snipers] = results.FetchInt(32);
        g_Stats[index].weaponHits[WeaponCategory_Snipers] = results.FetchInt(33);
        g_Stats[index].weaponShots[WeaponCategory_Revolvers] = results.FetchInt(34);
        g_Stats[index].weaponHits[WeaponCategory_Revolvers] = results.FetchInt(35);
        g_Stats[index].loaded = true;
    }
    else
    {
        g_Stats[index].firstSeenTimestamp = GetTime();
        FormatTime(g_Stats[index].firstSeen, sizeof(g_Stats[index].firstSeen), "%Y-%m-%d", g_Stats[index].firstSeenTimestamp);
        g_Stats[index].loaded = true;
    }

    TouchClientLastSeen(index);
    WhaleTracker_RefreshClientTrackingState(index);
}

public void WhaleTracker_LoadOnlineSnapshotCallback(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (!IsValidClient(client) || IsFakeClient(client))
    {
        return;
    }

    g_bOnlineStateLoadPending[client] = false;

    if (error[0] != '\0')
    {
        LogError("[WhaleTracker] Failed to restore online snapshot for %N: %s", client, error);
        if (WhaleTracker_IsConnectionLostError(error))
        {
            WhaleTracker_ScheduleReconnect(2.0);
        }
        g_MapStats[client].loaded = true;
        g_MapStats[client].connectTime = GetEngineTime();
        TouchClientLastSeen(client);
        WhaleTracker_RefreshClientTrackingState(client);
        return;
    }

    if (results != null && results.FetchRow())
    {
        g_MapStats[client].kills = results.FetchInt(0);
        g_MapStats[client].deaths = results.FetchInt(1);
        g_MapStats[client].totalAssists = results.FetchInt(2);
        g_MapStats[client].totalDamage = results.FetchInt(3);
        g_MapStats[client].totalDamageTaken = results.FetchInt(4);
        g_MapStats[client].totalHealing = results.FetchInt(5);
        g_MapStats[client].totalHeadshots = results.FetchInt(6);
        g_MapStats[client].totalBackstabs = results.FetchInt(7);
        g_MapStats[client].totalMedicDrops = results.FetchInt(8);
        g_MapStats[client].totalUberDrops = results.FetchInt(9);
        g_MapStats[client].totalAirshots = results.FetchInt(10);
        g_MapStats[client].totalMarketGardenHits = results.FetchInt(11);
        g_MapStats[client].playtime = results.FetchInt(12);
        g_MapStats[client].totalUbers = results.FetchInt(13);
        g_MapStats[client].bestKillstreak = results.FetchInt(14);
        g_MapStats[client].bestUbersLife = results.FetchInt(15);
        g_MapStats[client].currentKillstreak = results.FetchInt(16);
        g_MapStats[client].currentUbersLife = results.FetchInt(17);
        g_Stats[client].currentKillstreak = g_MapStats[client].currentKillstreak;
        g_Stats[client].currentUbersLife = g_MapStats[client].currentUbersLife;
        g_MapStats[client].weaponShots[WeaponCategory_Shotguns] = results.FetchInt(18);
        g_MapStats[client].weaponHits[WeaponCategory_Shotguns] = results.FetchInt(19);
        g_MapStats[client].weaponShots[WeaponCategory_Scatterguns] = results.FetchInt(20);
        g_MapStats[client].weaponHits[WeaponCategory_Scatterguns] = results.FetchInt(21);
        g_MapStats[client].weaponShots[WeaponCategory_Pistols] = results.FetchInt(22);
        g_MapStats[client].weaponHits[WeaponCategory_Pistols] = results.FetchInt(23);
        g_MapStats[client].weaponShots[WeaponCategory_RocketLaunchers] = results.FetchInt(24);
        g_MapStats[client].weaponHits[WeaponCategory_RocketLaunchers] = results.FetchInt(25);
        g_MapStats[client].weaponShots[WeaponCategory_GrenadeLaunchers] = results.FetchInt(26);
        g_MapStats[client].weaponHits[WeaponCategory_GrenadeLaunchers] = results.FetchInt(27);
        g_MapStats[client].weaponShots[WeaponCategory_StickyLaunchers] = results.FetchInt(28);
        g_MapStats[client].weaponHits[WeaponCategory_StickyLaunchers] = results.FetchInt(29);
        g_MapStats[client].weaponShots[WeaponCategory_Snipers] = results.FetchInt(30);
        g_MapStats[client].weaponHits[WeaponCategory_Snipers] = results.FetchInt(31);
        g_MapStats[client].weaponShots[WeaponCategory_Revolvers] = results.FetchInt(32);
        g_MapStats[client].weaponHits[WeaponCategory_Revolvers] = results.FetchInt(33);
    }

    g_MapStats[client].loaded = true;
    g_MapStats[client].connectTime = GetEngineTime();
    TouchClientLastSeen(client);
    WhaleTracker_RefreshClientTrackingState(client);
}

bool HasMapActivity(WhaleStats stats)
{
    return stats.playtime > 0
        || stats.kills > 0
        || stats.deaths > 0
        || stats.totalAssists > 0
        || stats.totalHealing > 0
        || stats.totalDamage > 0
        || stats.totalDamageTaken > 0
        || stats.totalHeadshots > 0
        || stats.totalBackstabs > 0
        || stats.totalUberDrops > 0
        || stats.totalMedicDrops > 0;
}

bool SaveClientMapStats(int client)
{
    if (!IsValidClient(client))
        return false;

    if (!WhaleTracker_AreClientStatsReady(client))
        return false;

    if (!g_MapStats[client].loaded)
        return false;

    if (g_MapStats[client].steamId[0] == '\0')
        return false;

    if (!HasMapActivity(g_MapStats[client]))
        return false;

    int snapshot[MATCH_STAT_COUNT];
    SnapshotFromStats(g_MapStats[client], snapshot);
    AppendSnapshotToStorage(g_MapStats[client].steamId, snapshot);

    EnsureMatchStorage();

    char name[MAX_NAME_LENGTH];
    if (IsClientInGame(client))
    {
        GetClientName(client, name, sizeof(name));
    }
    else if (!GetStoredMatchPlayerName(g_MapStats[client].steamId, name, sizeof(name)))
    {
        name[0] = '\0';
    }

    if (!name[0])
    {
        strcopy(name, sizeof(name), g_MapStats[client].steamId);
    }

    RememberMatchPlayerName(g_MapStats[client].steamId, name);

    return true;
}

void QueueStatsSave(int client, int userId, bool forceSync)
{
    char query[SAVE_QUERY_MAXLEN];
    char accuracyValueSegment[512];
    BuildWeaponAccuracySegment(g_Stats[client], accuracyValueSegment, sizeof(accuracyValueSegment));

    Format(query, sizeof(query),
        "INSERT INTO whaletracker "
        ... "(steamid, first_seen, kills, deaths, healing, total_ubers, best_ubers_life, medic_drops, uber_drops, airshots, medicKills, heavyKills, marketGardenHits, headshots, backstabs, "
        ... "best_killstreak, assists, playtime, damage_dealt, damage_taken, last_seen, "
        ... "shots_shotguns, hits_shotguns, shots_scatterguns, hits_scatterguns, shots_pistols, hits_pistols, shots_rocketlaunchers, hits_rocketlaunchers, shots_grenadelaunchers, hits_grenadelaunchers, shots_stickylaunchers, hits_stickylaunchers, shots_snipers, hits_snipers, shots_revolvers, hits_revolvers) "
        ... "VALUES ('%s', %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, "
        ... "%d, %d, %d, %d, %d, %d, %d, "
        ... "%s) "
        ... "ON DUPLICATE KEY UPDATE "
        ... "first_seen = LEAST(first_seen, VALUES(first_seen)), "
        ... "kills = GREATEST(kills, VALUES(kills)), "
        ... "deaths = GREATEST(deaths, VALUES(deaths)), "
        ... "healing = GREATEST(healing, VALUES(healing)), "
        ... "total_ubers = GREATEST(total_ubers, VALUES(total_ubers)), "
        ... "best_ubers_life = GREATEST(best_ubers_life, VALUES(best_ubers_life)), "
        ... "medic_drops = GREATEST(medic_drops, VALUES(medic_drops)), "
        ... "uber_drops = GREATEST(uber_drops, VALUES(uber_drops)), "
        ... "airshots = GREATEST(airshots, VALUES(airshots)), "
        ... "medicKills = GREATEST(medicKills, VALUES(medicKills)), "
        ... "heavyKills = GREATEST(heavyKills, VALUES(heavyKills)), "
        ... "marketGardenHits = GREATEST(marketGardenHits, VALUES(marketGardenHits)), "
        ... "headshots = GREATEST(headshots, VALUES(headshots)), "
        ... "backstabs = GREATEST(backstabs, VALUES(backstabs)), "
        ... "best_killstreak = GREATEST(best_killstreak, VALUES(best_killstreak)), "
        ... "assists = GREATEST(assists, VALUES(assists)), "
        ... "playtime = GREATEST(playtime, VALUES(playtime)), "
        ... "damage_dealt = GREATEST(damage_dealt, VALUES(damage_dealt)), "
        ... "damage_taken = GREATEST(damage_taken, VALUES(damage_taken)), "
        ... "last_seen = GREATEST(last_seen, VALUES(last_seen)), "

        ... "shots_shotguns = GREATEST(shots_shotguns, VALUES(shots_shotguns)), "
        ... "hits_shotguns = GREATEST(hits_shotguns, VALUES(hits_shotguns)), "
        ... "shots_scatterguns = GREATEST(shots_scatterguns, VALUES(shots_scatterguns)), "
        ... "hits_scatterguns = GREATEST(hits_scatterguns, VALUES(hits_scatterguns)), "
        ... "shots_pistols = GREATEST(shots_pistols, VALUES(shots_pistols)), "
        ... "hits_pistols = GREATEST(hits_pistols, VALUES(hits_pistols)), "
        ... "shots_rocketlaunchers = GREATEST(shots_rocketlaunchers, VALUES(shots_rocketlaunchers)), "
        ... "hits_rocketlaunchers = GREATEST(hits_rocketlaunchers, VALUES(hits_rocketlaunchers)), "
        ... "shots_grenadelaunchers = GREATEST(shots_grenadelaunchers, VALUES(shots_grenadelaunchers)), "
        ... "hits_grenadelaunchers = GREATEST(hits_grenadelaunchers, VALUES(hits_grenadelaunchers)), "
        ... "shots_stickylaunchers = GREATEST(shots_stickylaunchers, VALUES(shots_stickylaunchers)), "
        ... "hits_stickylaunchers = GREATEST(hits_stickylaunchers, VALUES(hits_stickylaunchers)), "
        ... "shots_snipers = GREATEST(shots_snipers, VALUES(shots_snipers)), "
        ... "hits_snipers = GREATEST(hits_snipers, VALUES(hits_snipers)), "
        ... "shots_revolvers = GREATEST(shots_revolvers, VALUES(shots_revolvers)), "
        ... "hits_revolvers = GREATEST(hits_revolvers, VALUES(hits_revolvers))",
        g_Stats[client].steamId,
        g_Stats[client].firstSeenTimestamp,
        g_Stats[client].kills,
        g_Stats[client].deaths,
        g_Stats[client].totalHealing,
        g_Stats[client].totalUbers,
        g_Stats[client].bestUbersLife,
        g_Stats[client].totalMedicDrops,
        g_Stats[client].totalUberDrops,
        g_Stats[client].totalAirshots,
        g_Stats[client].totalMedicKills,
        g_Stats[client].totalHeavyKills,
        g_Stats[client].totalMarketGardenHits,
        g_Stats[client].totalHeadshots,
        g_Stats[client].totalBackstabs,
        g_Stats[client].bestKillstreak,
        g_Stats[client].totalAssists,
        g_Stats[client].playtime,
        g_Stats[client].totalDamage,
        g_Stats[client].totalDamageTaken,
        g_Stats[client].lastSeen,

        accuracyValueSegment);

    QueueSaveQuery(query, userId, forceSync);
}

bool SaveClientStats(int client, bool includeMapStats, bool forceSave, bool forceSync = false)
{
    if (!IsValidClient(client))
        return false;

    EnsureClientSteamId(client);

    if (g_Stats[client].steamId[0] == '\0')
        return false;

    if (!g_Stats[client].loaded || g_bStatsLoadPending[client])
    {
        return false;
    }

    bool playtimeChanged = AccumulatePlaytime(client);

    g_KillSaveCounter[client] = 0;

    TouchClientLastSeen(client);

    if (!forceSave && !g_bStatsDirty[client] && !playtimeChanged)
    {
        return false;
    }

    int userId = GetClientUserId(client);
    QueueStatsSave(client, userId, forceSync);

    if (includeMapStats)
    {
        SaveClientMapStats(client);
    }

    g_bStatsDirty[client] = false;

    return true;
}

public void WhaleTracker_SaveCallback(Database db, DBResultSet results, const char[] error, any data)
{
    int slot = data;
    int userId = 0;

    if (slot >= 0 && slot < MAX_CONCURRENT_SAVE_QUERIES)
    {
        userId = g_SaveQueryUserIds[slot];
    }

    if (error[0] != '\0')
    {
        int client = (userId > 0) ? GetClientOfUserId(userId) : 0;
        char queryPreview[256];
        queryPreview[0] = '\0';

        if (slot >= 0 && slot < MAX_CONCURRENT_SAVE_QUERIES)
        {
            if (g_SaveQueryBuffers[slot][0] != '\0')
            {
                strcopy(queryPreview, sizeof(queryPreview), g_SaveQueryBuffers[slot]);
            }
        }

        if (client > 0 && IsValidClient(client))
        {
            if (queryPreview[0])
            {
                LogError("[WhaleTracker] Failed to save stats for %N: %s | Query: %s", client, error, queryPreview);
            }
            else
            {
                LogError("[WhaleTracker] Failed to save stats for %N: %s", client, error);
            }
        }
        else if (userId > 0)
        {
            if (queryPreview[0])
            {
                LogError("[WhaleTracker] Failed to save stats (userid %d): %s | Query: %s", userId, error, queryPreview);
            }
            else
            {
                LogError("[WhaleTracker] Failed to save stats (userid %d): %s", userId, error);
            }
        }
        else
        {
            if (queryPreview[0])
            {
                LogError("[WhaleTracker] Failed to save stats: %s | Query: %s", error, queryPreview);
            }
            else
            {
                LogError("[WhaleTracker] Failed to save stats: %s", error);
            }
        }

        if (WhaleTracker_IsConnectionLostError(error))
        {
            WhaleTracker_ScheduleReconnect(2.0);
        }
    }

    if (slot >= 0 && slot < MAX_CONCURRENT_SAVE_QUERIES)
    {
        g_SaveQuerySlotUsed[slot] = false;
        g_SaveQueryUserIds[slot] = 0;
        g_SaveQueryBuffers[slot][0] = '\0';
    }

    if (g_PendingSaveQueries > 0)
    {
        g_PendingSaveQueries--;
    }

    RequestPumpSaveQueue();
}
