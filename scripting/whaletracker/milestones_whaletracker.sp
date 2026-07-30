#define WT_PLAYTIME_MILESTONE_TABLE "whaletracker_playtime_milestones"
#define WT_PLAYTIME_MILESTONE_ID_MAX 64
#define WT_PLAYTIME_MILESTONE_REQUEST_MAX 128
#define WT_PLAYTIME_MILESTONE_TWO_HOURS "playtime_2h"
#define WT_PLAYTIME_MILESTONE_STIMULUS "playtime_10h_stimulus"
#define WT_PLAYTIME_TWO_HOURS_SECONDS (2 * WT_SECONDS_PER_HOUR)
#define WT_PLAYTIME_TEN_HOURS_SECONDS (10 * WT_SECONDS_PER_HOUR)
#define WT_PLAYTIME_MILESTONE_RETRY_DELAY 120.0

enum WhaleTrackerPlaytimeMilestone
{
    WhaleTrackerMilestone_TwoHours = 0,
    WhaleTrackerMilestone_TenHourStimulus,
    WhaleTrackerMilestone_Count
};

ConVar g_hStimulusGems = null;
bool g_bPlaytimeMilestoneSchemaReady = false;
bool g_bPlaytimeMilestoneSchemaPending = false;
bool g_bPlaytimeMilestoneHandled[MAXPLAYERS + 1][WhaleTrackerMilestone_Count];
bool g_bPlaytimeMilestonePending[MAXPLAYERS + 1][WhaleTrackerMilestone_Count];
float g_flPlaytimeMilestoneRetryAt[MAXPLAYERS + 1][WhaleTrackerMilestone_Count];

void WhaleTracker_CreatePlaytimeMilestoneConVars()
{
    g_hStimulusGems = CreateConVar(
        "sm_whaletracker_stimulus_gems",
        "100",
        "Gems attached to the one-time 10-hour WhaleTracker Stimulus Check.",
        FCVAR_NONE,
        true,
        1.0);
}

void WhaleTracker_ResetPlaytimeMilestoneClient(int client)
{
    for (int milestone = 0; milestone < view_as<int>(WhaleTrackerMilestone_Count); milestone++)
    {
        g_bPlaytimeMilestoneHandled[client][milestone] = false;
        g_bPlaytimeMilestonePending[client][milestone] = false;
        g_flPlaytimeMilestoneRetryAt[client][milestone] = 0.0;
    }
}

void WhaleTracker_DeferPlaytimeMilestoneRetry(int client, int milestoneIndex)
{
    if (client <= 0 || client > MaxClients
        || milestoneIndex < 0
        || milestoneIndex >= view_as<int>(WhaleTrackerMilestone_Count))
    {
        return;
    }

    g_bPlaytimeMilestonePending[client][milestoneIndex] = false;
    g_flPlaytimeMilestoneRetryAt[client][milestoneIndex] =
        GetEngineTime() + WT_PLAYTIME_MILESTONE_RETRY_DELAY;
}

void WhaleTracker_ResetPlaytimeMilestoneDatabaseState()
{
    g_bPlaytimeMilestoneSchemaReady = false;
    g_bPlaytimeMilestoneSchemaPending = false;

    for (int client = 1; client <= MaxClients; client++)
    {
        WhaleTracker_ResetPlaytimeMilestoneClient(client);
    }
}

void WhaleTracker_EnsurePlaytimeMilestoneTable()
{
    if (g_bPlaytimeMilestoneSchemaReady
        || g_bPlaytimeMilestoneSchemaPending
        || !g_bDatabaseReady
        || g_hDatabase == null)
    {
        return;
    }

    g_bPlaytimeMilestoneSchemaPending = true;
    char query[1024];
    FormatEx(query, sizeof(query),
        "CREATE TABLE IF NOT EXISTS %s ("
        ... "steamid64 VARCHAR(32) NOT NULL, "
        ... "milestone_id VARCHAR(64) NOT NULL, "
        ... "threshold_seconds INT NOT NULL, "
        ... "handled_at INT NOT NULL, "
        ... "PRIMARY KEY (steamid64, milestone_id), "
        ... "KEY idx_playtime_milestone_handled_at (handled_at)"
        ... ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
        WT_PLAYTIME_MILESTONE_TABLE);
    g_hDatabase.Query(WhaleTracker_PlaytimeMilestoneSchemaCallback, query);
}

public void WhaleTracker_PlaytimeMilestoneSchemaCallback(Database db, DBResultSet results, const char[] error, any data)
{
    g_bPlaytimeMilestoneSchemaPending = false;

    if (error[0] != '\0')
    {
        LogError("[WhaleTracker] Failed to create playtime milestone table: %s", error);
        return;
    }

    g_bPlaytimeMilestoneSchemaReady = true;
    for (int client = 1; client <= MaxClients; client++)
    {
        WhaleTracker_CheckPlaytimeMilestones(client);
    }
}

int WhaleTracker_GetPlaytimeMilestoneThreshold(WhaleTrackerPlaytimeMilestone milestone)
{
    switch (milestone)
    {
        case WhaleTrackerMilestone_TwoHours:
        {
            return WT_PLAYTIME_TWO_HOURS_SECONDS;
        }
        case WhaleTrackerMilestone_TenHourStimulus:
        {
            return WT_PLAYTIME_TEN_HOURS_SECONDS;
        }
    }

    return 0;
}

void WhaleTracker_GetPlaytimeMilestoneId(
    WhaleTrackerPlaytimeMilestone milestone,
    char[] milestoneId,
    int maxlen)
{
    switch (milestone)
    {
        case WhaleTrackerMilestone_TwoHours:
        {
            strcopy(milestoneId, maxlen, WT_PLAYTIME_MILESTONE_TWO_HOURS);
        }
        case WhaleTrackerMilestone_TenHourStimulus:
        {
            strcopy(milestoneId, maxlen, WT_PLAYTIME_MILESTONE_STIMULUS);
        }
        default:
        {
            milestoneId[0] = '\0';
        }
    }
}

bool WhaleTracker_IsSameMilestoneClient(int client, const char[] steamId64)
{
    return IsValidClient(client)
        && !IsFakeClient(client)
        && g_Stats[client].steamId[0] != '\0'
        && StrEqual(g_Stats[client].steamId, steamId64);
}

void WhaleTracker_CheckPlaytimeMilestones(int client)
{
    if (!g_bPlaytimeMilestoneSchemaReady
        || !IsValidClient(client)
        || IsFakeClient(client)
        || !g_Stats[client].loaded
        || g_Stats[client].steamId[0] == '\0'
        || g_MapStats[client].kills <= 0
        || g_hDatabase == null)
    {
        return;
    }

    for (int index = 0; index < view_as<int>(WhaleTrackerMilestone_Count); index++)
    {
        WhaleTrackerPlaytimeMilestone milestone = view_as<WhaleTrackerPlaytimeMilestone>(index);
        if (g_Stats[client].playtime < WhaleTracker_GetPlaytimeMilestoneThreshold(milestone)
            || g_bPlaytimeMilestoneHandled[client][index]
            || g_bPlaytimeMilestonePending[client][index]
            || GetEngineTime() < g_flPlaytimeMilestoneRetryAt[client][index])
        {
            continue;
        }

        g_bPlaytimeMilestonePending[client][index] = true;

        char milestoneId[WT_PLAYTIME_MILESTONE_ID_MAX];
        char escapedSteamId[STEAMID64_LEN * 2 + 1];
        char escapedMilestoneId[WT_PLAYTIME_MILESTONE_ID_MAX * 2 + 1];
        WhaleTracker_GetPlaytimeMilestoneId(milestone, milestoneId, sizeof(milestoneId));
        EscapeSqlString(g_Stats[client].steamId, escapedSteamId, sizeof(escapedSteamId));
        EscapeSqlString(milestoneId, escapedMilestoneId, sizeof(escapedMilestoneId));

        DataPack pack = new DataPack();
        pack.WriteCell(GetClientUserId(client));
        pack.WriteCell(index);
        pack.WriteString(g_Stats[client].steamId);

        char query[512];
        FormatEx(query, sizeof(query),
            "SELECT 1 FROM %s WHERE steamid64 = '%s' AND milestone_id = '%s' LIMIT 1",
            WT_PLAYTIME_MILESTONE_TABLE,
            escapedSteamId,
            escapedMilestoneId);
        g_hDatabase.Query(WhaleTracker_PlaytimeMilestoneLookupCallback, query, pack);
    }
}

public void WhaleTracker_PlaytimeMilestoneLookupCallback(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userId = pack.ReadCell();
    int milestoneIndex = pack.ReadCell();
    char steamId64[STEAMID64_LEN];
    pack.ReadString(steamId64, sizeof(steamId64));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (error[0] != '\0')
    {
        LogError("[WhaleTracker] Failed to look up playtime milestone for %s: %s", steamId64, error);
        if (WhaleTracker_IsSameMilestoneClient(client, steamId64))
        {
            WhaleTracker_DeferPlaytimeMilestoneRetry(client, milestoneIndex);
        }
        return;
    }

    if (results != null && results.FetchRow())
    {
        if (WhaleTracker_IsSameMilestoneClient(client, steamId64))
        {
            g_bPlaytimeMilestoneHandled[client][milestoneIndex] = true;
            g_bPlaytimeMilestonePending[client][milestoneIndex] = false;
            g_flPlaytimeMilestoneRetryAt[client][milestoneIndex] = 0.0;
        }
        return;
    }

    WhaleTrackerPlaytimeMilestone milestone = view_as<WhaleTrackerPlaytimeMilestone>(milestoneIndex);
    if (milestone == WhaleTrackerMilestone_TwoHours)
    {
        WhaleTracker_CommitPlaytimeMilestone(userId, steamId64, milestone);
        return;
    }

    WhaleTracker_SendStimulusMail(userId, steamId64);
}

void WhaleTracker_CommitPlaytimeMilestone(
    int userId,
    const char[] steamId64,
    WhaleTrackerPlaytimeMilestone milestone)
{
    if (!g_bPlaytimeMilestoneSchemaReady || g_hDatabase == null)
    {
        int client = GetClientOfUserId(userId);
        if (WhaleTracker_IsSameMilestoneClient(client, steamId64))
        {
            WhaleTracker_DeferPlaytimeMilestoneRetry(client, view_as<int>(milestone));
        }
        return;
    }

    char milestoneId[WT_PLAYTIME_MILESTONE_ID_MAX];
    char escapedSteamId[STEAMID64_LEN * 2 + 1];
    char escapedMilestoneId[WT_PLAYTIME_MILESTONE_ID_MAX * 2 + 1];
    WhaleTracker_GetPlaytimeMilestoneId(milestone, milestoneId, sizeof(milestoneId));
    EscapeSqlString(steamId64, escapedSteamId, sizeof(escapedSteamId));
    EscapeSqlString(milestoneId, escapedMilestoneId, sizeof(escapedMilestoneId));

    DataPack pack = new DataPack();
    pack.WriteCell(userId);
    pack.WriteCell(view_as<int>(milestone));
    pack.WriteString(steamId64);

    char query[768];
    FormatEx(query, sizeof(query),
        "INSERT IGNORE INTO %s "
        ... "(steamid64, milestone_id, threshold_seconds, handled_at) "
        ... "VALUES ('%s', '%s', %d, %d)",
        WT_PLAYTIME_MILESTONE_TABLE,
        escapedSteamId,
        escapedMilestoneId,
        WhaleTracker_GetPlaytimeMilestoneThreshold(milestone),
        GetTime());
    g_hDatabase.Query(WhaleTracker_PlaytimeMilestoneCommitCallback, query, pack);
}

public void WhaleTracker_PlaytimeMilestoneCommitCallback(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userId = pack.ReadCell();
    int milestoneIndex = pack.ReadCell();
    char steamId64[STEAMID64_LEN];
    pack.ReadString(steamId64, sizeof(steamId64));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (error[0] != '\0' || results == null)
    {
        LogError("[WhaleTracker] Failed to commit playtime milestone for %s: %s", steamId64, error);
        if (WhaleTracker_IsSameMilestoneClient(client, steamId64))
        {
            WhaleTracker_DeferPlaytimeMilestoneRetry(client, milestoneIndex);
        }
        return;
    }

    if (WhaleTracker_IsSameMilestoneClient(client, steamId64))
    {
        g_bPlaytimeMilestoneHandled[client][milestoneIndex] = true;
        g_bPlaytimeMilestonePending[client][milestoneIndex] = false;
        g_flPlaytimeMilestoneRetryAt[client][milestoneIndex] = 0.0;
    }

    if (results.AffectedRows <= 0 || !WhaleTracker_IsSameMilestoneClient(client, steamId64))
    {
        return;
    }

    WhaleTrackerPlaytimeMilestone milestone = view_as<WhaleTrackerPlaytimeMilestone>(milestoneIndex);
    if (milestone == WhaleTrackerMilestone_TwoHours)
    {
        CPrintToChat(client,
            "{gold}[kogasa.tf]{default} You now have 2 hours of playtime on this server, consider checking out our Steam group or website!");
    }
    else if (milestone == WhaleTrackerMilestone_TenHourStimulus)
    {
        WhaleTracker_AnnounceStimulus(client);
    }
}

bool WhaleTracker_IsServerMailAvailable()
{
    return GetFeatureStatus(FeatureType_Native, "ServerMail_SendCurrencySteamId") == FeatureStatus_Available;
}

void WhaleTracker_SendStimulusMail(int userId, const char[] steamId64)
{
    int client = GetClientOfUserId(userId);
    if (!WhaleTracker_IsServerMailAvailable())
    {
        if (WhaleTracker_IsSameMilestoneClient(client, steamId64))
        {
            WhaleTracker_DeferPlaytimeMilestoneRetry(
                client,
                WhaleTrackerMilestone_TenHourStimulus);
        }
        return;
    }

    char requestKey[WT_PLAYTIME_MILESTONE_REQUEST_MAX];
    FormatEx(requestKey, sizeof(requestKey), "whaletracker:playtime:10h:%s", steamId64);
    int gems = g_hStimulusGems.IntValue;
    if (!ServerMail_SendCurrencySteamId(
        "",
        "kogasa.tf",
        steamId64,
        "Stimulus Check",
        "A one-time reward for reaching 10 hours of playtime on kogasa.tf.",
        gems,
        requestKey))
    {
        LogError("[WhaleTracker] Failed to queue 10-hour Stimulus Check mail for %s.", steamId64);
        if (WhaleTracker_IsSameMilestoneClient(client, steamId64))
        {
            WhaleTracker_DeferPlaytimeMilestoneRetry(
                client,
                WhaleTrackerMilestone_TenHourStimulus);
        }
    }
}

public void ServerMail_OnMailSendResult(
    const char[] requestKey,
    bool success,
    int mailId,
    bool newlyCreated)
{
    static const char requestPrefix[] = "whaletracker:playtime:10h:";
    int prefixLength = sizeof(requestPrefix) - 1;
    if (strncmp(requestKey, requestPrefix, prefixLength) != 0)
    {
        return;
    }

    char steamId64[STEAMID64_LEN];
    strcopy(steamId64, sizeof(steamId64), requestKey[prefixLength]);
    int client = WhaleTracker_FindClientBySteamId64(steamId64);

    if (!success || mailId <= 0)
    {
        LogError("[WhaleTracker] Stimulus Check mail insert failed for %s.", steamId64);
        if (WhaleTracker_IsSameMilestoneClient(client, steamId64))
        {
            WhaleTracker_DeferPlaytimeMilestoneRetry(
                client,
                WhaleTrackerMilestone_TenHourStimulus);
        }
        return;
    }

    int userId = WhaleTracker_IsSameMilestoneClient(client, steamId64) ? GetClientUserId(client) : 0;
    WhaleTracker_CommitPlaytimeMilestone(
        userId,
        steamId64,
        WhaleTrackerMilestone_TenHourStimulus);
}

void WhaleTracker_GetCurrencyColor(char[] colorTag, int maxlen)
{
    ConVar currencyColor = FindConVar("sm_points_store_currency_color");
    char colorName[32];
    if (currencyColor != null)
    {
        currencyColor.GetString(colorName, sizeof(colorName));
    }
    else
    {
        strcopy(colorName, sizeof(colorName), "cyan");
    }
    FormatEx(colorTag, maxlen, "{%s}", colorName);
}

void WhaleTracker_AnnounceStimulus(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client))
    {
        return;
    }

    char currencyColor[40];
    WhaleTracker_GetCurrencyColor(currencyColor, sizeof(currencyColor));
    CPrintToChat(client,
        "{gold}[WhaleTracker]{default} Use {gold}!mail{default} to collect your %sStimulus Check{default}.",
        currencyColor);

    char coloredName[256];
    if (GetFeatureStatus(FeatureType_Native, "Filters_GetChatName") != FeatureStatus_Available
        || !Filters_GetChatName(client, coloredName, sizeof(coloredName))
        || coloredName[0] == '\0')
    {
        GetClientName(client, coloredName, sizeof(coloredName));
    }

    CPrintToChatAllEx(client,
        "{gold}[WhaleTracker] %s{default} just got a %sStimulus Check{default} for reaching {gold}10 hours playtime!",
        coloredName,
        currencyColor);

    if (GetFeatureStatus(FeatureType_Native, "SaySounds_PlayCommand") == FeatureStatus_Available)
    {
        SaySounds_PlayCommand(0, "xp_gain", true);
    }
}

public void OnLibraryAdded(const char[] name)
{
    if (!StrEqual(name, "server_mail"))
    {
        return;
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        if (g_bPlaytimeMilestonePending[client][WhaleTrackerMilestone_TenHourStimulus])
        {
            g_bPlaytimeMilestonePending[client][WhaleTrackerMilestone_TenHourStimulus] = false;
        }
        g_flPlaytimeMilestoneRetryAt[client][WhaleTrackerMilestone_TenHourStimulus] = 0.0;
        WhaleTracker_CheckPlaytimeMilestones(client);
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if (!StrEqual(name, "server_mail"))
    {
        return;
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        g_bPlaytimeMilestonePending[client][WhaleTrackerMilestone_TenHourStimulus] = false;
        g_flPlaytimeMilestoneRetryAt[client][WhaleTrackerMilestone_TenHourStimulus] =
            GetEngineTime() + WT_PLAYTIME_MILESTONE_RETRY_DELAY;
    }
}
