#undef REQUIRE_EXTENSIONS
#include <sourcetvmanager>
#define REQUIRE_EXTENSIONS

bool g_WhaleDemosColumnReady;
bool g_WhaleDemosRequested;
bool g_WhaleDemosQueryPending;
bool g_WhaleDemosOwnRecording;
int g_WhaleDemosGeneration;
float g_WhaleDemosNextAttempt;
char g_WhaleDemoFile[PLATFORM_MAX_PATH];

void WhaleDemos_EnsureColumn()
{
    // Old connection callbacks must not retain or clear the new lookup's lease.
    g_WhaleDemosGeneration++;
    g_WhaleDemosQueryPending = false;
    g_WhaleDemosNextAttempt = 0.0;
    g_WhaleDemosColumnReady = false;
    if (g_hDatabase == null) return;
    g_hDatabase.Query(WhaleDemos_ColumnReady,
        "ALTER TABLE whaletracker_logs ADD COLUMN IF NOT EXISTS demo_filename VARCHAR(260) NULL DEFAULT NULL");
}

public void WhaleDemos_ColumnReady(Database db, DBResultSet result, const char[] error, any data)
{
    if (db != g_hDatabase) return;
    if (error[0])
    {
        LogError("[WhaleDemos] Demo filename column unavailable: %s", error);
        return;
    }
    g_WhaleDemosColumnReady = true;
    WhaleDemos_TryStart();
}

bool WhaleDemos_HasSourceTV()
{
    return GetFeatureStatus(FeatureType_Native, "SourceTV_IsActive") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "SourceTV_IsRecording") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "SourceTV_StartRecording") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "SourceTV_StopRecording") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "SourceTV_GetDemoFileName") == FeatureStatus_Available;
}

bool WhaleDemos_HasEnoughPlayers()
{
    // Never count bots, connecting clients or spectators as DGM's real players.
    return GetFeatureStatus(FeatureType_Native, "DGM_RealPlayerCount") == FeatureStatus_Available
        && DGM_RealPlayerCount() > 7;
}

void WhaleDemos_OnClientPostAdminCheck(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client) || !WhaleDemos_HasEnoughPlayers()) return;
    g_WhaleDemosRequested = true;
    WhaleDemos_TryStart();
}

void WhaleDemos_TryStart()
{
    if (!g_WhaleDemosRequested || g_WhaleDemosQueryPending || g_WhaleDemoFile[0]
        || !g_WhaleDemosColumnReady || !g_bDatabaseReady || g_hDatabase == null
        || !g_sCurrentLogId[0] || g_bMatchFinalized || !WhaleTracker_ShouldUseMatchLogs()
        || !WhaleDemos_HasEnoughPlayers() || GetEngineTime() < g_WhaleDemosNextAttempt) return;

    g_WhaleDemosNextAttempt = GetEngineTime() + 5.0;
    if (!WhaleDemos_HasSourceTV() || !SourceTV_IsActive() || SourceTV_IsRecording()) return;

    char escapedId[128], query[256];
    EscapeSqlString(g_sCurrentLogId, escapedId, sizeof(escapedId));
    FormatEx(query, sizeof(query),
        "SELECT demo_filename FROM whaletracker_logs WHERE log_id = '%s' LIMIT 1", escapedId);

    DataPack pack = new DataPack();
    pack.WriteCell(g_WhaleDemosGeneration);
    pack.WriteString(g_sCurrentLogId);
    g_WhaleDemosQueryPending = true;
    g_hDatabase.Query(WhaleDemos_CheckCurrentRow, query, pack);
}

public void WhaleDemos_CheckCurrentRow(Database db, DBResultSet result, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int generation = pack.ReadCell();
    char logId[64];
    pack.ReadString(logId, sizeof(logId));
    delete pack;

    // A map change/finalization must not let an old query start the next match's demo.
    if (generation != g_WhaleDemosGeneration || !StrEqual(logId, g_sCurrentLogId)) return;
    g_WhaleDemosQueryPending = false;
    if (db != g_hDatabase || !g_bDatabaseReady || g_bMatchFinalized) return;
    if (error[0] || result == null)
    {
        LogError("[WhaleDemos] Failed to read demo filename for %s: %s", logId, error);
        return;
    }
    if (result.FetchRow() && !result.IsFieldNull(0))
    {
        result.FetchString(0, g_WhaleDemoFile, sizeof(g_WhaleDemoFile));
        g_WhaleDemosRequested = false;
        return;
    }

    if (!WhaleDemos_HasEnoughPlayers() || !WhaleDemos_HasSourceTV()
        || !SourceTV_IsActive() || SourceTV_IsRecording()) return;

    char filename[PLATFORM_MAX_PATH];
    WhaleDemos_BuildFilename(filename, sizeof(filename));
    if (!SourceTV_StartRecording(filename) || !SourceTV_IsRecording())
    {
        LogError("[WhaleDemos] Failed to start recording %s for %s", filename, logId);
        return;
    }

    strcopy(g_WhaleDemoFile, sizeof(g_WhaleDemoFile), filename);
    g_WhaleDemosOwnRecording = true;
    g_WhaleDemosRequested = false;
    // An upsert also covers a match whose first summary row is not written yet.
    int now = GetTime();
    InsertMatchLogRecord(now, now - g_iMatchStartTime, WhaleTracker_GetCurrentPlayerCount(), false, false);
    LogMessage("[WhaleDemos] Started %s for match %s", filename, logId);
}

void WhaleDemos_BuildFilename(char[] filename, int maxlen)
{
    char mapName[128];
    GetCurrentMap(mapName, sizeof(mapName));
    if (GetFeatureStatus(FeatureType_Native, "DGM_NormalizeMapName") == FeatureStatus_Available)
        DGM_NormalizeMapName(mapName, mapName, sizeof(mapName));
    else
    {
        int slash = FindCharInString(mapName, '/', true);
        if (slash != -1) strcopy(mapName, sizeof(mapName), mapName[slash + 1]);
        int ugc = StrContains(mapName, ".ugc", false);
        if (ugc != -1) mapName[ugc] = '\0';
    }
    for (int i = 0; mapName[i]; i++)
    {
        if (!IsCharAlpha(mapName[i]) && !IsCharNumeric(mapName[i]) && mapName[i] != '_' && mapName[i] != '-')
            mapName[i] = '_';
    }

    static const char months[][] = {
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sept", "oct", "nov", "dec"
    };
    char month[3], day[3], clock[6], base[PLATFORM_MAX_PATH];
    int now = GetTime();
    // The VPS timezone is America/New_York; FormatTime follows its DST rules.
    FormatTime(month, sizeof(month), "%m", now);
    FormatTime(day, sizeof(day), "%d", now);
    FormatTime(clock, sizeof(clock), "%H-%M", now);
    FormatEx(base, sizeof(base), "%s_%s_%d_%s", mapName, months[StringToInt(month) - 1], StringToInt(day), clock);
    FormatEx(filename, maxlen, "%s.dem", base);
    // Both servers share the demo directory; never overwrite a same-minute recording.
    for (int suffix = 2; FileExists(filename, true); suffix++)
        FormatEx(filename, maxlen, "%s_%d.dem", base, suffix);
}

void WhaleDemos_ResetMatch()
{
    g_WhaleDemosGeneration++;
    g_WhaleDemosRequested = false;
    g_WhaleDemosQueryPending = false;
    g_WhaleDemosNextAttempt = 0.0;
    if (g_WhaleDemosOwnRecording && WhaleDemos_HasSourceTV() && SourceTV_IsRecording())
    {
        char recorded[PLATFORM_MAX_PATH];
        if (SourceTV_GetDemoFileName(recorded, sizeof(recorded)))
        {
            int slash = FindCharInString(recorded, '/', true);
            if (StrEqual(recorded[slash + 1], g_WhaleDemoFile)) SourceTV_StopRecording();
        }
    }
    g_WhaleDemosOwnRecording = false;
    g_WhaleDemoFile[0] = '\0';
}

void WhaleDemos_GetLogFields(char[] column, int columnLen, char[] value, int valueLen, char[] update, int updateLen)
{
    column[0] = value[0] = update[0] = '\0';
    if (!g_WhaleDemosColumnReady) return;
    strcopy(column, columnLen, ", demo_filename");
    strcopy(update, updateLen, ", demo_filename = COALESCE(demo_filename, VALUES(demo_filename))");
    if (!g_WhaleDemoFile[0])
        strcopy(value, valueLen, ", NULL");
    else
    {
        char escaped[PLATFORM_MAX_PATH * 2 + 1];
        EscapeSqlString(g_WhaleDemoFile, escaped, sizeof(escaped));
        FormatEx(value, valueLen, ", '%s'", escaped);
    }
}
