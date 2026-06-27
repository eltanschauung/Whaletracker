#define WT_COMMAND_QUICK_RECONNECT_DELAY 2.0

public Action Command_ShowStats(int client, int args)
{
    if (!IsValidClient(client) || IsFakeClient(client))
        return Plugin_Handled;

    int target = client;

    if (args >= 1)
    {
        char targetArg[64];
        GetCmdArgString(targetArg, sizeof(targetArg));
        TrimString(targetArg);

        if (targetArg[0])
        {
            int candidate = FindTarget(client, targetArg, true, false);
            if (candidate > 0 && IsValidClient(candidate) && !IsFakeClient(candidate))
            {
                target = candidate;
            }
            else
            {
                CPrintToChat(client, "{green}[WhaleTracker]{default} Could not find player '%s'.", targetArg);
                return Plugin_Handled;
            }
        }
    }

    SendMatchStatsMessage(client, target);
    return Plugin_Handled;
}

public Action Command_SaveAllStats(int client, int args)
{
    int saved = 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (SaveClientStats(i, false, true))
        {
            saved++;
        }
    }

    if (client > 0 && IsClientInGame(client))
    {
        CPrintToChat(client, "{green}[WhaleTracker]{default} Saved stats for %d player(s).", saved);
    }
    else
    {
        PrintToServer("[WhaleTracker] Saved stats for %d player(s).", saved);
    }

    return Plugin_Handled;
}

void PrintUnrankedWhalePointsMessage(int client, int target)
{
    char displayName[128];
    GetClientChatDisplayName(target, displayName, sizeof(displayName));

    if (g_Stats[target].loaded)
    {
        int combined = g_Stats[target].kills + g_Stats[target].deaths;
        int playtime = (g_Stats[target].playtime > 0) ? g_Stats[target].playtime : 0;
        float hours = float(playtime) / float(WT_SECONDS_PER_HOUR);
        float requiredHours = float(WT_GetRankMinPlaytimeSeconds()) / float(WT_SECONDS_PER_HOUR);
        CPrintToChatEx(client, target, "{green}[WhaleTracker]{default} %s{default} is unranked until Kills + Deaths reaches at least %d and playtime reaches %.2f hours (current: %d K+D, %.2f hours).", displayName, WT_GetRankMinKdSum(), requiredHours, combined, hours);
        return;
    }

    CPrintToChatEx(client, target, "{green}[WhaleTracker]{default} %s{default} is currently unranked.", displayName);
}

void PrintLiveWhalePointsMessage(int client, int target, bool broadcast, bool showHints, int points, int rank, bool hasRank)
{
    char displayName[128];
    GetClientChatDisplayName(target, displayName, sizeof(displayName));

    if (broadcast)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientInGame(i))
            {
                continue;
            }

            if (hasRank && rank > 0)
            {
                CPrintToChatEx(i, target, "{gold}[Whaletracker]{default} %s{default}'s Points: %d, Rank #%d", displayName, points, rank);
            }
            else
            {
                CPrintToChatEx(i, target, "{gold}[Whaletracker]{default} %s{default}'s Points: %d", displayName, points);
            }
        }
    }
    else
    {
        if (hasRank && rank > 0)
        {
            CPrintToChatEx(client, target, "{gold}[Whaletracker]{default} %s{default}'s Points: %d, Rank #%d", displayName, points, rank);
        }
        else
        {
            CPrintToChatEx(client, target, "{gold}[Whaletracker]{default} %s{default}'s Points: %d", displayName, points);
        }
    }

    if (!hasRank)
    {
        CPrintToChat(client, "{green}[WhaleTracker]{default} Live rank unavailable right now.");
    }

    if (g_Stats[target].loaded)
    {
        int lifetimeKills = g_Stats[target].kills;
        int lifetimeDeaths = g_Stats[target].deaths;
        float lifetimeKd = (lifetimeDeaths > 0) ? float(lifetimeKills) / float(lifetimeDeaths) : float(lifetimeKills);
        CPrintToChat(client, "Kill/Death ratio: %.2f", lifetimeKd);
    }

    if (showHints)
    {
        CPrintToChat(client, "Use {gold}!ranks{default} to view the leaderboard;");
        CPrintToChat(client, "Use {gold}!calc{default} to view how this is calculated!");
    }
}

public Action Command_ShowPointsCalculation(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
    {
        return Plugin_Handled;
    }

    CPrintToChat(client, "Score: {lightgreen}1000 * confidence * (5 * combat + pressure + support)");
    CPrintToChat(client, "Combat: {lightgreen}(kills + assists * 0.35) / (deaths + 20)");
    CPrintToChat(client, "Pressure: {lightgreen}ln(1 + damage / (150 * eng))");
    CPrintToChat(client, "Support: {lightgreen}0.60 * ln(1 + healing / (100 * eng)) + 0.90 * ln(1 + 60 * ubers / eng)");
    CPrintToChat(client, "Confidence: {axis}sqrt(eng / (eng + 400)) * (hours / (hours + 20))");
    CPrintToChat(client, "Where {lightgreen}eng = kills + deaths{default} and {lightgreen}hours = playtime / 3600");
    return Plugin_Handled;
}

void QueryLiveWhalePointsRank(int client, int target, bool broadcast, bool showHints, int points)
{
    if (!g_bDatabaseReady || g_hDatabase == null)
    {
        PrintLiveWhalePointsMessage(client, target, broadcast, showHints, points, 0, false);
        return;
    }

    EnsureClientSteamId(target);
    if (g_Stats[target].steamId[0] == '\0')
    {
        PrintLiveWhalePointsMessage(client, target, broadcast, showHints, points, 0, false);
        return;
    }

    char escapedSteamId[STEAMID64_LEN * 2];
    EscapeSqlString(g_Stats[target].steamId, escapedSteamId, sizeof(escapedSteamId));

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(GetClientUserId(target));
    pack.WriteCell(broadcast ? 1 : 0);
    pack.WriteCell(showHints ? 1 : 0);
    pack.WriteCell(points);

    char query[6144];
    Format(query, sizeof(query),
        "SELECT 1 + COUNT(*) "
        ... "FROM whaletracker "
        ... "WHERE ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) >= %d "
        ... "AND (CASE WHEN playtime > 0 THEN playtime ELSE 0 END) >= %d "
        ... "AND (%s > %d OR (%s = %d AND steamid < '%s'))",
        WT_GetRankMinKdSum(),
        WT_GetRankMinPlaytimeSeconds(),
        WHALE_POINTS_SQL_EXPR,
        points,
        WHALE_POINTS_SQL_EXPR,
        points,
        escapedSteamId);
    g_hDatabase.Query(WhaleTracker_ShowLivePointsRankCallback, query, pack);
}

public void WhaleTracker_ShowLivePointsRankCallback(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    int target = GetClientOfUserId(pack.ReadCell());
    bool broadcast = (pack.ReadCell() != 0);
    bool showHints = (pack.ReadCell() != 0);
    int points = pack.ReadCell();
    delete pack;

    if (!IsValidClient(client) || !IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    if (!IsValidClient(target) || !IsClientInGame(target) || IsFakeClient(target))
    {
        CPrintToChat(client, "{green}[WhaleTracker]{default} Target is no longer available.");
        return;
    }

    if (error[0] != '\0')
    {
        LogError("[WhaleTracker] Failed to query live points rank: %s", error);
        if (WhaleTracker_IsConnectionLostError(error))
        {
            WhaleTracker_ScheduleReconnect(WT_COMMAND_QUICK_RECONNECT_DELAY);
        }
        PrintLiveWhalePointsMessage(client, target, broadcast, showHints, points, 0, false);
        return;
    }

    int rank = 0;
    bool hasRank = false;
    if (results != null && results.FetchRow())
    {
        rank = results.FetchInt(0);
        hasRank = (rank > 0);
    }

    PrintLiveWhalePointsMessage(client, target, broadcast, showHints, points, rank, hasRank);
}

Action HandleShowPointsCommand(int client, int target, bool broadcast, bool showHints)
{
    EnsureClientSteamId(target);
    if (g_Stats[target].steamId[0] == '\0' || !g_Stats[target].loaded)
    {
        RequestClientStateLoads(target);
        CPrintToChat(client, "{green}[WhaleTracker]{default} %N stats are loading. Try again in a moment.", target);
        return Plugin_Handled;
    }

    int combined = g_Stats[target].kills + g_Stats[target].deaths;
    int playtime = (g_Stats[target].playtime > 0) ? g_Stats[target].playtime : 0;
    if (combined < WT_GetRankMinKdSum() || playtime < WT_GetRankMinPlaytimeSeconds())
    {
        PrintUnrankedWhalePointsMessage(client, target);
        return Plugin_Handled;
    }

    int points = GetWhalePointsForStats(g_Stats[target]);
    QueryLiveWhalePointsRank(client, target, broadcast, showHints, points);
    return Plugin_Handled;
}

public Action Command_ShowPoints(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
    {
        return Plugin_Handled;
    }
    int target = client;
    if (args >= 1)
    {
        char targetArg[64];
        GetCmdArgString(targetArg, sizeof(targetArg));
        TrimString(targetArg);
        if (targetArg[0])
        {
            int candidate = FindTarget(client, targetArg, true, false);
            if (candidate > 0 && IsValidClient(candidate) && !IsFakeClient(candidate))
            {
                target = candidate;
            }
            else
            {
                CPrintToChat(client, "{green}[WhaleTracker]{default} Could not find player '%s'.", targetArg);
                return Plugin_Handled;
            }
        }
    }
    return HandleShowPointsCommand(client, target, false, true);
}

public Action Command_ShowPointsMe(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
    {
        return Plugin_Handled;
    }
    int target = client;
    if (args >= 1)
    {
        char targetArg[64];
        GetCmdArgString(targetArg, sizeof(targetArg));
        TrimString(targetArg);
        if (targetArg[0])
        {
            int candidate = FindTarget(client, targetArg, true, false);
            if (candidate > 0 && IsValidClient(candidate) && !IsFakeClient(candidate))
            {
                target = candidate;
            }
            else
            {
                CPrintToChat(client, "{green}[WhaleTracker]{default} Could not find player '%s'.", targetArg);
                return Plugin_Handled;
            }
        }
    }
    return HandleShowPointsCommand(client, target, false, false);
}

public Action Command_ShowLastSeen(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
    {
        return Plugin_Handled;
    }

    if (!g_bDatabaseReady || g_hDatabase == null)
    {
        CPrintToChat(client, "{green}[WhaleTracker]{default} Database is not ready.");
        return Plugin_Handled;
    }

    char search[128];
    GetCmdArgString(search, sizeof(search));
    TrimString(search);

    if (search[0] == '\0')
    {
        CPrintToChat(client, "{green}[WhaleTracker]{default} Usage: !seen <name>");
        return Plugin_Handled;
    }

    char steamId[STEAMID64_LEN];
    char matchedName[256];
    if (!FindOnlineSeenMatch(search, steamId, sizeof(steamId), matchedName, sizeof(matchedName))
        && !FindSeenMatch(search, steamId, sizeof(steamId), matchedName, sizeof(matchedName)))
    {
        CPrintToChat(client, "{green}[WhaleTracker]{default} No cached name matched '%s'.", search);
        return Plugin_Handled;
    }

    int lastSeen = GetLastSeenForSteamId64(steamId);
    if (lastSeen <= 0)
    {
        CPrintToChat(client, "{green}[WhaleTracker]{default} %s{default} has no last seen data.", matchedName);
        return Plugin_Handled;
    }

    char timestamp[32];
    FormatTime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", lastSeen);
    CPrintToChat(client, "{green}[WhaleTracker]{default} %s{default} last seen: {gold}%s", matchedName, timestamp);

    int firstSeen = GetFirstSeenForSteamId64(steamId);
    if (firstSeen > 0)
    {
        char firstSeenDate[32];
        FormatTime(firstSeenDate, sizeof(firstSeenDate), "%Y-%m-%d", firstSeen);
        CPrintToChat(client, "{green}[WhaleTracker]{default} First seen: {gold}%s", firstSeenDate);
    }

    return Plugin_Handled;
}

public Action Command_ShowMarketGardens(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
    {
        return Plugin_Handled;
    }

    CPrintToChat(client, "{green}[WhaleTracker]{default} Market gardens: {gold}%d {default}| Airshots: {gold}%d", g_Stats[client].totalMarketGardenHits, g_Stats[client].totalAirshots);
    return Plugin_Handled;
}

public Action Command_SetFavoriteClass(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
    {
        return Plugin_Handled;
    }

    if (args >= 1)
    {
        char classArg[32];
        GetCmdArg(1, classArg, sizeof(classArg));
        TrimString(classArg);

        int favoriteClass = ParseFavoriteClassName(classArg);
        if (favoriteClass != CLASS_UNKNOWN)
        {
            SetFavoriteClassForClient(client, favoriteClass);
            return Plugin_Handled;
        }

        CPrintToChat(client, "{green}[WhaleTracker]{default} Unknown class '%s'.", classArg);
    }

    ShowFavoriteClassMenu(client);
    PrintCurrentFavoriteClass(client);
    return Plugin_Handled;
}

public Action Command_ToggleCountryVisibility(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
    {
        return Plugin_Handled;
    }

    if (args >= 1)
    {
        char countryArg[16];
        GetCmdArg(1, countryArg, sizeof(countryArg));
        TrimString(countryArg);
        SetCountryForClient(client, countryArg);
        return Plugin_Handled;
    }

    if (!g_bShowCountryLoaded[client])
    {
        RequestShowCountryLoad(client, true);
        return Plugin_Handled;
    }

    SetShowCountryForClient(client, !g_bShowCountryCache[client]);
    return Plugin_Handled;
}

public Action Command_ShowLeaderboard(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
    {
        return Plugin_Handled;
    }

    if (!g_bDatabaseReady || g_hDatabase == null)
    {
        CPrintToChat(client, "{green}[WhaleTracker]{default} Database is not ready.");
        return Plugin_Handled;
    }

    int page = 1;
    if (args >= 1)
    {
        char arg[16];
        GetCmdArg(1, arg, sizeof(arg));
        int parsed = StringToInt(arg);
        if (parsed > 0)
        {
            page = parsed;
        }
    }

    int offset = (page - 1) * WHALE_LEADERBOARD_PAGE_SIZE;

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(page);

    char query[1024];
    Format(query, sizeof(query),
        "SELECT pc.rank, pc.points, COALESCE(NULLIF(pr.newname,''), NULLIF(fs.last_name,''), NULLIF(w.cached_personaname,''), pc.steamid), COALESCE(NULLIF(pc.name_color,''), 'gold') "
        ... "FROM whaletracker_points_cache pc "
        ... "LEFT JOIN prename_rules pr ON pr.pattern COLLATE utf8mb4_uca1400_ai_ci = pc.steamid "
        ... "LEFT JOIN filters_steam_names fs ON fs.steamid64 = pc.steamid "
        ... "LEFT JOIN whaletracker w ON w.steamid = pc.steamid "
        ... "WHERE pc.rank > 0 "
        ... "ORDER BY pc.rank ASC "
        ... "LIMIT %d OFFSET %d",
        WHALE_LEADERBOARD_PAGE_SIZE,
        offset);
    g_hDatabase.Query(WhaleTracker_ShowLeaderboardCallback, query, pack);
    return Plugin_Handled;
}

public void WhaleTracker_ShowLeaderboardCallback(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    int page = pack.ReadCell();
    delete pack;

    if (!IsValidClient(client) || IsFakeClient(client))
    {
        return;
    }

    if (error[0] != '\0')
    {
        CPrintToChat(client, "{green}[WhaleTracker]{default} Failed to load leaderboard.");
        LogError("[WhaleTracker] Failed to load leaderboard: %s", error);
        return;
    }

    int rows = 0;
    while (results != null && results.FetchRow())
    {
        int rank = results.FetchInt(0);
        int points = results.FetchInt(1);

        char displayName[128];
        char colorTag[32];
        results.FetchString(2, displayName, sizeof(displayName));
        results.FetchString(3, colorTag, sizeof(colorTag));
        TrimString(displayName);
        TrimString(colorTag);

        if (displayName[0] == '\0')
        {
            strcopy(displayName, sizeof(displayName), "Unknown");
        }
        if (colorTag[0] == '\0')
        {
            strcopy(colorTag, sizeof(colorTag), "gold");
        }
        else if (StrEqual(colorTag, "teamcolor", false) || StrEqual(colorTag, "{teamcolor}", false))
        {
            strcopy(colorTag, sizeof(colorTag), "gold");
        }

        rows++;
        CPrintToChat(client, "#%d {%s}%s{default} %d", rank, colorTag, displayName, points);
    }

    if (rows == 0)
    {
        CPrintToChat(client, "{green}[WhaleTracker]{default} No leaderboard entries on page %d.", page);
        return;
    }

    CPrintToChat(client, "Use !{gold}ranks %d{default} to view the next 10 ranks!", page + 1);
}

void ShowFavoriteClassMenu(int client)
{
    Menu menu = new Menu(MenuHandler_FavoriteClass);
    menu.SetTitle("Select Favorite Class");
    menu.AddItem("1", "Scout");
    menu.AddItem("3", "Soldier");
    menu.AddItem("7", "Pyro");
    menu.AddItem("4", "Demoman");
    menu.AddItem("6", "Heavy");
    menu.AddItem("9", "Engineer");
    menu.AddItem("5", "Medic");
    menu.AddItem("2", "Sniper");
    menu.AddItem("8", "Spy");
    menu.Pagination = 5;
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_FavoriteClass(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select)
    {
        char info[8];
        menu.GetItem(item, info, sizeof(info));
        int favoriteClass = StringToInt(info);
        if (favoriteClass != CLASS_UNKNOWN)
        {
            SetFavoriteClassForClient(client, favoriteClass);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

int ParseFavoriteClassName(const char[] className)
{
    if (StrEqual(className, "scout", false))
    {
        return CLASS_SCOUT;
    }
    if (StrEqual(className, "soldier", false))
    {
        return CLASS_SOLDIER;
    }
    if (StrEqual(className, "pyro", false))
    {
        return CLASS_PYRO;
    }
    if (StrEqual(className, "demo", false) || StrEqual(className, "demoman", false))
    {
        return CLASS_DEMOMAN;
    }
    if (StrEqual(className, "heavy", false))
    {
        return CLASS_HEAVY;
    }
    if (StrEqual(className, "engi", false) || StrEqual(className, "engineer", false))
    {
        return CLASS_ENGINEER;
    }
    if (StrEqual(className, "medic", false))
    {
        return CLASS_MEDIC;
    }
    if (StrEqual(className, "sniper", false))
    {
        return CLASS_SNIPER;
    }
    if (StrEqual(className, "spy", false))
    {
        return CLASS_SPY;
    }

    return CLASS_UNKNOWN;
}

void ResetClientCommandCaches(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    g_bFavoriteClassLoaded[client] = false;
    g_bFavoriteClassPending[client] = false;
    g_iFavoriteClassCache[client] = CLASS_UNKNOWN;
    g_bShowCountryLoaded[client] = false;
    g_bShowCountryPending[client] = false;
    g_bShowCountryCache[client] = false;
    g_bShowCountryToggleAfterLoad[client] = false;
}

void GetClientChatDisplayName(int client, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    if (client > 0 && client <= MaxClients
        && IsClientConnected(client)
        && GetFeatureStatus(FeatureType_Native, "Filters_GetChatName") == FeatureStatus_Available
        && Filters_GetChatName(client, buffer, maxlen)
        && buffer[0] != '\0')
    {
        TrimString(buffer);
        return;
    }

    if (client > 0 && client <= MaxClients && IsClientConnected(client))
    {
        GetClientName(client, buffer, maxlen);
        TrimString(buffer);
    }
}

bool TryGetFiltersSteamIdColorTag(const char[] steamId, char[] colorTag, int maxlen)
{
    colorTag[0] = '\0';

    if (steamId[0] == '\0')
    {
        return false;
    }

    if (GetFeatureStatus(FeatureType_Native, "Filters_GetSteamIdColorTag") != FeatureStatus_Available)
    {
        return false;
    }

    if (!Filters_GetSteamIdColorTag(steamId, colorTag, maxlen))
    {
        return false;
    }

    TrimString(colorTag);
    return (colorTag[0] != '\0');
}

bool TryGetFiltersLastRecordedSteamName(const char[] steamId, char[] name, int maxlen)
{
    name[0] = '\0';

    if (steamId[0] == '\0')
    {
        return false;
    }

    if (GetFeatureStatus(FeatureType_Native, "Filters_GetLastRecordedSteamName") != FeatureStatus_Available)
    {
        return false;
    }

    if (!Filters_GetLastRecordedSteamName(steamId, name, maxlen))
    {
        return false;
    }

    TrimString(name);
    return (name[0] != '\0');
}

int GetSeenNameMatchRank(const char[] loweredSearch, const char[] name)
{
    if (loweredSearch[0] == '\0' || name[0] == '\0')
    {
        return 999;
    }

    char loweredName[256];
    CopyLowercase(name, loweredName, sizeof(loweredName));

    if (StrEqual(loweredName, loweredSearch, false))
    {
        return 0;
    }

    int matchIndex = StrContains(loweredName, loweredSearch, false);
    if (matchIndex == 0)
    {
        return 1;
    }

    if (matchIndex > 0)
    {
        return 2;
    }

    return 999;
}

bool FindOnlineSeenMatch(const char[] search, char[] steamId, int steamIdLen, char[] matchedName, int matchedNameLen)
{
    steamId[0] = '\0';
    matchedName[0] = '\0';

    if (search[0] == '\0')
    {
        return false;
    }

    char loweredSearch[128];
    CopyLowercase(search, loweredSearch, sizeof(loweredSearch));

    int bestClient = 0;
    int bestRank = 999;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientConnected(i) || IsFakeClient(i))
        {
            continue;
        }

        char clientSteamId[STEAMID64_LEN];
        if (!GetClientAuthId(i, AuthId_SteamID64, clientSteamId, sizeof(clientSteamId)))
        {
            continue;
        }

        int rank = 999;
        if (StrEqual(clientSteamId, search, false))
        {
            rank = 0;
        }
        else
        {
            char displayName[256];
            GetClientChatDisplayName(i, displayName, sizeof(displayName));
            rank = GetSeenNameMatchRank(loweredSearch, displayName);

            char clientName[256];
            GetClientName(i, clientName, sizeof(clientName));
            int clientNameRank = GetSeenNameMatchRank(loweredSearch, clientName);
            if (clientNameRank < rank)
            {
                rank = clientNameRank;
            }
        }

        if (rank < bestRank)
        {
            bestClient = i;
            bestRank = rank;
        }
    }

    if (bestClient <= 0 || bestRank >= 999)
    {
        return false;
    }

    GetClientAuthId(bestClient, AuthId_SteamID64, steamId, steamIdLen);
    GetClientChatDisplayName(bestClient, matchedName, matchedNameLen);
    if (matchedName[0] == '\0')
    {
        GetClientName(bestClient, matchedName, matchedNameLen);
    }
    TrimString(steamId);
    TrimString(matchedName);
    return (steamId[0] != '\0');
}

bool FindSeenMatch(const char[] search, char[] steamId, int steamIdLen, char[] matchedName, int matchedNameLen)
{
    steamId[0] = '\0';
    matchedName[0] = '\0';

    if (search[0] == '\0' || !g_bDatabaseReady || g_hDatabase == null)
    {
        return false;
    }

    char loweredSearch[128];
    CopyLowercase(search, loweredSearch, sizeof(loweredSearch));

    char escapedSearch[256];
    EscapeSqlString(loweredSearch, escapedSearch, sizeof(escapedSearch));

    char query[2048];
    Format(query, sizeof(query),
        "SELECT w.steamid, COALESCE(NULLIF(pr.newname, ''), NULLIF(fs.last_name, ''), NULLIF(w.cached_personaname, ''), w.steamid) "
        ... "FROM whaletracker w "
        ... "LEFT JOIN prename_rules pr ON pr.pattern COLLATE utf8mb4_uca1400_ai_ci = w.steamid "
        ... "LEFT JOIN filters_steam_names fs ON fs.steamid64 = w.steamid "
        ... "CROSS JOIN (SELECT '%s' AS term) q "
        ... "WHERE INSTR(COALESCE(w.cached_personaname_lower, ''), q.term) > 0 "
        ... "OR INSTR(LOWER(COALESCE(pr.newname, '')), q.term) > 0 "
        ... "OR INSTR(COALESCE(fs.last_name_lower, ''), q.term) > 0 "
        ... "OR INSTR(w.steamid, q.term) > 0 "
        ... "ORDER BY CASE "
        ... "WHEN w.steamid = q.term THEN 0 "
        ... "WHEN COALESCE(w.cached_personaname_lower, '') = q.term "
        ... "OR LOWER(COALESCE(pr.newname, '')) = q.term "
        ... "OR COALESCE(fs.last_name_lower, '') = q.term THEN 0 "
        ... "WHEN LEFT(COALESCE(w.cached_personaname_lower, ''), CHAR_LENGTH(q.term)) = q.term "
        ... "OR LEFT(LOWER(COALESCE(pr.newname, '')), CHAR_LENGTH(q.term)) = q.term "
        ... "OR LEFT(COALESCE(fs.last_name_lower, ''), CHAR_LENGTH(q.term)) = q.term THEN 1 "
        ... "ELSE 2 END, "
        ... "COALESCE(w.playtime, 0) DESC, COALESCE(w.last_seen, 0) DESC, w.steamid ASC "
        ... "LIMIT 1",
        escapedSearch);

    DBResultSet results = SQLQuerySync(query);
    if (results == null)
    {
        char error[256];
        GetSyncDatabaseError(error, sizeof(error));
        LogError("[WhaleTracker] Seen match query failed: %s", error);
        return false;
    }

    bool found = false;
    if (results.FetchRow())
    {
        results.FetchString(0, steamId, steamIdLen);
        results.FetchString(1, matchedName, matchedNameLen);
        TrimString(steamId);
        TrimString(matchedName);
        found = (steamId[0] != '\0');
    }

    delete results;
    return found;
}

void GetFavoriteClassDisplayName(int favoriteClass, char[] buffer, int maxlen)
{
    switch (favoriteClass)
    {
        case CLASS_SCOUT:
        {
            strcopy(buffer, maxlen, "Scout");
        }
        case CLASS_SOLDIER:
        {
            strcopy(buffer, maxlen, "Soldier");
        }
        case CLASS_PYRO:
        {
            strcopy(buffer, maxlen, "Pyro");
        }
        case CLASS_DEMOMAN:
        {
            strcopy(buffer, maxlen, "Demoman");
        }
        case CLASS_HEAVY:
        {
            strcopy(buffer, maxlen, "Heavy");
        }
        case CLASS_ENGINEER:
        {
            strcopy(buffer, maxlen, "Engineer");
        }
        case CLASS_MEDIC:
        {
            strcopy(buffer, maxlen, "Medic");
        }
        case CLASS_SNIPER:
        {
            strcopy(buffer, maxlen, "Sniper");
        }
        case CLASS_SPY:
        {
            strcopy(buffer, maxlen, "Spy");
        }
        default:
        {
            strcopy(buffer, maxlen, "Unknown");
        }
    }
}

void PrintCurrentFavoriteClass(int client)
{
    int favoriteClass = GetFavoriteClassForClient(client);
    if (favoriteClass == CLASS_UNKNOWN)
    {
        RequestFavoriteClassLoad(client, true);
        return;
    }

    char className[16];
    GetFavoriteClassDisplayName(favoriteClass, className, sizeof(className));
    CPrintToChat(client, "{green}[WhaleTracker]{default} Your favorite class: {gold}%s{default}", className);
}

int GetFavoriteClassForClient(int client)
{
    if (client <= 0 || client > MaxClients || !IsClientConnected(client))
    {
        return CLASS_UNKNOWN;
    }

    if (!g_bFavoriteClassLoaded[client])
    {
        return CLASS_UNKNOWN;
    }

    return g_iFavoriteClassCache[client];
}

void SetFavoriteClassForClient(int client, int favoriteClass)
{
    if (!g_bDatabaseReady || g_hDatabase == null)
    {
        CPrintToChat(client, "{green}[WhaleTracker]{default} Database is not ready.");
        return;
    }

    EnsureClientSteamId(client);
    if (g_Stats[client].steamId[0] == '\0')
    {
        CPrintToChat(client, "{green}[WhaleTracker]{default} Could not determine your SteamID yet.");
        return;
    }

    char escapedSteamId[STEAMID64_LEN * 2];
    EscapeSqlString(g_Stats[client].steamId, escapedSteamId, sizeof(escapedSteamId));

    int firstSeen = g_Stats[client].firstSeenTimestamp;
    if (firstSeen <= 0)
    {
        firstSeen = GetTime();
    }

    char query[512];
    Format(query, sizeof(query),
        "INSERT INTO whaletracker (steamid, first_seen, favorite_class) "
        ... "VALUES ('%s', %d, %d) "
        ... "ON DUPLICATE KEY UPDATE "
        ... "first_seen = LEAST(first_seen, VALUES(first_seen)), "
        ... "favorite_class = VALUES(favorite_class)",
        escapedSteamId,
        firstSeen,
        favoriteClass);
    QueueSaveQuery(query, GetClientUserId(client), false);
    g_iFavoriteClassCache[client] = favoriteClass;
    g_bFavoriteClassLoaded[client] = true;
    g_bFavoriteClassPending[client] = false;

    char className[16];
    GetFavoriteClassDisplayName(favoriteClass, className, sizeof(className));
    CPrintToChat(client, "{green}[WhaleTracker]{default} Your favorite class is now {gold}%s{default}!", className);
}

bool NormalizeCountryCodeArg(const char[] input, char[] countryCode, int maxlen)
{
    if (maxlen < 3 || input[0] == '\0' || input[1] == '\0' || input[2] != '\0')
    {
        return false;
    }

    for (int i = 0; i < 2; i++)
    {
        bool isAlpha = (input[i] >= 'A' && input[i] <= 'Z') || (input[i] >= 'a' && input[i] <= 'z');
        if (!isAlpha)
        {
            return false;
        }

        countryCode[i] = CharToLower(input[i]);
    }

    countryCode[2] = '\0';
    return true;
}

void SetCountryForClient(int client, const char[] countryArg)
{
    if (!g_bDatabaseReady || g_hDatabase == null)
    {
        CPrintToChat(client, "{green}[WhaleTracker]{default} Database is not ready.");
        return;
    }

    char countryCode[3];
    if (!NormalizeCountryCodeArg(countryArg, countryCode, sizeof(countryCode)))
    {
        CPrintToChat(client, "{green}[WhaleTracker]{default} Usage: {gold}!country CA{default}");
        return;
    }

    EnsureClientSteamId(client);
    if (g_Stats[client].steamId[0] == '\0')
    {
        CPrintToChat(client, "{green}[WhaleTracker]{default} Could not determine your SteamID yet.");
        return;
    }

    char escapedSteamId[STEAMID64_LEN * 2];
    EscapeSqlString(g_Stats[client].steamId, escapedSteamId, sizeof(escapedSteamId));

    char escapedCountryCode[16];
    EscapeSqlString(countryCode, escapedCountryCode, sizeof(escapedCountryCode));

    int firstSeen = g_Stats[client].firstSeenTimestamp;
    if (firstSeen <= 0)
    {
        firstSeen = GetTime();
    }

    char query[512];
    Format(query, sizeof(query),
        "INSERT INTO whaletracker (steamid, first_seen, country) "
        ... "VALUES ('%s', %d, '%s') "
        ... "ON DUPLICATE KEY UPDATE "
        ... "first_seen = LEAST(first_seen, VALUES(first_seen)), "
        ... "country = VALUES(country)",
        escapedSteamId,
        firstSeen,
        escapedCountryCode);
    QueueSaveQuery(query, GetClientUserId(client), false);

    CPrintToChat(client, "{green}[WhaleTracker]{default} Your country flag has been set to {gold}%s{default}. Use {gold}!country{default} to toggle visibility.", countryCode);
}

void RequestFavoriteClassLoad(int client, bool echoAfterLoad = false)
{
    if (!IsValidClient(client) || IsFakeClient(client) || !g_bDatabaseReady || g_hDatabase == null || g_bFavoriteClassPending[client])
    {
        return;
    }

    EnsureClientSteamId(client);
    if (g_Stats[client].steamId[0] == '\0')
    {
        return;
    }

    g_bFavoriteClassPending[client] = true;

    char escapedSteamId[STEAMID64_LEN * 2];
    EscapeSqlString(g_Stats[client].steamId, escapedSteamId, sizeof(escapedSteamId));

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(echoAfterLoad ? 1 : 0);

    char query[192];
    Format(query, sizeof(query),
        "SELECT COALESCE(favorite_class, 0) FROM whaletracker WHERE steamid = '%s' LIMIT 1",
        escapedSteamId);
    g_hDatabase.Query(WhaleTracker_FavoriteClassLoadCallback, query, pack);
}

public void WhaleTracker_FavoriteClassLoadCallback(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    bool echoAfterLoad = (pack.ReadCell() != 0);
    delete pack;

    if (!IsValidClient(client) || IsFakeClient(client))
    {
        return;
    }

    g_bFavoriteClassPending[client] = false;

    if (error[0] != '\0')
    {
        LogError("[WhaleTracker] Failed to load favorite class for %N: %s", client, error);
        return;
    }

    int favoriteClass = CLASS_UNKNOWN;
    if (results != null && results.FetchRow())
    {
        favoriteClass = results.FetchInt(0);
    }

    g_iFavoriteClassCache[client] = favoriteClass;
    g_bFavoriteClassLoaded[client] = true;

    if (echoAfterLoad && favoriteClass != CLASS_UNKNOWN)
    {
        char className[16];
        GetFavoriteClassDisplayName(favoriteClass, className, sizeof(className));
        CPrintToChat(client, "{green}[WhaleTracker]{default} Your favorite class: {gold}%s{default}", className);
    }
}

void SetShowCountryForClient(int client, bool showCountry)
{
    if (!g_bDatabaseReady || g_hDatabase == null)
    {
        CPrintToChat(client, "{green}[WhaleTracker]{default} Database is not ready.");
        return;
    }

    EnsureClientSteamId(client);
    if (g_Stats[client].steamId[0] == '\0')
    {
        CPrintToChat(client, "{green}[WhaleTracker]{default} Could not determine your SteamID yet.");
        return;
    }

    char escapedSteamId[STEAMID64_LEN * 2];
    EscapeSqlString(g_Stats[client].steamId, escapedSteamId, sizeof(escapedSteamId));

    char countryCode[3];
    WhaleTracker_GetClientCountryCode(client, countryCode, sizeof(countryCode));
    char escapedCountryCode[16];
    EscapeSqlString(countryCode, escapedCountryCode, sizeof(escapedCountryCode));

    int firstSeen = g_Stats[client].firstSeenTimestamp;
    if (firstSeen <= 0)
    {
        firstSeen = GetTime();
    }

    char query[512];
    Format(query, sizeof(query),
        "INSERT INTO whaletracker (steamid, first_seen, country, show_country) "
        ... "VALUES ('%s', %d, '%s', %d) "
        ... "ON DUPLICATE KEY UPDATE "
        ... "first_seen = LEAST(first_seen, VALUES(first_seen)), "
        ... "country = VALUES(country), "
        ... "show_country = VALUES(show_country)",
        escapedSteamId,
        firstSeen,
        escapedCountryCode,
        showCountry ? 1 : 0);
    QueueSaveQuery(query, GetClientUserId(client), false);

    g_bShowCountryCache[client] = showCountry;
    g_bShowCountryLoaded[client] = true;
    g_bShowCountryPending[client] = false;
    g_bShowCountryToggleAfterLoad[client] = false;

    if (showCountry)
    {
        CPrintToChat(client, "{green}[WhaleTracker]{default} Your country flag will become visible on {gold}kogasa.tf/stats{default} next time it updates. Use {gold}!country{default} again to disable.");
    }
    else
    {
        CPrintToChat(client, "{green}[WhaleTracker]{default} Your country flag will no longer be visible on {gold}kogasa.tf/stats{default} next time it updates.");
    }
}

void RequestShowCountryLoad(int client, bool toggleAfterLoad = false)
{
    if (!IsValidClient(client) || IsFakeClient(client) || !g_bDatabaseReady || g_hDatabase == null)
    {
        return;
    }

    if (toggleAfterLoad)
    {
        g_bShowCountryToggleAfterLoad[client] = true;
    }

    if (g_bShowCountryPending[client])
    {
        return;
    }

    EnsureClientSteamId(client);
    if (g_Stats[client].steamId[0] == '\0')
    {
        return;
    }

    g_bShowCountryPending[client] = true;

    char escapedSteamId[STEAMID64_LEN * 2];
    EscapeSqlString(g_Stats[client].steamId, escapedSteamId, sizeof(escapedSteamId));

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));

    char query[192];
    Format(query, sizeof(query),
        "SELECT COALESCE(show_country, 0) FROM whaletracker WHERE steamid = '%s' LIMIT 1",
        escapedSteamId);
    g_hDatabase.Query(WhaleTracker_ShowCountryLoadCallback, query, pack);
}

public void WhaleTracker_ShowCountryLoadCallback(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    delete pack;

    if (!IsValidClient(client) || IsFakeClient(client))
    {
        return;
    }

    g_bShowCountryPending[client] = false;

    if (error[0] != '\0')
    {
        LogError("[WhaleTracker] Failed to load show_country for %N: %s", client, error);
        return;
    }

    bool showCountry = false;
    if (results != null && results.FetchRow())
    {
        showCountry = results.FetchInt(0) != 0;
    }

    g_bShowCountryCache[client] = showCountry;
    g_bShowCountryLoaded[client] = true;

    if (g_bShowCountryToggleAfterLoad[client])
    {
        SetShowCountryForClient(client, !showCountry);
    }
}

void GetNameColorTagForSteamId(const char[] steamId, char[] colorTag, int maxlen)
{
    strcopy(colorTag, maxlen, "gold");

    if (!g_bDatabaseReady || g_hDatabase == null)
    {
        return;
    }

    if (steamId[0] == '\0')
    {
        return;
    }

    if (TryGetFiltersSteamIdColorTag(steamId, colorTag, maxlen))
    {
        return;
    }

    char escapedSteamId[STEAMID64_LEN * 2];
    EscapeSqlString(steamId, escapedSteamId, sizeof(escapedSteamId));

    char query[192];
    Format(query, sizeof(query),
        "SELECT color FROM filters_namecolors WHERE steamid = '%s' LIMIT 1",
        escapedSteamId);

    DBResultSet results = SQLQuerySync(query);
    if (results != null && SQL_HasResultSet(results) && results.FetchRow())
    {
        results.FetchString(0, colorTag, maxlen);
        TrimString(colorTag);
    }
    delete results;

    if (colorTag[0] != '\0')
    {
        return;
    }

    Format(query, sizeof(query),
        "SELECT name_color FROM whaletracker_points_cache WHERE steamid = '%s' LIMIT 1",
        escapedSteamId);

    results = SQLQuerySync(query);
    if (results != null && SQL_HasResultSet(results) && results.FetchRow())
    {
        results.FetchString(0, colorTag, maxlen);
        TrimString(colorTag);
    }
    delete results;
}

void UpdateWhalePointsCacheMetadata(const char[] steamId, const char[] knownColor = "", int userId = 0)
{
    if (!g_bDatabaseReady || g_hDatabase == null)
    {
        return;
    }

    if (steamId[0] == '\0')
    {
        return;
    }

    char escapedSteamId[STEAMID64_LEN * 2];
    EscapeSqlString(steamId, escapedSteamId, sizeof(escapedSteamId));

    char nameColor[32];
    if (knownColor[0] != '\0')
    {
        strcopy(nameColor, sizeof(nameColor), knownColor);
    }
    else
    {
        GetNameColorTagForSteamId(steamId, nameColor, sizeof(nameColor));
    }

    char escapedNameColor[64];
    EscapeSqlString(nameColor, escapedNameColor, sizeof(escapedNameColor));

    char query[1600];
    Format(query, sizeof(query),
        "INSERT INTO whaletracker_points_cache (steamid, name_color, updated_at) "
        ... "VALUES ('%s', '%s', %d) "
        ... "ON DUPLICATE KEY UPDATE "
        ... "name_color = VALUES(name_color), "
        ... "updated_at = VALUES(updated_at)",
        escapedSteamId,
        escapedNameColor,
        GetTime());
    QueueSaveQuery(query, userId, false);
}

void CacheWhalePointsOnDisconnect(int client)
{
    if (client <= 0 || client > MaxClients || IsFakeClient(client))
    {
        return;
    }

    EnsureClientSteamId(client);
    if (g_Stats[client].steamId[0] == '\0')
    {
        return;
    }

    char colorTag[32];
    GetNameColorTagForSteamId(g_Stats[client].steamId, colorTag, sizeof(colorTag));

    UpdateWhalePointsCacheMetadata(g_Stats[client].steamId, colorTag, GetClientUserId(client));
}

bool IsValidClient(int client)
{
    return client > 0 && client <= MaxClients && IsClientConnected(client);
}

void GetClientFiltersNameColorTag(int client, char[] colorTag, int maxlen)
{
    strcopy(colorTag, maxlen, "gold");

    if (client <= 0 || client > MaxClients || !IsClientConnected(client))
    {
        return;
    }

    EnsureClientSteamId(client);
    if (g_Stats[client].steamId[0] == '\0')
    {
        return;
    }

    if (TryGetFiltersSteamIdColorTag(g_Stats[client].steamId, colorTag, maxlen))
    {
        return;
    }
}

int GetWhalePointsForStats(const WhaleStats stats)
{
    int safeKills = (stats.kills > 0) ? stats.kills : 0;
    int safeDeaths = (stats.deaths > 0) ? stats.deaths : 0;
    int safeAssists = (stats.totalAssists > 0) ? stats.totalAssists : 0;
    int safeTotalUbers = (stats.totalUbers > 0) ? stats.totalUbers : 0;
    int safeDamage = (stats.totalDamage > 0) ? stats.totalDamage : 0;
    int safeHealing = (stats.totalHealing > 0) ? stats.totalHealing : 0;
    int safePlaytime = (stats.playtime > 0) ? stats.playtime : 0;
    int safeEngagement = safeKills + safeDeaths;

    if (safeEngagement < WT_GetRankMinKdSum() || safePlaytime < WT_GetRankMinPlaytimeSeconds())
    {
        return 0;
    }

    float engagement = float(safeEngagement);
    float hours = float(safePlaytime) / float(WT_SECONDS_PER_HOUR);
    float combat = (float(safeKills) + (float(safeAssists) * WT_WHALE_POINTS_ASSIST_WEIGHT)) / (float(safeDeaths) + WT_WHALE_POINTS_DEATH_OFFSET);
    float pressure = Logarithm(1.0 + (float(safeDamage) / (WT_WHALE_POINTS_DAMAGE_SCALE * engagement)), WT_WHALE_POINTS_LOG_BASE_E);
    float support =
        (WT_WHALE_POINTS_HEALING_WEIGHT * Logarithm(1.0 + (float(safeHealing) / (WT_WHALE_POINTS_HEALING_SCALE * engagement)), WT_WHALE_POINTS_LOG_BASE_E))
        + (WT_WHALE_POINTS_UBER_WEIGHT * Logarithm(1.0 + ((WT_WHALE_POINTS_UBER_SCALE * float(safeTotalUbers)) / engagement), WT_WHALE_POINTS_LOG_BASE_E));
    float confidence = SquareRoot(engagement / (engagement + WT_WHALE_POINTS_CONFIDENCE_ENGAGEMENT_OFFSET)) * (hours / (hours + WT_WHALE_POINTS_CONFIDENCE_HOURS_OFFSET));

    float pointsFloat = WT_WHALE_POINTS_SCALE * confidence * ((WT_WHALE_POINTS_COMBAT_WEIGHT * combat) + pressure + support);
    if (pointsFloat < 0.0)
    {
        pointsFloat = 0.0;
    }
    if (pointsFloat > WT_WHALE_POINTS_MAX_FLOAT)
    {
        pointsFloat = WT_WHALE_POINTS_MAX_FLOAT;
    }

    int points = RoundToNearest(pointsFloat);
    if (points < 0)
    {
        points = 0;
    }
    return points;
}

public int GetWhalePointsForClient(int client)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
    {
        return 0;
    }

    if (g_Stats[client].loaded)
    {
        return GetWhalePointsForStats(g_Stats[client]);
    }

    if (!g_bDatabaseReady || g_hDatabase == null)
    {
        return 0;
    }

    EnsureClientSteamId(client);
    if (g_Stats[client].steamId[0] == '\0')
    {
        return 0;
    }

    char escapedSteamId[STEAMID64_LEN * 2];
    EscapeSqlString(g_Stats[client].steamId, escapedSteamId, sizeof(escapedSteamId));

    char query[256];
    Format(query, sizeof(query),
        "SELECT kills, deaths, assists, total_ubers, damage_dealt, healing, playtime "
        ... "FROM whaletracker WHERE steamid = '%s' LIMIT 1",
        escapedSteamId);

    DBResultSet results = SQLQuerySync(query);
    if (results == null)
    {
        char error[256];
        GetSyncDatabaseError(error, sizeof(error));
        LogError("[WhaleTracker] WhalePoints query failed: %s", error);
        return 0;
    }

    if (!results.FetchRow())
    {
        delete results;
        return 0;
    }

    WhaleStats pointStats;
    pointStats.kills = results.FetchInt(0);
    pointStats.deaths = results.FetchInt(1);
    pointStats.totalAssists = results.FetchInt(2);
    pointStats.totalUbers = results.FetchInt(3);
    pointStats.totalDamage = results.FetchInt(4);
    pointStats.totalHealing = results.FetchInt(5);
    pointStats.playtime = results.FetchInt(6);
    delete results;

    return GetWhalePointsForStats(pointStats);
}

public any Native_WhaleTracker_GetCumulativeKills(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client <= 0 || client > MaxClients)
    {
        return 0;
    }

    return g_Stats[client].kills;
}

public any Native_WhaleTracker_AreStatsLoaded(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    return WhaleTracker_AreClientStatsReady(client);
}

public any Native_WhaleTracker_HasPlaytimeHours(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int hours = GetNativeCell(2);

    if (!WhaleTracker_AreClientStatsReady(client) || hours < 0)
    {
        return false;
    }

    if (hours > WT_NATIVE_MAX_PLAYTIME_HOURS)
    {
        return false;
    }

    int requiredSeconds = hours * WT_SECONDS_PER_HOUR;
    return g_Stats[client].playtime >= requiredSeconds;
}

public any Native_WhaleTracker_GetWhalePoints(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    return GetWhalePointsForClient(client);
}

public any Native_WhaleTracker_ComputeWhalePoints(Handle plugin, int numParams)
{
    WhaleStats pointStats;
    pointStats.kills = GetNativeCell(1);
    pointStats.deaths = GetNativeCell(2);
    pointStats.totalAssists = GetNativeCell(3);
    pointStats.totalUbers = GetNativeCell(4);
    pointStats.totalDamage = GetNativeCell(5);
    pointStats.totalHealing = GetNativeCell(6);
    pointStats.playtime = GetNativeCell(7);
    return GetWhalePointsForStats(pointStats);
}

int GetLastSeenForSteamId64(const char[] steamId)
{
    if (steamId[0] == '\0')
    {
        return 0;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientConnected(i) || IsFakeClient(i))
        {
            continue;
        }

        char clientSteamId[STEAMID64_LEN];
        if (!GetClientAuthId(i, AuthId_SteamID64, clientSteamId, sizeof(clientSteamId)))
        {
            continue;
        }

        if (!StrEqual(clientSteamId, steamId, false))
        {
            continue;
        }

        if (g_Stats[i].lastSeen > 0)
        {
            return g_Stats[i].lastSeen;
        }

        break;
    }

    if (!g_bDatabaseReady || g_hDatabase == null)
    {
        return 0;
    }

    char escapedSteamId[STEAMID64_LEN * 2];
    EscapeSqlString(steamId, escapedSteamId, sizeof(escapedSteamId));

    char query[256];
    Format(query, sizeof(query),
        "SELECT COALESCE(last_seen, 0) FROM whaletracker WHERE steamid = '%s' LIMIT 1",
        escapedSteamId);

    DBResultSet results = SQLQuerySync(query);
    if (results == null)
    {
        char error[256];
        GetSyncDatabaseError(error, sizeof(error));
        LogError("[WhaleTracker] LastSeen query failed: %s", error);
        return 0;
    }

    int lastSeen = 0;
    if (results.FetchRow())
    {
        lastSeen = results.FetchInt(0);
    }

    delete results;
    return lastSeen;
}

int GetFirstSeenForSteamId64(const char[] steamId)
{
    if (steamId[0] == '\0')
    {
        return 0;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientConnected(i) || IsFakeClient(i))
        {
            continue;
        }

        char clientSteamId[STEAMID64_LEN];
        if (!GetClientAuthId(i, AuthId_SteamID64, clientSteamId, sizeof(clientSteamId)))
        {
            continue;
        }

        if (!StrEqual(clientSteamId, steamId, false))
        {
            continue;
        }

        if (g_Stats[i].firstSeenTimestamp > 0)
        {
            return g_Stats[i].firstSeenTimestamp;
        }

        break;
    }

    if (!g_bDatabaseReady || g_hDatabase == null)
    {
        return 0;
    }

    char escapedSteamId[STEAMID64_LEN * 2];
    EscapeSqlString(steamId, escapedSteamId, sizeof(escapedSteamId));

    char query[256];
    Format(query, sizeof(query),
        "SELECT COALESCE(first_seen, 0) FROM whaletracker WHERE steamid = '%s' LIMIT 1",
        escapedSteamId);

    DBResultSet results = SQLQuerySync(query);
    if (results == null)
    {
        char error[256];
        GetSyncDatabaseError(error, sizeof(error));
        LogError("[WhaleTracker] FirstSeen query failed: %s", error);
        return 0;
    }

    int firstSeen = 0;
    if (results.FetchRow())
    {
        firstSeen = results.FetchInt(0);
    }

    delete results;
    return firstSeen;
}

public any Native_WhaleTracker_GetLastRecordedName(Handle plugin, int numParams)
{
    char steamId[STEAMID64_LEN];
    GetNativeString(1, steamId, sizeof(steamId));

    int maxlen = GetNativeCell(3);
    if (maxlen <= 0)
    {
        return false;
    }

    if (steamId[0] == '\0')
    {
        SetNativeString(2, "", maxlen, true);
        return false;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientConnected(i) || IsFakeClient(i))
        {
            continue;
        }

        char clientSteamId[STEAMID64_LEN];
        if (!GetClientAuthId(i, AuthId_SteamID64, clientSteamId, sizeof(clientSteamId)))
        {
            continue;
        }

        if (!StrEqual(clientSteamId, steamId, false))
        {
            continue;
        }

        char connectedName[256];
        if (GetClientName(i, connectedName, sizeof(connectedName)))
        {
            TrimString(connectedName);
            if (connectedName[0] != '\0')
            {
                SetNativeString(2, connectedName, maxlen, true);
                return true;
            }
        }

        break;
    }

    if (!g_bDatabaseReady || g_hDatabase == null)
    {
        SetNativeString(2, "", maxlen, true);
        return false;
    }

    char escapedSteamId[STEAMID64_LEN * 2];
    EscapeSqlString(steamId, escapedSteamId, sizeof(escapedSteamId));

    char name[256];
    name[0] = '\0';

    if (TryGetFiltersLastRecordedSteamName(steamId, name, sizeof(name)))
    {
        SetNativeString(2, name, maxlen, true);
        return true;
    }

    char query[768];
    Format(query, sizeof(query),
        "SELECT COALESCE("
        ... "NULLIF(fs.last_name, ''), "
        ... "NULLIF(w.cached_personaname, ''), "
        ... "''"
        ... ") "
        ... "FROM (SELECT '%s' AS steamid) s "
        ... "LEFT JOIN filters_steam_names fs ON fs.steamid64 = s.steamid "
        ... "LEFT JOIN whaletracker w ON w.steamid = s.steamid "
        ... "LIMIT 1",
        escapedSteamId);

    DBResultSet results = SQLQuerySync(query);
    if (results == null)
    {
        char error[256];
        GetSyncDatabaseError(error, sizeof(error));
        LogError("[WhaleTracker] LastRecordedName query failed: %s", error);
        SetNativeString(2, "", maxlen, true);
        return false;
    }

    bool found = false;

    if (results.FetchRow())
    {
        results.FetchString(0, name, sizeof(name));
        TrimString(name);
        found = (name[0] != '\0');
    }

    delete results;
    SetNativeString(2, name, maxlen, true);
    return found;
}

public any Native_WhaleTracker_GetLastSeen(Handle plugin, int numParams)
{
    char steamId[STEAMID64_LEN];
    GetNativeString(1, steamId, sizeof(steamId));
    return GetLastSeenForSteamId64(steamId);
}
