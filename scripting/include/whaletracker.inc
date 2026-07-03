#if defined _whaletracker_helpers_included
  #endinput
#endif
#define _whaletracker_helpers_included

public void OnConfigsExecuted()
{
    RefreshHostAddress();
    RefreshServerFlags();
}

void ResetRuntimeCounters(WhaleStats stats)
{
    stats.currentKillstreak = 0;
    stats.currentUbersLife = 0;
    stats.currentAssistsLife = 0;
}

void ResetStatsStruct(WhaleStats stats, bool resetIdentity)
{
    if (resetIdentity)
    {
        stats.loaded = false;
        stats.steamId[0] = '\0';
        stats.firstSeen[0] = '\0';
        stats.firstSeenTimestamp = 0;
        stats.isAdmin = false;
    }

    stats.kills = 0;
    stats.deaths = 0;

    stats.totalHealing = 0;
    stats.totalUbers = 0;
    stats.totalMedicDrops = 0;
    stats.totalAirshots = 0;
    stats.totalCrossbowHits = 0;
    stats.totalMarketGardenHits = 0;
    stats.totalHeadshots = 0;
    stats.totalBackstabs = 0;
    stats.totalAssists = 0;
    stats.totalDamage = 0;
    stats.totalDamageTaken = 0;
    stats.totalUberDrops = 0;
    for (int i = 0; i <= WEAPON_CATEGORY_COUNT; i++)
    {
        stats.weaponShots[i] = 0;
        stats.weaponHits[i] = 0;
    }
    stats.lastSeen = 0;
    stats.bestKillstreak = 0;
    stats.bestUbersLife = 0;
    stats.playtime = 0;
    stats.connectTime = 0.0;

    ResetRuntimeCounters(stats);
}

void ResetAllStats(int client)
{
    ResetStatsStruct(g_Stats[client], true);
    ResetStatsStruct(g_MapStats[client], true);
    g_bStatsDirty[client] = false;
    g_bStatsLoadPending[client] = false;
    g_bOnlineStateLoadPending[client] = false;
    g_bTrackEligible[client] = false;
    g_iDamageGate[client] = 0;
    for (int i = 0; i <= WEAPON_CATEGORY_COUNT; i++)
    {
        g_fLastHitscanAccuracyHit[client][i] = 0.0;
    }
}

void ResetMapStats(int client)
{
    ResetStatsStruct(g_MapStats[client], false);
    g_MapStats[client].loaded = g_Stats[client].loaded;
    g_MapStats[client].isAdmin = g_Stats[client].isAdmin;
    if (g_Stats[client].steamId[0] != '\0')
    {
        strcopy(g_MapStats[client].steamId, sizeof(g_MapStats[client].steamId), g_Stats[client].steamId);
    }
    g_MapStats[client].connectTime = GetEngineTime();
}

bool WhaleTracker_ComputeClientAdminStatus(int client)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
    {
        return false;
    }

    return GetUserAdmin(client) != INVALID_ADMIN_ID;
}

void WhaleTracker_UpdateClientAdminStatus(int client)
{
    if (client <= 0 || client > MaxClients || IsFakeClient(client))
    {
        return;
    }

    bool isAdmin = WhaleTracker_ComputeClientAdminStatus(client);
    if (g_Stats[client].isAdmin == isAdmin && g_MapStats[client].isAdmin == isAdmin)
    {
        return;
    }

    g_Stats[client].isAdmin = isAdmin;
    g_MapStats[client].isAdmin = isAdmin;

    if (g_Stats[client].loaded)
    {
        MarkClientDirty(client);
    }
}

void ResetRuntimeStats(int client)
{
    ResetRuntimeCounters(g_Stats[client]);
    ResetRuntimeCounters(g_MapStats[client]);
}

void TouchClientLastSeen(int client)
{
    if (!IsClientInGame(client))
    {
        return;
    }

    int now = GetTime();
    g_Stats[client].lastSeen = now;
    WhaleTracker_RefreshClientTrackingState(client);
}

bool WhaleTracker_AreClientStatsReady(int client)
{
    return (client > 0
        && client <= MaxClients
        && IsClientInGame(client)
        && !IsFakeClient(client)
        && g_Stats[client].loaded
        && !g_bStatsLoadPending[client]
        && !g_bOnlineStateLoadPending[client]);
}

bool WhaleTracker_IsRoundRunning()
{
    if (GetFeatureStatus(FeatureType_Native, "DGM_IsRoundRunning") == FeatureStatus_Available)
    {
        return DGM_IsRoundRunning();
    }

    return (GameRules_GetRoundState() == RoundState_RoundRunning);
}

bool WhaleTracker_HasHumanClientsExcept(int excludedClient)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (i == excludedClient || !IsClientConnected(i) || IsFakeClient(i))
        {
            continue;
        }

        return true;
    }

    return false;
}

void WhaleTracker_RefreshClientTrackingState(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    g_bTrackEligible[client] = (WhaleTracker_AreClientStatsReady(client) && GetClientTeam(client) > 1);
}

void ClearOnlineStats()
{
    char deleteOnline[128];
    Format(deleteOnline, sizeof(deleteOnline), "DELETE FROM whaletracker_online WHERE host_port = %d", g_iHostPort);
    char clearOnlineFields[96];
    Format(clearOnlineFields, sizeof(clearOnlineFields), "\"kind\":\"online_clear_host\",\"host_port\":%d", g_iHostPort);
    if (!WhaleTracker_RustQueueTypedWrite(deleteOnline, clearOnlineFields, 0, false))
    {
        QueueSaveQuery(deleteOnline, 0, false);
    }

    char deleteServer[128];
    Format(deleteServer, sizeof(deleteServer), "DELETE FROM whaletracker_servers WHERE port = %d", g_iHostPort);
    char clearServerFields[96];
    Format(clearServerFields, sizeof(clearServerFields), "\"kind\":\"server_clear_port\",\"host_port\":%d", g_iHostPort);
    if (!WhaleTracker_RustQueueTypedWrite(deleteServer, clearServerFields, 0, false))
    {
        QueueSaveQuery(deleteServer, 0, false);
    }
}

void RemoveOnlineStats(int client)
{
    char steamId[STEAMID64_LEN];
    if (!GetClientAuthId(client, AuthId_SteamID64, steamId, sizeof(steamId)))
        return;

    char query[192];
    Format(query, sizeof(query), "DELETE FROM whaletracker_online WHERE steamid = '%s' AND host_port = %d", steamId, g_iHostPort);
    char fields[192];
    Format(fields, sizeof(fields), "\"kind\":\"online_remove\",\"steamid\":\"%s\",\"host_port\":%d", steamId, g_iHostPort);
    if (!WhaleTracker_RustQueueTypedWrite(query, fields, 0, false))
    {
        QueueSaveQuery(query, 0, false);
    }
}

bool QueueClientOnlineSnapshot(int client, int now, float engineNow, int playerCount, int visibleMax, const char[] escapedMapName, const char[] escapedHostIp, bool forceSync)
{
    if (!WhaleTracker_AreClientStatsReady(client))
    {
        return false;
    }

    char steamId[STEAMID64_LEN];
    if (!GetClientAuthId(client, AuthId_SteamID64, steamId, sizeof(steamId)))
    {
        return false;
    }

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));
    RememberMatchPlayerName(steamId, name);

    char escapedName[MAX_NAME_LENGTH * 2];
    SQL_EscapeString(g_hDatabase, name, escapedName, sizeof(escapedName));

    TouchClientLastSeen(client);

    TFClassType tfClassType = TF2_GetPlayerClass(client);
    int tfClass = view_as<int>(tfClassType);
    int team = GetClientTeam(client);
    bool alive = IsPlayerAlive(client);
    bool spectator = (team != 2 && team != 3) || tfClassType == TFClass_Unknown;

    int playtime = g_MapStats[client].playtime;
    if (g_MapStats[client].connectTime > 0.0)
    {
        playtime += RoundToFloor(engineNow - g_MapStats[client].connectTime);
    }

    char weaponValueSegment[512];
    BuildWeaponAccuracySegment(g_MapStats[client], weaponValueSegment, sizeof(weaponValueSegment));

    char query[SAVE_QUERY_MAXLEN];
    Format(query, sizeof(query),
        "REPLACE INTO whaletracker_online "
        ... "(steamid, personaname, class, team, alive, is_spectator, is_admin, kills, deaths, assists, damage, damage_taken, healing, headshots, backstabs, medic_drops, uber_drops, airshots, marketGardenHits, playtime, total_ubers, best_streak, best_ubers_life, current_killstreak, current_ubers_life, visible_max, time_connected, shots_shotguns, hits_shotguns, shots_scatterguns, hits_scatterguns, shots_pistols, hits_pistols, shots_rocketlaunchers, hits_rocketlaunchers, shots_grenadelaunchers, hits_grenadelaunchers, shots_stickylaunchers, hits_stickylaunchers, shots_snipers, hits_snipers, shots_revolvers, hits_revolvers, host_ip, host_port, playercount, map_name, last_update) "
        ... "VALUES ('%s', '%s', %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %s, '%s', %d, %d, '%s', %d)",
        steamId,
        escapedName,
        tfClass,
        team,
        alive ? 1 : 0,
        spectator ? 1 : 0,
        g_Stats[client].isAdmin ? 1 : 0,
        g_MapStats[client].kills,
        g_MapStats[client].deaths,
        g_MapStats[client].totalAssists,
        g_MapStats[client].totalDamage,
        g_MapStats[client].totalDamageTaken,
        g_MapStats[client].totalHealing,
        g_MapStats[client].totalHeadshots,
        g_MapStats[client].totalBackstabs,
        g_MapStats[client].totalMedicDrops,
        g_MapStats[client].totalUberDrops,
        g_MapStats[client].totalAirshots,
        g_MapStats[client].totalMarketGardenHits,
        playtime,
        g_MapStats[client].totalUbers,
        g_MapStats[client].bestKillstreak,
        g_MapStats[client].bestUbersLife,
        g_MapStats[client].currentKillstreak,
        g_MapStats[client].currentUbersLife,
        visibleMax,
        playtime,
        weaponValueSegment,
        escapedHostIp,
        g_iHostPort,
        playerCount,
        escapedMapName,
        now);

    QueueSaveQuery(query, 0, forceSync);
    return true;
}

public Action Timer_UpdateOnlineStats(Handle timer, any data)
{
    if (!WhaleTracker_HasHumanClientsExcept(0))
    {
        FinalizeCurrentMatch(false);
    }

    if (!g_bDatabaseReady || g_hDatabase == null)
        return Plugin_Continue;

    int now = GetTime();
    float engineNow = GetEngineTime();
    int onlinePlayerCount = WhaleTracker_GetOnlinePlayerCount();
    int serverPlayerCount = onlinePlayerCount;
    int visibleMax = WhaleTracker_GetCurrentServerCapacity();

    char query[SAVE_QUERY_MAXLEN];
    char escapedMapName[256];
    char mapName[128];
    char escapedGameName[128];
    char gameName[64];
    char escapedGameUrl[64];
    char gameUrl[32];
    if (g_sOnlineMapName[0])
    {
        strcopy(mapName, sizeof(mapName), g_sOnlineMapName);
    }
    else
    {
        strcopy(mapName, sizeof(mapName), "unknown");
    }
    SQL_EscapeString(g_hDatabase, mapName, escapedMapName, sizeof(escapedMapName));
    if (g_hGameName != null)
    {
        g_hGameName.GetString(gameName, sizeof(gameName));
    }
    if (!gameName[0])
    {
        strcopy(gameName, sizeof(gameName), "TF2");
    }
    SQL_EscapeString(g_hDatabase, gameName, escapedGameName, sizeof(escapedGameName));
    if (g_hGameUrl != null)
    {
        g_hGameUrl.GetString(gameUrl, sizeof(gameUrl));
    }
    if (!gameUrl[0])
    {
        strcopy(gameUrl, sizeof(gameUrl), "440");
    }
    SQL_EscapeString(g_hDatabase, gameUrl, escapedGameUrl, sizeof(escapedGameUrl));

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

    char hostCity[64];
    if (g_sHostCity[0])
    {
        strcopy(hostCity, sizeof(hostCity), g_sHostCity);
    }
    else
    {
        strcopy(hostCity, sizeof(hostCity), "Unknown");
    }
    char escapedHostCity[128];
    SQL_EscapeString(g_hDatabase, hostCity, escapedHostCity, sizeof(escapedHostCity));

    char hostCountry[3];
    if (g_sHostCountryLower[0])
    {
        strcopy(hostCountry, sizeof(hostCountry), g_sHostCountryLower);
    }
    else
    {
        strcopy(hostCountry, sizeof(hostCountry), "");
    }
    char escapedHostCountry[16];
    SQL_EscapeString(g_hDatabase, hostCountry, escapedHostCountry, sizeof(escapedHostCountry));

    char escapedServerFlags[512];
    SQL_EscapeString(g_hDatabase, g_sServerFlags, escapedServerFlags, sizeof(escapedServerFlags));

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client))
            continue;

        if (!QueueClientOnlineSnapshot(client, now, engineNow, onlinePlayerCount, visibleMax, escapedMapName, escapedHostIp, false))
            continue;

        int snapshotData[MATCH_STAT_COUNT];
        SnapshotFromStatsAtTime(g_MapStats[client], snapshotData, engineNow);
        char steamId[STEAMID64_LEN];
        if (!GetClientAuthId(client, AuthId_SteamID64, steamId, sizeof(steamId)))
        {
            continue;
        }

        char name[MAX_NAME_LENGTH];
        ResolveMatchPlayerName(client, steamId, name, sizeof(name));
        InsertPlayerLogRecord(snapshotData, steamId, name, now, false);
    }

    Format(query, sizeof(query), "DELETE FROM whaletracker_online WHERE last_update < %d", now - 20);
    QueueSaveQuery(query, 0, false);

    Format(query, sizeof(query),
        "REPLACE INTO whaletracker_servers "
        ... "(ip, port, playercount, visible_max, game, game_url, map, city, country, flags, last_update) "
        ... "VALUES ('%s', %d, %d, %d, '%s', '%s', '%s', '%s', '%s', '%s', %d)",
        escapedHostIp,
        g_iHostPort,
        serverPlayerCount,
        visibleMax,
        escapedGameName,
        escapedGameUrl,
        escapedMapName,
        escapedHostCity,
        escapedHostCountry,
        escapedServerFlags,
        now);
    QueueSaveQuery(query, 0, false);

    int duration = (g_iMatchStartTime > 0) ? (now - g_iMatchStartTime) : 0;
    InsertMatchLogRecord(now, duration, serverPlayerCount, false);

    return Plugin_Continue;
}

public Action Timer_GlobalSave(Handle timer, any data)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            SaveClientStats(i, false, false);
        }
    }
    return Plugin_Continue;
}

void EscapeSqlString(const char[] input, char[] output, int maxlen)
{
    if (maxlen <= 0)
    {
        return;
    }

    output[0] = '\0';

    if (!input[0])
    {
        return;
    }

    if (g_hDatabase != null && g_bDatabaseReady)
    {
        SQL_EscapeString(g_hDatabase, input, output, maxlen);
        return;
    }

    int written = 0;
    for (int i = 0; input[i] != '\0' && written < maxlen - 1; i++)
    {
        char c = input[i];

        if (c == '\\' || c == '\'' || c == '\"')
        {
            if (written + 2 >= maxlen)
            {
                break;
            }
            output[written++] = '\\';
            output[written++] = c;
        }
        else if (c == '\n' || c == '\r' || c == '\t')
        {
            if (written + 2 >= maxlen)
            {
                break;
            }
            output[written++] = '\\';
            output[written++] = (c == '\n') ? 'n' : ((c == '\r') ? 'r' : 't');
        }
        else
        {
            output[written++] = c;
        }
    }

    output[written] = '\0';
}

void EnsureMatchStorage()
{
    if (g_DisconnectedStats == null)
    {
        g_DisconnectedStats = new StringMap();
    }
    if (g_MatchNames == null)
    {
        g_MatchNames = new StringMap();
    }
}

void ResetMatchStorage()
{
    EnsureMatchStorage();
    g_DisconnectedStats.Clear();
    g_MatchNames.Clear();
}

void ClearCurrentMatchTracking()
{
    ResetMatchStorage();
    g_bMatchFinalized = true;
    g_sCurrentLogId[0] = '\0';
    g_iMatchStartTime = 0;
}

void CopyLowercase(const char[] source, char[] dest, int maxlen)
{
    if (maxlen <= 0)
        return;

    int i = 0;
    for (; i < maxlen - 1 && source[i] != '\0'; i++)
    {
        dest[i] = CharToLower(source[i]);
    }
    dest[i] = '\0';
}

bool WhaleTracker_GetClientCountryCode(int client, char[] countryCode, int maxlen)
{
    if (maxlen <= 0)
        return false;

    countryCode[0] = '\0';

    char rawIp[64];
    if (!GetClientIP(client, rawIp, sizeof(rawIp), false) || !rawIp[0])
    {
        return false;
    }

    char geoCode[3];
    if (!GeoipCode2(rawIp, geoCode) || !geoCode[0])
    {
        return false;
    }

    CopyLowercase(geoCode, countryCode, maxlen);
    return countryCode[0] != '\0';
}

bool WhaleTracker_IsConnectionLostError(const char[] error)
{
    if (!error[0])
    {
        return false;
    }

    return StrContains(error, "Lost connection to MySQL server", false) != -1
        || StrContains(error, "MySQL server has gone away", false) != -1
        || StrContains(error, "Server has gone away", false) != -1;
}

void WhaleTracker_ScheduleReconnect(float delay)
{
    if (g_bShuttingDown)
    {
        return;
    }

    if (g_hReconnectTimer != null)
    {
        PrintToServer("[WhaleTracker] DB reconnect already scheduled delay=%.2f", delay);
        return;
    }

    g_bDatabaseReady = false;
    g_bAsyncDatabaseConnected = false;
    g_bSyncDatabaseConnected = false;
    g_bDatabaseConnectInFlight = false;
    g_bSchemaReady = false;
    g_bSchemaCheckInFlight = false;

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

    if (g_hSchemaRetryTimer != null)
    {
        CloseHandle(g_hSchemaRetryTimer);
        g_hSchemaRetryTimer = null;
    }

    PrintToServer("[WhaleTracker] DB reconnect scheduled delay=%.2f players=%d round=%d",
        delay,
        GetClientCount(false),
        WhaleTracker_IsRoundRunning() ? 1 : 0);
    g_hReconnectTimer = CreateTimer(delay, WhaleTracker_ReconnectTimer);
}

public Action WhaleTracker_ReconnectTimer(Handle timer, any data)
{
    if (timer == g_hReconnectTimer)
    {
        g_hReconnectTimer = null;
    }

    PrintToServer("[WhaleTracker] DB reconnect timer fired players=%d round=%d",
        GetClientCount(false),
        WhaleTracker_IsRoundRunning() ? 1 : 0);
    WhaleTracker_SQLConnect();
    return Plugin_Stop;
}

bool WhaleTracker_IsDatabaseHealthy()
{
    if (!g_bDatabaseReady || g_hDatabase == null)
    {
        if (g_bDatabaseConnectInFlight)
        {
            return true;
        }

        return false;
    }

    if (SQLFastQuerySync("SELECT 1"))
    {
        return true;
    }

    char error[256];
    GetSyncDatabaseError(error, sizeof(error));
    LogError("[WhaleTracker] DB health check failed: %s", error);
    WhaleTracker_ScheduleReconnect(1.0);
    return false;
}

void RememberMatchPlayerName(const char[] steamId, const char[] name)
{
    if (!steamId[0] || !name[0])
        return;

    EnsureMatchStorage();
    g_MatchNames.SetString(steamId, name);
}

bool GetStoredMatchPlayerName(const char[] steamId, char[] buffer, int maxlen)
{
    if (!steamId[0] || maxlen <= 0)
    {
        return false;
    }

    EnsureMatchStorage();
    return g_MatchNames.GetString(steamId, buffer, maxlen);
}

bool GetFiltersRecordedMatchName(const char[] steamId, char[] buffer, int maxlen)
{
    if (!steamId[0] || maxlen <= 0)
    {
        return false;
    }

    if (GetFeatureStatus(FeatureType_Native, "Filters_GetLastRecordedSteamName") != FeatureStatus_Available)
    {
        return false;
    }

    if (!Filters_GetLastRecordedSteamName(steamId, buffer, maxlen))
    {
        return false;
    }

    TrimString(buffer);
    return buffer[0] != '\0';
}

bool MatchPlayerNameNeedsUtfFallback(const char[] name)
{
    return name[0] == '\0' || StrContains(name, "??", false) != -1;
}

bool GetPrenameMatchName(const char[] steamId, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    if (!steamId[0] || maxlen <= 0 || g_hSyncDatabase == null)
    {
        return false;
    }

    char escapedSteam[64];
    SQL_EscapeString(g_hSyncDatabase, steamId, escapedSteam, sizeof(escapedSteam));

    char query[256];
    Format(query, sizeof(query),
        "SELECT newname FROM prename_rules WHERE pattern COLLATE utf8mb4_uca1400_ai_ci = '%s' LIMIT 1",
        escapedSteam);

    DBResultSet results = SQL_Query(g_hSyncDatabase, query);
    if (results == null)
    {
        return false;
    }

    bool found = false;
    if (results.FetchRow())
    {
        results.FetchString(0, buffer, maxlen);
        TrimString(buffer);
        found = buffer[0] != '\0';
    }

    delete results;
    return found;
}

bool TryResolveUtfMatchPlayerName(const char[] steamId, char[] buffer, int maxlen)
{
    if (GetPrenameMatchName(steamId, buffer, maxlen))
    {
        return true;
    }

    return GetFiltersRecordedMatchName(steamId, buffer, maxlen);
}

void ResolveMatchPlayerName(int client, const char[] steamId, char[] buffer, int maxlen)
{
    if (maxlen <= 0)
    {
        return;
    }

    buffer[0] = '\0';

    if (client > 0 && client <= MaxClients && IsClientInGame(client))
    {
        GetClientName(client, buffer, maxlen);
        TrimString(buffer);
        if (!MatchPlayerNameNeedsUtfFallback(buffer) || TryResolveUtfMatchPlayerName(steamId, buffer, maxlen))
        {
            return;
        }
    }

    if (GetStoredMatchPlayerName(steamId, buffer, maxlen))
    {
        TrimString(buffer);
        if (!MatchPlayerNameNeedsUtfFallback(buffer) || TryResolveUtfMatchPlayerName(steamId, buffer, maxlen))
        {
            return;
        }
    }

    if (TryResolveUtfMatchPlayerName(steamId, buffer, maxlen))
    {
        return;
    }

    strcopy(buffer, maxlen, steamId);
}

void SnapshotFromStats(const WhaleStats stats, int data[MATCH_STAT_COUNT])
{
    data[MatchStat_Kills] = stats.kills;
    data[MatchStat_Deaths] = stats.deaths;
    data[MatchStat_Assists] = stats.totalAssists;
    data[MatchStat_Damage] = stats.totalDamage;
    data[MatchStat_DamageTaken] = stats.totalDamageTaken;
    data[MatchStat_Healing] = stats.totalHealing;
    data[MatchStat_Headshots] = stats.totalHeadshots;
    data[MatchStat_Backstabs] = stats.totalBackstabs;
    data[MatchStat_Ubers] = stats.totalUbers;
    data[MatchStat_Playtime] = stats.playtime;
    data[MatchStat_MedicDrops] = stats.totalMedicDrops;
    data[MatchStat_UberDrops] = stats.totalUberDrops;
    data[MatchStat_Airshots] = stats.totalAirshots;
    data[MatchStat_MarketGardenHits] = stats.totalMarketGardenHits;
    data[MatchStat_ShotsShotguns] = stats.weaponShots[WeaponCategory_Shotguns];
    data[MatchStat_HitsShotguns] = stats.weaponHits[WeaponCategory_Shotguns];
    data[MatchStat_ShotsScatterguns] = stats.weaponShots[WeaponCategory_Scatterguns];
    data[MatchStat_HitsScatterguns] = stats.weaponHits[WeaponCategory_Scatterguns];
    data[MatchStat_ShotsPistols] = stats.weaponShots[WeaponCategory_Pistols];
    data[MatchStat_HitsPistols] = stats.weaponHits[WeaponCategory_Pistols];
    data[MatchStat_ShotsRocketLaunchers] = stats.weaponShots[WeaponCategory_RocketLaunchers];
    data[MatchStat_HitsRocketLaunchers] = stats.weaponHits[WeaponCategory_RocketLaunchers];
    data[MatchStat_ShotsGrenadeLaunchers] = stats.weaponShots[WeaponCategory_GrenadeLaunchers];
    data[MatchStat_HitsGrenadeLaunchers] = stats.weaponHits[WeaponCategory_GrenadeLaunchers];
    data[MatchStat_ShotsStickyLaunchers] = stats.weaponShots[WeaponCategory_StickyLaunchers];
    data[MatchStat_HitsStickyLaunchers] = stats.weaponHits[WeaponCategory_StickyLaunchers];
    data[MatchStat_ShotsSnipers] = stats.weaponShots[WeaponCategory_Snipers];
    data[MatchStat_HitsSnipers] = stats.weaponHits[WeaponCategory_Snipers];
    data[MatchStat_ShotsRevolvers] = stats.weaponShots[WeaponCategory_Revolvers];
    data[MatchStat_HitsRevolvers] = stats.weaponHits[WeaponCategory_Revolvers];
    data[MatchStat_BestStreak] = WT_ShouldLogMatchKillstreaks() ? stats.bestKillstreak : 0;
    data[MatchStat_BestUbersLife] = stats.bestUbersLife;
    data[MatchStat_IsAdmin] = stats.isAdmin ? 1 : 0;
}

int GetStatsPlaytimeAtTime(const WhaleStats stats, float engineNow)
{
    int playtime = stats.playtime;
    if (stats.connectTime > 0.0)
    {
        int delta = RoundToFloor(engineNow - stats.connectTime);
        if (delta > 0)
        {
            playtime += delta;
        }
    }
    return playtime;
}

void SnapshotFromStatsAtTime(const WhaleStats stats, int data[MATCH_STAT_COUNT], float engineNow)
{
    SnapshotFromStats(stats, data);
    data[MatchStat_Playtime] = GetStatsPlaytimeAtTime(stats, engineNow);
}

bool IsMatchLogRatePlausible(int amount, int playtime)
{
    if (amount < 0 || playtime < 0)
    {
        return false;
    }

    if (amount == 0)
    {
        return true;
    }

    if (playtime <= 0)
    {
        return false;
    }

    float perMinute = float(amount) * float(WT_SECONDS_PER_MINUTE) / float(playtime);
    return perMinute <= WT_MATCH_LOG_MAX_DAMAGE_PER_MINUTE;
}

bool IsValidMatchLogSnapshot(const int data[MATCH_STAT_COUNT])
{
    if (!IsMatchLogRatePlausible(data[MatchStat_Damage], data[MatchStat_Playtime]))
    {
        return false;
    }

    if (!IsMatchLogRatePlausible(data[MatchStat_DamageTaken], data[MatchStat_Playtime]))
    {
        return false;
    }

    return true;
}

void MergeSnapshotArrays(int base[MATCH_STAT_COUNT], const int delta[MATCH_STAT_COUNT])
{
    base[MatchStat_Kills] += delta[MatchStat_Kills];
    base[MatchStat_Deaths] += delta[MatchStat_Deaths];
    base[MatchStat_Assists] += delta[MatchStat_Assists];
    base[MatchStat_Damage] += delta[MatchStat_Damage];
    base[MatchStat_DamageTaken] += delta[MatchStat_DamageTaken];
    base[MatchStat_Healing] += delta[MatchStat_Healing];
    base[MatchStat_Headshots] += delta[MatchStat_Headshots];
    base[MatchStat_Backstabs] += delta[MatchStat_Backstabs];
    base[MatchStat_Ubers] += delta[MatchStat_Ubers];
    base[MatchStat_Playtime] += delta[MatchStat_Playtime];
    base[MatchStat_MedicDrops] += delta[MatchStat_MedicDrops];
    base[MatchStat_UberDrops] += delta[MatchStat_UberDrops];
    base[MatchStat_Airshots] += delta[MatchStat_Airshots];
    base[MatchStat_MarketGardenHits] += delta[MatchStat_MarketGardenHits];
    base[MatchStat_ShotsShotguns] += delta[MatchStat_ShotsShotguns];
    base[MatchStat_HitsShotguns] += delta[MatchStat_HitsShotguns];
    base[MatchStat_ShotsScatterguns] += delta[MatchStat_ShotsScatterguns];
    base[MatchStat_HitsScatterguns] += delta[MatchStat_HitsScatterguns];
    base[MatchStat_ShotsPistols] += delta[MatchStat_ShotsPistols];
    base[MatchStat_HitsPistols] += delta[MatchStat_HitsPistols];
    base[MatchStat_ShotsRocketLaunchers] += delta[MatchStat_ShotsRocketLaunchers];
    base[MatchStat_HitsRocketLaunchers] += delta[MatchStat_HitsRocketLaunchers];
    base[MatchStat_ShotsGrenadeLaunchers] += delta[MatchStat_ShotsGrenadeLaunchers];
    base[MatchStat_HitsGrenadeLaunchers] += delta[MatchStat_HitsGrenadeLaunchers];
    base[MatchStat_ShotsStickyLaunchers] += delta[MatchStat_ShotsStickyLaunchers];
    base[MatchStat_HitsStickyLaunchers] += delta[MatchStat_HitsStickyLaunchers];
    base[MatchStat_ShotsSnipers] += delta[MatchStat_ShotsSnipers];
    base[MatchStat_HitsSnipers] += delta[MatchStat_HitsSnipers];
    base[MatchStat_ShotsRevolvers] += delta[MatchStat_ShotsRevolvers];
    base[MatchStat_HitsRevolvers] += delta[MatchStat_HitsRevolvers];

    if (delta[MatchStat_BestStreak] > base[MatchStat_BestStreak])
    {
        base[MatchStat_BestStreak] = delta[MatchStat_BestStreak];
    }
    if (delta[MatchStat_BestUbersLife] > base[MatchStat_BestUbersLife])
    {
        base[MatchStat_BestUbersLife] = delta[MatchStat_BestUbersLife];
    }
    if (delta[MatchStat_IsAdmin] > base[MatchStat_IsAdmin])
    {
        base[MatchStat_IsAdmin] = delta[MatchStat_IsAdmin];
    }
}

void AppendSnapshotToStorage(const char[] steamId, const int data[MATCH_STAT_COUNT])
{
    if (!steamId[0])
        return;

    EnsureMatchStorage();

    int aggregate[MATCH_STAT_COUNT];
    bool hasExisting = g_DisconnectedStats.GetArray(steamId, aggregate, MATCH_STAT_COUNT);

    if (hasExisting)
    {
        MergeSnapshotArrays(aggregate, data);
    }
    else
    {
        for (int i = 0; i < MATCH_STAT_COUNT; i++)
        {
            aggregate[i] = data[i];
        }
    }

    g_DisconnectedStats.SetArray(steamId, aggregate, MATCH_STAT_COUNT);
}

bool ExtractSnapshotForSteamId(const char[] steamId, int data[MATCH_STAT_COUNT])
{
    if (!steamId[0])
        return false;

    EnsureMatchStorage();
    return g_DisconnectedStats.GetArray(steamId, data, MATCH_STAT_COUNT);
}

int CountValidMatchSnapshots(StringMapSnapshot snap)
{
    if (snap == null)
        return 0;

    int count = 0;
    for (int i = 0; i < snap.Length; i++)
    {
        char steamId[STEAMID64_LEN];
        snap.GetKey(i, steamId, sizeof(steamId));

        int data[MATCH_STAT_COUNT];
        if (ExtractSnapshotForSteamId(steamId, data) && IsValidMatchLogSnapshot(data))
        {
            count++;
        }
    }
    return count;
}

void RemoveSnapshotForSteamId(const char[] steamId)
{
    if (!steamId[0] || g_DisconnectedStats == null)
        return;

    g_DisconnectedStats.Remove(steamId);
}

void ApplySnapshotToStats(WhaleStats stats, const int data[MATCH_STAT_COUNT])
{
    stats.kills = data[MatchStat_Kills];
    stats.deaths = data[MatchStat_Deaths];
    stats.totalAssists = data[MatchStat_Assists];
    stats.totalDamage = data[MatchStat_Damage];
    stats.totalDamageTaken = data[MatchStat_DamageTaken];
    stats.totalHealing = data[MatchStat_Healing];
    stats.totalHeadshots = data[MatchStat_Headshots];
    stats.totalBackstabs = data[MatchStat_Backstabs];
    stats.totalUbers = data[MatchStat_Ubers];
    stats.playtime = data[MatchStat_Playtime];
    stats.totalMedicDrops = data[MatchStat_MedicDrops];
    stats.totalUberDrops = data[MatchStat_UberDrops];
    stats.totalAirshots = data[MatchStat_Airshots];
    stats.totalMarketGardenHits = data[MatchStat_MarketGardenHits];
    stats.weaponShots[WeaponCategory_Shotguns] = data[MatchStat_ShotsShotguns];
    stats.weaponHits[WeaponCategory_Shotguns] = data[MatchStat_HitsShotguns];
    stats.weaponShots[WeaponCategory_Scatterguns] = data[MatchStat_ShotsScatterguns];
    stats.weaponHits[WeaponCategory_Scatterguns] = data[MatchStat_HitsScatterguns];
    stats.weaponShots[WeaponCategory_Pistols] = data[MatchStat_ShotsPistols];
    stats.weaponHits[WeaponCategory_Pistols] = data[MatchStat_HitsPistols];
    stats.weaponShots[WeaponCategory_RocketLaunchers] = data[MatchStat_ShotsRocketLaunchers];
    stats.weaponHits[WeaponCategory_RocketLaunchers] = data[MatchStat_HitsRocketLaunchers];
    stats.weaponShots[WeaponCategory_GrenadeLaunchers] = data[MatchStat_ShotsGrenadeLaunchers];
    stats.weaponHits[WeaponCategory_GrenadeLaunchers] = data[MatchStat_HitsGrenadeLaunchers];
    stats.weaponShots[WeaponCategory_StickyLaunchers] = data[MatchStat_ShotsStickyLaunchers];
    stats.weaponHits[WeaponCategory_StickyLaunchers] = data[MatchStat_HitsStickyLaunchers];
    stats.weaponShots[WeaponCategory_Snipers] = data[MatchStat_ShotsSnipers];
    stats.weaponHits[WeaponCategory_Snipers] = data[MatchStat_HitsSnipers];
    stats.weaponShots[WeaponCategory_Revolvers] = data[MatchStat_ShotsRevolvers];
    stats.weaponHits[WeaponCategory_Revolvers] = data[MatchStat_HitsRevolvers];
    stats.bestKillstreak = data[MatchStat_BestStreak];
    stats.bestUbersLife = data[MatchStat_BestUbersLife];
    stats.isAdmin = data[MatchStat_IsAdmin] != 0;
    stats.loaded = true;
}

void BeginMatchTracking()
{
    if (!WhaleTracker_ShouldUseMatchLogs())
    {
        ClearCurrentMatchTracking();
        g_sLastFinalizedLogId[0] = '\0';
        return;
    }

    CleanupFinalizedLog();
    ResetMatchStorage();

    g_iMatchStartTime = GetTime();
    GetCurrentMap(g_sCurrentMap, sizeof(g_sCurrentMap));
    if (!g_sCurrentMap[0])
    {
        strcopy(g_sCurrentMap, sizeof(g_sCurrentMap), "unknown");
    }

    int randomPart = GetURandomInt() & 0xFFFF;
    Format(g_sCurrentLogId, sizeof(g_sCurrentLogId), "%d_%04X", g_iMatchStartTime, randomPart);

    g_bMatchFinalized = false;
}

void RefreshCurrentOnlineMapName()
{
    char rawName[128];
    g_sOnlineMapName[0] = '\0';
    if (GetFeatureStatus(FeatureType_Native, "DGM_CurrentNormalizedMap") == FeatureStatus_Available
        && DGM_CurrentNormalizedMap(rawName, sizeof(rawName)))
    {
        strcopy(g_sOnlineMapName, sizeof(g_sOnlineMapName), rawName);
        return;
    }

    GetCurrentMap(rawName, sizeof(rawName));
    if (!rawName[0])
    {
        strcopy(g_sOnlineMapName, sizeof(g_sOnlineMapName), "unknown");
        return;
    }

    if (GetFeatureStatus(FeatureType_Native, "DGM_NormalizeMapName") == FeatureStatus_Available)
    {
        DGM_NormalizeMapName(rawName, rawName, sizeof(rawName));
    }
    strcopy(g_sOnlineMapName, sizeof(g_sOnlineMapName), rawName[0] ? rawName : "unknown");
}

void RefreshHostAddress()
{
    if (g_hHostIpCvar == null)
    {
        g_hHostIpCvar = FindConVar("ip");
        if (g_hHostIpCvar == null)
        {
            g_hHostIpCvar = FindConVar("hostip");
        }
    }

    if (g_hHostIpCvar != null)
    {
        g_hHostIpCvar.GetString(g_sHostIp, sizeof(g_sHostIp));
    }
    else
    {
        g_sHostIp[0] = '\0';
    }

    if (!g_sHostIp[0])
    {
        strcopy(g_sHostIp, sizeof(g_sHostIp), "0.0.0.0");
    }

    if (g_hHostPortCvar == null)
    {
        g_hHostPortCvar = FindConVar("hostport");
    }
    g_iHostPort = (g_hHostPortCvar != null) ? g_hHostPortCvar.IntValue : 27015;

    RefreshPublicHostIp();
}

bool WhaleTracker_ShouldUseMatchLogs()
{
    return (g_hEnableMatchLogs != null && g_hEnableMatchLogs.BoolValue);
}

bool WhaleTracker_RunSchemaQuery(const char[] query, const char[] description)
{
    if (SQLFastQuerySync(query))
    {
        return true;
    }

    char error[256];
    GetSyncDatabaseError(error, sizeof(error));
    LogError("[WhaleTracker] Failed to ensure %s: %s", description, error);
    return false;
}

void WhaleTracker_EnsureAdminStatusColumns()
{
    if (!g_bDatabaseReady || g_hSyncDatabase == null)
    {
        return;
    }

    WhaleTracker_RunSchemaQuery("ALTER TABLE whaletracker ADD COLUMN IF NOT EXISTS is_admin TINYINT(1) DEFAULT 0", "whaletracker.is_admin");
    WhaleTracker_RunSchemaQuery("ALTER TABLE whaletracker ADD COLUMN IF NOT EXISTS country VARCHAR(64) NOT NULL DEFAULT ''", "whaletracker.country");
    WhaleTracker_RunSchemaQuery("ALTER TABLE whaletracker ADD COLUMN IF NOT EXISTS show_country TINYINT(1) NOT NULL DEFAULT 0", "whaletracker.show_country");
    WhaleTracker_RunSchemaQuery("ALTER TABLE whaletracker_online ADD COLUMN IF NOT EXISTS is_admin TINYINT(1) DEFAULT 0", "whaletracker_online.is_admin");
    WhaleTracker_RunSchemaQuery("ALTER TABLE whaletracker_log_players ADD COLUMN IF NOT EXISTS is_admin TINYINT DEFAULT 0", "whaletracker_log_players.is_admin");
}

void RefreshPublicHostIp()
{
    g_sPublicHostIp[0] = '\0';
    if (GetFeatureStatus(FeatureType_Native, "SteamWorks_GetPublicIP") == FeatureStatus_Available)
    {
        int addr[4];
        if (SteamWorks_GetPublicIP(addr))
        {
            Format(g_sPublicHostIp, sizeof(g_sPublicHostIp), "%d.%d.%d.%d", addr[0], addr[1], addr[2], addr[3]);
        }
    }

    RefreshHostCity();
}

void RefreshHostCity()
{
    char sourceIp[64];
    if (g_sPublicHostIp[0])
    {
        strcopy(sourceIp, sizeof(sourceIp), g_sPublicHostIp);
    }
    else if (g_sHostIp[0])
    {
        strcopy(sourceIp, sizeof(sourceIp), g_sHostIp);
    }
    else
    {
        sourceIp[0] = '\0';
    }

    if (!sourceIp[0])
    {
        strcopy(g_sHostCity, sizeof(g_sHostCity), "Unknown");
        g_sHostCountry[0] = '\0';
        g_sHostCountryLower[0] = '\0';
        return;
    }

    char city[64];
    if (!GeoipCity(sourceIp, city, sizeof(city)) || !city[0])
    {
        strcopy(g_sHostCity, sizeof(g_sHostCity), "Unknown");
    }
    else
    {
        strcopy(g_sHostCity, sizeof(g_sHostCity), city);
    }

    char countryCode[3];
    if (!GeoipCode2(sourceIp, countryCode) || !countryCode[0])
    {
        g_sHostCountry[0] = '\0';
        g_sHostCountryLower[0] = '\0';
    }
    else
    {
        strcopy(g_sHostCountry, sizeof(g_sHostCountry), countryCode);
        CopyLowercase(countryCode, g_sHostCountryLower, sizeof(g_sHostCountryLower));
    }
}

public void ConVarChanged_ServerFlags(ConVar convar, const char[] oldValue, const char[] newValue)
{
    RefreshServerFlags();
}

void RefreshServerFlags()
{
    if (g_hServerFlags == null)
    {
        g_hServerFlags = CreateConVar("sm_serverflags", "", "Additional flag codes (comma-separated) appended to the server card", FCVAR_NOTIFY);
        g_hServerFlags.AddChangeHook(ConVarChanged_ServerFlags);
    }
    g_hServerFlags.GetString(g_sServerFlags, sizeof(g_sServerFlags));
    TrimString(g_sServerFlags);
}

void InsertPlayerLogRecord(const int data[MATCH_STAT_COUNT], const char[] steamId, const char[] name, int timestamp, bool forceSync)
{
    if (!WhaleTracker_ShouldUseMatchLogs())
        return;

    if (!g_sCurrentLogId[0] || steamId[0] == '\0')
        return;

    if (!IsValidMatchLogSnapshot(data))
        return;

    char escapedName[256];
    EscapeSqlString(name, escapedName, sizeof(escapedName));

    char query[SAVE_QUERY_MAXLEN];
    Format(query, sizeof(query),
        "INSERT INTO whaletracker_log_players "
        ... "(log_id, steamid, personaname, kills, deaths, assists, damage, damage_taken, healing, headshots, backstabs, total_ubers, playtime, medic_drops, uber_drops, airshots, marketGardenHits, "
        ... "shots_shotguns, hits_shotguns, shots_scatterguns, hits_scatterguns, shots_pistols, hits_pistols, shots_rocketlaunchers, hits_rocketlaunchers, shots_grenadelaunchers, hits_grenadelaunchers, shots_stickylaunchers, hits_stickylaunchers, shots_snipers, hits_snipers, shots_revolvers, hits_revolvers, "
        ... "best_streak, best_ubers_life, is_admin, last_updated) "
        ... "VALUES ('%s', '%s', '%s', %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, "
        ... "%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, "
        ... "%d, %d, %d, %d) "
        ... "ON DUPLICATE KEY UPDATE "
        ... "personaname = VALUES(personaname), "
        ... "kills = VALUES(kills), "
        ... "deaths = VALUES(deaths), "
        ... "assists = VALUES(assists), "
        ... "damage = VALUES(damage), "
        ... "damage_taken = VALUES(damage_taken), "
        ... "healing = VALUES(healing), "
        ... "headshots = VALUES(headshots), "
        ... "backstabs = VALUES(backstabs), "
        ... "total_ubers = VALUES(total_ubers), "
        ... "playtime = VALUES(playtime), "
        ... "medic_drops = VALUES(medic_drops), "
        ... "uber_drops = VALUES(uber_drops), "
        ... "airshots = VALUES(airshots), "
        ... "marketGardenHits = VALUES(marketGardenHits), "
        ... "shots_shotguns = VALUES(shots_shotguns), "
        ... "hits_shotguns = VALUES(hits_shotguns), "
        ... "shots_scatterguns = VALUES(shots_scatterguns), "
        ... "hits_scatterguns = VALUES(hits_scatterguns), "
        ... "shots_pistols = VALUES(shots_pistols), "
        ... "hits_pistols = VALUES(hits_pistols), "
        ... "shots_rocketlaunchers = VALUES(shots_rocketlaunchers), "
        ... "hits_rocketlaunchers = VALUES(hits_rocketlaunchers), "
        ... "shots_grenadelaunchers = VALUES(shots_grenadelaunchers), "
        ... "hits_grenadelaunchers = VALUES(hits_grenadelaunchers), "
        ... "shots_stickylaunchers = VALUES(shots_stickylaunchers), "
        ... "hits_stickylaunchers = VALUES(hits_stickylaunchers), "
        ... "shots_snipers = VALUES(shots_snipers), "
        ... "hits_snipers = VALUES(hits_snipers), "
        ... "shots_revolvers = VALUES(shots_revolvers), "
        ... "hits_revolvers = VALUES(hits_revolvers), "
        ... "best_streak = VALUES(best_streak), "
        ... "best_ubers_life = VALUES(best_ubers_life), "
        ... "is_admin = VALUES(is_admin), "
        ... "last_updated = VALUES(last_updated)",
        g_sCurrentLogId,
        steamId,
        escapedName,
        data[MatchStat_Kills],
        data[MatchStat_Deaths],
        data[MatchStat_Assists],
        data[MatchStat_Damage],
        data[MatchStat_DamageTaken],
        data[MatchStat_Healing],
        data[MatchStat_Headshots],
        data[MatchStat_Backstabs],
        data[MatchStat_Ubers],
        data[MatchStat_Playtime],
        data[MatchStat_MedicDrops],
        data[MatchStat_UberDrops],
        data[MatchStat_Airshots],
        data[MatchStat_MarketGardenHits],
        data[MatchStat_ShotsShotguns],
        data[MatchStat_HitsShotguns],
        data[MatchStat_ShotsScatterguns],
        data[MatchStat_HitsScatterguns],
        data[MatchStat_ShotsPistols],
        data[MatchStat_HitsPistols],
        data[MatchStat_ShotsRocketLaunchers],
        data[MatchStat_HitsRocketLaunchers],
        data[MatchStat_ShotsGrenadeLaunchers],
        data[MatchStat_HitsGrenadeLaunchers],
        data[MatchStat_ShotsStickyLaunchers],
        data[MatchStat_HitsStickyLaunchers],
        data[MatchStat_ShotsSnipers],
        data[MatchStat_HitsSnipers],
        data[MatchStat_ShotsRevolvers],
        data[MatchStat_HitsRevolvers],
        data[MatchStat_BestStreak],
        data[MatchStat_BestUbersLife],
        data[MatchStat_IsAdmin],
        timestamp);

    QueueSaveQuery(query, 0, forceSync);
}

void NormalizeGamemodeForMap(const char[] mapName, char[] gamemode, int gamemodeLen)
{
    if (!mapName[0])
    {
        return;
    }

    char gamemodeKey[32];
    if (GetFeatureStatus(FeatureType_Native, "DGM_GetGameModeKeyForMap") == FeatureStatus_Available
        && DGM_GetGameModeKeyForMap(mapName, gamemodeKey, sizeof(gamemodeKey)))
    {
        if (StrEqual(gamemodeKey, "ctf", false))
        {
            strcopy(gamemode, gamemodeLen, "Capture The Flag");
            return;
        }

        if (StrEqual(gamemodeKey, "cp", false))
        {
            strcopy(gamemode, gamemodeLen, "Control Point");
            return;
        }
    }

    if (StrContains(mapName, "ctf_", false) == 0)
    {
        strcopy(gamemode, gamemodeLen, "Capture The Flag");
        return;
    }

    if (StrContains(mapName, "cp_", false) == 0)
    {
        strcopy(gamemode, gamemodeLen, "Control Point");
        return;
    }
}

bool WhaleTracker_GetDgmGameMode(char[] gamemode, int gamemodeLen)
{
    if (gamemodeLen <= 0)
    {
        return false;
    }

    gamemode[0] = '\0';
    if (GetFeatureStatus(FeatureType_Native, "DGM_GetGameMode") == FeatureStatus_Available
        && DGM_GetGameMode(gamemode, gamemodeLen)
        && gamemode[0])
    {
        return true;
    }
    strcopy(gamemode, gamemodeLen, "Unknown");
    return false;
}

void WhaleTracker_EnsureRoundStatisticsTable()
{
    if (!g_bDatabaseReady || g_hSyncDatabase == null)
    {
        return;
    }

    char query[SAVE_QUERY_MAXLEN];
    FormatEx(query, sizeof(query),
        "CREATE TABLE IF NOT EXISTS whaletracker_round_statistics_events ("
        ... "id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,"
        ... "recorded_at INT NOT NULL,"
        ... "host_port INT NOT NULL DEFAULT 0,"
        ... "map_name VARCHAR(128) NOT NULL DEFAULT '',"
        ... "gamemode VARCHAR(64) NOT NULL DEFAULT '',"
        ... "winning_team TINYINT NOT NULL DEFAULT 0,"
        ... "winning_team_name VARCHAR(16) NOT NULL DEFAULT '',"
        ... "losing_team TINYINT NOT NULL DEFAULT 0,"
        ... "losing_team_name VARCHAR(16) NOT NULL DEFAULT '',"
        ... "winning_steamids TEXT NOT NULL,"
        ... "losing_steamids TEXT NOT NULL,"
        ... "winner_count INT NOT NULL DEFAULT 0,"
        ... "loser_count INT NOT NULL DEFAULT 0,"
        ... "PRIMARY KEY (id),"
        ... "KEY idx_recorded_at (recorded_at),"
        ... "KEY idx_gamemode (gamemode),"
        ... "KEY idx_winning_team (winning_team),"
        ... "KEY idx_host_map_time (host_port, map_name, recorded_at)"
        ... ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    WhaleTracker_RunSchemaQuery(query, "round statistics table");
}

int WhaleTracker_GetCurrentPlayerCount()
{
    if (GetFeatureStatus(FeatureType_Native, "DGM_RealPlayerCount") == FeatureStatus_Available)
    {
        return DGM_RealPlayerCount();
    }

    return GetClientCount(false);
}

int WhaleTracker_GetOnlinePlayerCount()
{
    return GetClientCount(false);
}

int WhaleTracker_GetCurrentServerCapacity()
{
    if (GetFeatureStatus(FeatureType_Native, "DGM_GetServerCapacity") == FeatureStatus_Available)
    {
        int capacity = DGM_GetServerCapacity();
        if (capacity > 0)
        {
            return capacity;
        }
    }

    int visibleMax = GetMaxHumanPlayers();
    if (g_hVisibleMaxPlayers != null)
    {
        int conVarValue = GetConVarInt(g_hVisibleMaxPlayers);
        if (conVarValue > 0 && visibleMax > conVarValue)
        {
            visibleMax = conVarValue;
        }
    }

    return visibleMax;
}

void WhaleTracker_GetTeamName(int team, char[] buffer, int maxlen)
{
    if (team == 2)
    {
        strcopy(buffer, maxlen, "RED");
        return;
    }

    if (team == 3)
    {
        strcopy(buffer, maxlen, "BLU");
        return;
    }

    strcopy(buffer, maxlen, "Unknown");
}

bool WhaleTracker_GetClientSteamId64(int client, char[] buffer, int maxlen)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
    {
        return false;
    }

    EnsureClientSteamId(client);
    if (g_Stats[client].steamId[0])
    {
        strcopy(buffer, maxlen, g_Stats[client].steamId);
        return true;
    }

    return GetClientAuthId(client, AuthId_SteamID64, buffer, maxlen);
}

void WhaleTracker_BuildTeamSteamIdList(int team, char[] buffer, int maxlen, int &count)
{
    buffer[0] = '\0';
    count = 0;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client) || GetClientTeam(client) != team)
        {
            continue;
        }

        char steamId[STEAMID64_LEN];
        if (!WhaleTracker_GetClientSteamId64(client, steamId, sizeof(steamId)))
        {
            continue;
        }

        if (buffer[0])
        {
            StrCat(buffer, maxlen, ",");
        }
        StrCat(buffer, maxlen, steamId);
        count++;
    }
}

void WhaleTracker_RecordRoundStatistics(Event event)
{
    if (!g_bDatabaseReady || g_hDatabase == null)
    {
        return;
    }

    int winningTeam = event.GetInt("team");
    if (winningTeam != 2 && winningTeam != 3)
    {
        return;
    }

    int losingTeam = (winningTeam == 2) ? 3 : 2;

    char winningSteamIds[1024];
    char losingSteamIds[1024];
    int winnerCount = 0;
    int loserCount = 0;
    WhaleTracker_BuildTeamSteamIdList(winningTeam, winningSteamIds, sizeof(winningSteamIds), winnerCount);
    WhaleTracker_BuildTeamSteamIdList(losingTeam, losingSteamIds, sizeof(losingSteamIds), loserCount);

    char mapName[128];
    strcopy(mapName, sizeof(mapName), g_sCurrentMap);
    if (!mapName[0])
    {
        GetCurrentMap(mapName, sizeof(mapName));
    }
    if (!mapName[0])
    {
        strcopy(mapName, sizeof(mapName), "unknown");
    }

    char gamemode[64] = "Unknown";
    WhaleTracker_GetDgmGameMode(gamemode, sizeof(gamemode));
    NormalizeGamemodeForMap(mapName, gamemode, sizeof(gamemode));

    char winningTeamName[16];
    char losingTeamName[16];
    WhaleTracker_GetTeamName(winningTeam, winningTeamName, sizeof(winningTeamName));
    WhaleTracker_GetTeamName(losingTeam, losingTeamName, sizeof(losingTeamName));

    char escapedMap[256];
    char escapedMode[128];
    char escapedWinningSteamIds[2048];
    char escapedLosingSteamIds[2048];
    EscapeSqlString(mapName, escapedMap, sizeof(escapedMap));
    EscapeSqlString(gamemode, escapedMode, sizeof(escapedMode));
    EscapeSqlString(winningSteamIds, escapedWinningSteamIds, sizeof(escapedWinningSteamIds));
    EscapeSqlString(losingSteamIds, escapedLosingSteamIds, sizeof(escapedLosingSteamIds));

    int timestamp = GetTime();
    char query[SAVE_QUERY_MAXLEN];
    Format(query, sizeof(query),
        "INSERT INTO whaletracker_round_statistics_events "
        ... "(recorded_at, host_port, map_name, gamemode, winning_team, winning_team_name, losing_team, losing_team_name, winning_steamids, losing_steamids, winner_count, loser_count) "
        ... "VALUES (%d, %d, '%s', '%s', %d, '%s', %d, '%s', '%s', '%s', %d, %d)",
        timestamp,
        g_iHostPort,
        escapedMap,
        escapedMode,
        winningTeam,
        winningTeamName,
        losingTeam,
        losingTeamName,
        escapedWinningSteamIds,
        escapedLosingSteamIds,
        winnerCount,
        loserCount);

    QueueSaveQuery(query, 0, false);
}

void InsertMatchLogRecord(int endTime, int duration, int participantCount, bool forceSync)
{
    if (!WhaleTracker_ShouldUseMatchLogs())
        return;

    if (!g_sCurrentLogId[0])
        return;

    char mapName[128];
    strcopy(mapName, sizeof(mapName), g_sCurrentMap);
    if (!mapName[0])
    {
        strcopy(mapName, sizeof(mapName), "unknown");
    }

    char escapedMap[128];
    EscapeSqlString(mapName, escapedMap, sizeof(escapedMap));

    char gamemode[64] = "Unknown";
    WhaleTracker_GetDgmGameMode(gamemode, sizeof(gamemode));
    NormalizeGamemodeForMap(mapName, gamemode, sizeof(gamemode));

    char escapedMode[64];
    EscapeSqlString(gamemode, escapedMode, sizeof(escapedMode));

    int started = (g_iMatchStartTime > 0) ? g_iMatchStartTime : endTime;

    char query[512];
    Format(query, sizeof(query),
        "INSERT INTO whaletracker_logs "
        ... "(log_id, map, gamemode, started_at, ended_at, duration, player_count, created_at, updated_at) "
        ... "VALUES ('%s', '%s', '%s', %d, %d, %d, %d, %d, %d) "
        ... "ON DUPLICATE KEY UPDATE "
        ... "map = VALUES(map), "
        ... "gamemode = VALUES(gamemode), "
        ... "started_at = VALUES(started_at), "
        ... "ended_at = VALUES(ended_at), "
        ... "duration = VALUES(duration), "
        ... "player_count = VALUES(player_count), "
        ... "updated_at = VALUES(updated_at)",
        g_sCurrentLogId,
        escapedMap,
        escapedMode,
        started,
        endTime,
        duration,
        participantCount,
        started,
        endTime);

    QueueSaveQuery(query, 0, forceSync);
}

void DeleteMatchLogRecord(const char[] logId, bool forceSync)
{
    if (!WhaleTracker_ShouldUseMatchLogs() || !logId[0] || !g_bDatabaseReady || g_hDatabase == null)
        return;

    char escaped[128];
    EscapeSqlString(logId, escaped, sizeof(escaped));

    char query[256];
    Format(query, sizeof(query), "DELETE FROM whaletracker_log_players WHERE log_id = '%s'", escaped);
    QueueSaveQuery(query, 0, forceSync);

    Format(query, sizeof(query), "DELETE FROM whaletracker_logs WHERE log_id = '%s'", escaped);
    QueueSaveQuery(query, 0, forceSync);
}

void FinalizeCurrentMatch(bool shuttingDown)
{
    if (!WhaleTracker_ShouldUseMatchLogs())
    {
        ClearCurrentMatchTracking();
        g_sLastFinalizedLogId[0] = '\0';
        return;
    }

    if (g_bMatchFinalized)
        return;

    EnsureMatchStorage();

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidClient(i) || IsFakeClient(i))
            continue;

        AccumulatePlaytime(i);
        EnsureClientSteamId(i);

        if (g_MapStats[i].steamId[0] == '\0')
            continue;

        int data[MATCH_STAT_COUNT];
        SnapshotFromStats(g_MapStats[i], data);
        AppendSnapshotToStorage(g_MapStats[i].steamId, data);

        char name[MAX_NAME_LENGTH];
        ResolveMatchPlayerName(i, g_MapStats[i].steamId, name, sizeof(name));
        RememberMatchPlayerName(g_MapStats[i].steamId, name);
    }

    if (!g_bDatabaseReady || g_hDatabase == null)
    {
        ClearCurrentMatchTracking();
        return;
    }

    StringMapSnapshot snap = g_DisconnectedStats != null ? g_DisconnectedStats.Snapshot() : null;
    if (snap == null || snap.Length == 0)
    {
        if (snap != null)
        {
            delete snap;
        }
        ClearCurrentMatchTracking();
        return;
    }

    int endTime = GetTime();
    int duration = (g_iMatchStartTime > 0) ? (endTime - g_iMatchStartTime) : 0;
    if (duration < 0)
    {
        duration = 0;
    }

    int participantCount = CountValidMatchSnapshots(snap);
    if (participantCount == 0)
    {
        delete snap;
        ClearCurrentMatchTracking();
        return;
    }

    if (participantCount == 1)
    {
        delete snap;
        DeleteMatchLogRecord(g_sCurrentLogId, shuttingDown);
        g_sLastFinalizedLogId[0] = '\0';
        ClearCurrentMatchTracking();
        return;
    }

    for (int i = 0; i < snap.Length; i++)
    {
        char steamId[STEAMID64_LEN];
        snap.GetKey(i, steamId, sizeof(steamId));

        int data[MATCH_STAT_COUNT];
        if (!ExtractSnapshotForSteamId(steamId, data))
            continue;

        char name[MAX_NAME_LENGTH];
        ResolveMatchPlayerName(0, steamId, name, sizeof(name));

        InsertPlayerLogRecord(data, steamId, name, endTime, shuttingDown);
    }

    delete snap;

    InsertMatchLogRecord(endTime, duration, participantCount, shuttingDown);

    if (g_sCurrentLogId[0])
    {
        strcopy(g_sLastFinalizedLogId, sizeof(g_sLastFinalizedLogId), g_sCurrentLogId);
    }
    ClearCurrentMatchTracking();
}

void EnsureClientSteamId(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client))
        return;

    char steamId[STEAMID64_LEN];
    if (GetClientAuthId(client, AuthId_SteamID64, steamId, sizeof(steamId)))
    {
        strcopy(g_Stats[client].steamId, sizeof(g_Stats[client].steamId), steamId);
        strcopy(g_MapStats[client].steamId, sizeof(g_MapStats[client].steamId), steamId);
        return;
    }

    // Keep map copy aligned if only fallback auth is currently available.
    if (g_Stats[client].steamId[0] != '\0')
    {
        strcopy(g_MapStats[client].steamId, sizeof(g_MapStats[client].steamId), g_Stats[client].steamId);
    }
}

void CleanupFinalizedLog()
{
    if (!WhaleTracker_ShouldUseMatchLogs())
    {
        g_sLastFinalizedLogId[0] = '\0';
        return;
    }

    if (!g_sLastFinalizedLogId[0] || !g_bDatabaseReady || g_hDatabase == null)
    {
        return;
    }

    char escaped[128];
    EscapeSqlString(g_sLastFinalizedLogId, escaped, sizeof(escaped));

    char query[SAVE_QUERY_MAXLEN];
    Format(query, sizeof(query),
        "DELETE FROM whaletracker_logs WHERE log_id = '%s' AND (SELECT COALESCE(SUM(damage), 0) FROM whaletracker_log_players WHERE log_id = '%s') < 500",
        escaped, escaped);
    QueueSaveQuery(query, 0, false);

    Format(query, sizeof(query),
        "DELETE FROM whaletracker_log_players WHERE log_id = '%s' AND NOT EXISTS (SELECT 1 FROM whaletracker_logs WHERE log_id = '%s')",
        escaped, escaped);
    QueueSaveQuery(query, 0, false);

    g_sLastFinalizedLogId[0] = '\0';
}

int GetClientTfClass(int client)
{
    TFClassType tfClassType = TF2_GetPlayerClass(client);
    int classId = view_as<int>(tfClassType);
    if (classId < CLASS_MIN || classId > CLASS_MAX)
    {
        return 0;
    }
    return classId;
}

void NormalizeWeaponClassname(char[] classname, int maxlen)
{
    if (StrEqual(classname, "tf_weapon_rocketlauncher_directhit", false)
        || StrEqual(classname, "tf_weapon_particle_cannon", false))
    {
        strcopy(classname, maxlen, "tf_projectile_rocket");
        return;
    }

    if (StrContains(classname, "tf_weapon_", false) == 0)
    {
        strcopy(classname, maxlen, classname[10]);
    }

    if (StrEqual(classname, "rocketlauncher", false) || StrEqual(classname, "rocketlauncher_directhit", false)
        || StrEqual(classname, "particle_cannon", false))
    {
        strcopy(classname, maxlen, "tf_projectile_rocket");
    }
    else if (StrEqual(classname, "pipebomblauncher", false))
    {
        strcopy(classname, maxlen, "tf_projectile_pipe_remote");
    }
    else if (StrEqual(classname, "grenadelauncher", false))
    {
        strcopy(classname, maxlen, "tf_projectile_pipe");
    }
    else if (StrEqual(classname, "crossbow", false))
    {
        strcopy(classname, maxlen, "tf_projectile_healing_bolt");
    }
}

int GetWeaponCategoryFromClassname(const char[] rawClassname)
{
    char classname[64];
    strcopy(classname, sizeof(classname), rawClassname);
    NormalizeWeaponClassname(classname, sizeof(classname));

    if (StrEqual(classname, "shotgun_soldier", false)
        || StrEqual(classname, "shotgun_primary", false)
        || StrEqual(classname, "shotgun_hwg", false)
        || StrEqual(classname, "shotgun_pyro", false))
    {
        return WeaponCategory_Shotguns;
    }

    if (StrEqual(classname, "scattergun", false)
        || StrEqual(classname, "pep_brawler_blaster", false)
        || StrEqual(classname, "handgun_scout_primary", false)
        || StrEqual(classname, "soda_popper", false))
    {
        return WeaponCategory_Scatterguns;
    }

    if (StrEqual(classname, "pistol_scout", false)
        || StrEqual(classname, "handgun_scout_secondary", false)
        || StrEqual(classname, "pistol", false))
    {
        return WeaponCategory_Pistols;
    }

    if (StrEqual(classname, "tf_projectile_rocket", false))
    {
        return WeaponCategory_RocketLaunchers;
    }

    if (StrEqual(classname, "tf_projectile_pipe", false))
    {
        return WeaponCategory_GrenadeLaunchers;
    }

    if (StrEqual(classname, "tf_projectile_pipe_remote", false))
    {
        return WeaponCategory_StickyLaunchers;
    }

    if (StrEqual(classname, "sniperrifle", false) || StrEqual(classname, "smg", false))
    {
        return StrEqual(classname, "sniperrifle", false) ? WeaponCategory_Snipers : WeaponCategory_Pistols;
    }

    if (StrEqual(classname, "revolver", false))
    {
        return WeaponCategory_Revolvers;
    }

    return WeaponCategory_None;
}

int ResolveAccuracyWeaponCategory(int weapon)
{
    if (weapon <= MaxClients || !IsValidEntity(weapon))
    {
        return 0;
    }

    if (!HasEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"))
    {
        return 0;
    }

    int defIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
    if (defIndex <= 0)
    {
        char classname[64];
        GetEntityClassname(weapon, classname, sizeof(classname));
        return GetWeaponCategoryFromClassname(classname);
    }

    int category = GetWeaponCategoryFromDefIndex(defIndex);
    if (category != view_as<int>(WeaponCategory_None))
    {
        return category;
    }

    char classname[64];
    GetEntityClassname(weapon, classname, sizeof(classname));
    return GetWeaponCategoryFromClassname(classname);
}

bool IsHitscanAccuracyCategory(int weaponCategory)
{
    return (weaponCategory == view_as<int>(WeaponCategory_Shotguns)
        || weaponCategory == view_as<int>(WeaponCategory_Scatterguns)
        || weaponCategory == view_as<int>(WeaponCategory_Pistols)
        || weaponCategory == view_as<int>(WeaponCategory_Snipers)
        || weaponCategory == view_as<int>(WeaponCategory_Revolvers));
}

bool ShouldDebounceAccuracyHit(int client, int weaponCategory)
{
    if (!IsHitscanAccuracyCategory(weaponCategory))
    {
        return false;
    }

    float now = GetEngineTime();
    float lastHit = g_fLastHitscanAccuracyHit[client][weaponCategory];
    if (lastHit > 0.0 && now - lastHit <= WT_GetHitscanAccuracyHitDebounce())
    {
        return true;
    }

    g_fLastHitscanAccuracyHit[client][weaponCategory] = now;
    return false;
}

bool TrackAccuracyEvent(int client, int weapon, bool isHit)
{
    if (!WhaleTracker_IsTrackingEnabled(client))
    {
        return false;
    }

    int weaponCategory = ResolveAccuracyWeaponCategory(weapon);
    if (weaponCategory <= view_as<int>(WeaponCategory_None) || weaponCategory > WEAPON_CATEGORY_COUNT)
    {
        return false;
    }

    int classId = GetClientTfClass(client);
    if (classId <= 0)
    {
        return false;
    }

    if (isHit)
    {
        if (ShouldDebounceAccuracyHit(client, weaponCategory))
        {
            return true;
        }

        g_Stats[client].weaponHits[weaponCategory]++;
        g_MapStats[client].weaponHits[weaponCategory]++;
    }
    else
    {
        g_Stats[client].weaponShots[weaponCategory]++;
        g_MapStats[client].weaponShots[weaponCategory]++;
    }

    MarkClientDirty(client);
    return true;
}

void IncrementHeadshotStats(WhaleStats stats)
{
    stats.totalHeadshots++;
}

void RecordHeadshotEvent(int client)
{
    if (!WhaleTracker_IsTrackingEnabled(client))
    {
        return;
    }

    IncrementHeadshotStats(g_Stats[client]);
    IncrementHeadshotStats(g_MapStats[client]);
    MarkClientDirty(client);
}



bool WhaleTracker_IsTrackingEnabled(int client)
{
    return (client > 0
        && client <= MaxClients
        && !IsFakeClient(client)
        && GetClientTeam(client) > 1
        && WhaleTracker_IsRoundRunning()
        && WhaleTracker_AreClientStatsReady(client)
        && g_bTrackEligible[client]);
}

bool WhaleTracker_CheckDamageGate(int client, int damage)
{
    if (client <= 0 || client > MaxClients || IsFakeClient(client) || GetClientTeam(client) <= 1 || !WhaleTracker_AreClientStatsReady(client))
    {
        return false;
    }
    g_iDamageGate[client] += damage;
    if (g_iDamageGate[client] >= WT_GetDamageTrackingGate())
    {
        g_bTrackEligible[client] = true;
        return true;
    }
    return false;
}

bool ApplyBonusPoints(int client, int points = 1, bool playSound = true, bool chatAlert = true, float randomChance = 1.0, const char[] type = "", int target = 0, float delay = 3.0, int perMap = 0)
{
    if (GetFeatureStatus(FeatureType_Native, "PointsStore_ApplyBonusPoints") != FeatureStatus_Available)
    {
        return false;
    }

    return PointsStore_ApplyBonusPoints(client, points, playSound, chatAlert, randomChance, type, target, delay, perMap);
}

bool ApplyBonusPointsSteamId(const char[] steamId64, int points = 1, bool playSound = true, bool chatAlert = true, const char[] type = "", int perMap = 0)
{
    if (GetFeatureStatus(FeatureType_Native, "PointsStore_ApplyBonusPointsSteamId") != FeatureStatus_Available)
    {
        return false;
    }

    return PointsStore_ApplyBonusPointsSteamId(steamId64, points, playSound, chatAlert, type, perMap);
}

void BuildWeaponAccuracySegment(const WhaleStats stats, char[] buffer, int maxlen)
{
    Format(buffer, maxlen,
        "%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d",
        stats.weaponShots[WeaponCategory_Shotguns],
        stats.weaponHits[WeaponCategory_Shotguns],
        stats.weaponShots[WeaponCategory_Scatterguns],
        stats.weaponHits[WeaponCategory_Scatterguns],
        stats.weaponShots[WeaponCategory_Pistols],
        stats.weaponHits[WeaponCategory_Pistols],
        stats.weaponShots[WeaponCategory_RocketLaunchers],
        stats.weaponHits[WeaponCategory_RocketLaunchers],
        stats.weaponShots[WeaponCategory_GrenadeLaunchers],
        stats.weaponHits[WeaponCategory_GrenadeLaunchers],
        stats.weaponShots[WeaponCategory_StickyLaunchers],
        stats.weaponHits[WeaponCategory_StickyLaunchers],
        stats.weaponShots[WeaponCategory_Snipers],
        stats.weaponHits[WeaponCategory_Snipers],
        stats.weaponShots[WeaponCategory_Revolvers],
        stats.weaponHits[WeaponCategory_Revolvers]);
}

void ResetLifeCounters(WhaleStats stats)
{
    stats.currentKillstreak = 0;
    stats.currentUbersLife = 0;
    stats.currentAssistsLife = 0;
}

void ApplyKillStats(WhaleStats stats, bool backstab, bool medicDrop)
{
    stats.kills++;

    stats.currentKillstreak++;


    if (stats.currentKillstreak > stats.bestKillstreak)
    {
        stats.bestKillstreak = stats.currentKillstreak;
    }
    if (backstab)
    {
        stats.totalBackstabs++;
    }
    if (medicDrop)
    {
        stats.totalMedicDrops++;
    }
}

void ApplyAssistStats(WhaleStats stats)
{
    stats.totalAssists++;
    stats.currentAssistsLife++;

}

void ApplyCumulativeDeathStats(WhaleStats stats, bool countDeath = true)
{
    if (countDeath)
    {
        stats.deaths++;
    }
    ResetLifeCounters(stats);
}

void ApplyDeathStats(WhaleStats stats)
{
    stats.deaths++;
    ResetLifeCounters(stats);
}

void ApplyHealingStats(WhaleStats stats, int amount)
{
    stats.totalHealing += amount;
}

void ApplyUberStats(WhaleStats stats)
{
    stats.totalUbers++;

    stats.currentUbersLife++;
    if (stats.currentUbersLife > stats.bestUbersLife)
    {
        stats.bestUbersLife = stats.currentUbersLife;
    }
}

bool AccumulatePlaytimeStruct(WhaleStats stats)
{
    if (stats.connectTime <= 0.0)
        return false;

    float session = GetEngineTime() - stats.connectTime;
    if (session >= 1.0)
    {
        int delta = RoundToFloor(session);
        stats.playtime += delta;
        stats.connectTime = GetEngineTime();
        return delta > 0;
    }
    return false;
}

bool AccumulatePlaytime(int client)
{
    if (client <= 0 || client > MaxClients)
        return false;

    bool changed = false;
    changed |= AccumulatePlaytimeStruct(g_Stats[client]);
    changed |= AccumulatePlaytimeStruct(g_MapStats[client]);
    return changed;
}

void MarkClientDirty(int client)
{
    if (client <= 0 || client > MaxClients)
        return;
    g_bStatsDirty[client] = true;
}

void RunSaveQuerySync(const char[] query, int userId)
{
    if (GetSyncDatabaseHandle() == null)
    {
        WhaleTracker_ScheduleReconnect(1.0);
        return;
    }

    if (!SQLFastQuerySync(query))
    {
        char error[256];
        GetSyncDatabaseError(error, sizeof(error));

        if (userId > 0)
        {
            LogError("[WhaleTracker] Failed to save stats synchronously (userid %d): %s", userId, error);
        }
        else
        {
            LogError("[WhaleTracker] Failed to save stats synchronously: %s", error);
        }

        if (WhaleTracker_IsConnectionLostError(error))
        {
            WhaleTracker_ScheduleReconnect(2.0);
        }
    }
}

void PumpSaveQueue()
{
    if (g_SaveQueue == null || g_hDatabase == null || !g_bDatabaseReady || g_bShuttingDown)
    {
        return;
    }

    while (g_PendingSaveQueries < MAX_CONCURRENT_SAVE_QUERIES && g_SaveQueue.Length > 0)
    {
        DataPack pack = view_as<DataPack>(g_SaveQueue.Get(0));
        g_SaveQueue.Erase(0);

        pack.Reset();
        int userId = pack.ReadCell();

        char query[SAVE_QUERY_MAXLEN];
        pack.ReadString(query, sizeof(query));

        delete pack;

        int slot = -1;
        for (int i = 0; i < MAX_CONCURRENT_SAVE_QUERIES; i++)
        {
            if (!g_SaveQuerySlotUsed[i])
            {
                slot = i;
                break;
            }
        }

        if (slot == -1)
        {
            RunSaveQuerySync(query, userId);
            continue;
        }

        strcopy(g_SaveQueryBuffers[slot], SAVE_QUERY_MAXLEN, query);
        g_SaveQueryUserIds[slot] = userId;
        g_SaveQuerySlotUsed[slot] = true;

        g_PendingSaveQueries++;
        g_hDatabase.Query(WhaleTracker_SaveCallback, g_SaveQueryBuffers[slot], slot);
    }
}

void RequestPumpSaveQueue()
{
    if (g_hDeferredSavePump == null || !g_hDeferredSavePump.BoolValue)
    {
        PumpSaveQueue();
        return;
    }

    if (g_bShuttingDown || g_hSavePumpTimer != null)
    {
        return;
    }

    g_hSavePumpTimer = CreateTimer(0.0, WhaleTracker_PumpSaveQueueTimer);
}

public Action WhaleTracker_PumpSaveQueueTimer(Handle timer, any data)
{
    if (timer == g_hSavePumpTimer)
    {
        g_hSavePumpTimer = null;
    }

    PumpSaveQueue();
    return Plugin_Stop;
}

void FlushSaveQueueSync()
{
    if (g_SaveQueue == null)
    {
        return;
    }

    while (g_SaveQueue.Length > 0)
    {
        DataPack pack = view_as<DataPack>(g_SaveQueue.Get(0));
        g_SaveQueue.Erase(0);

        pack.Reset();
        int userId = pack.ReadCell();

        char query[SAVE_QUERY_MAXLEN];
        pack.ReadString(query, sizeof(query));

        delete pack;

        RunSaveQuerySync(query, userId);
    }
}

void QueueSaveQuery(const char[] query, int userId, bool forceSync)
{
    if (WhaleTracker_RustQueueSqlWrite(query, userId, forceSync))
    {
        return;
    }

    if (forceSync || g_bShuttingDown)
    {
        RunSaveQuerySync(query, userId);
        return;
    }

    if (g_SaveQueue == null)
    {
        g_SaveQueue = new ArrayList();
    }

    DataPack pack = new DataPack();
    pack.WriteCell(userId);
    pack.WriteString(query);
    g_SaveQueue.Push(pack);

    RequestPumpSaveQueue();
}
