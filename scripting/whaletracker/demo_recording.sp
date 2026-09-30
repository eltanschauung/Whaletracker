#undef REQUIRE_EXTENSIONS
#include <sourcetvmanager>
#define REQUIRE_EXTENSIONS

bool g_MatchDemoColumnReady;
char g_MatchDemoFile[PLATFORM_MAX_PATH];

void WhaleTracker_EnsureDemoColumn()
{
    if (g_hDatabase == null) return;
    g_MatchDemoColumnReady = false;
    g_hDatabase.Query(WhaleTracker_DemoColumnReady,
        "ALTER TABLE whaletracker_logs ADD COLUMN IF NOT EXISTS demo_filename VARCHAR(260) NULL DEFAULT NULL");
}

public void WhaleTracker_DemoColumnReady(Database db, DBResultSet result, const char[] error, any data)
{
    if (db != g_hDatabase) return;
    if (error[0])
    {
        LogError("[WhaleTracker] Demo filename column unavailable: %s", error);
        return;
    }
    g_MatchDemoColumnReady = true;
}

public void WhaleTracker_CaptureRoundDemo(Event event, const char[] name, bool dontBroadcast)
{
    if (g_MatchDemoFile[0] || !g_sCurrentLogId[0] || g_bMatchFinalized
        || GetFeatureStatus(FeatureType_Native, "SourceTV_IsActive") != FeatureStatus_Available
        || GetFeatureStatus(FeatureType_Native, "SourceTV_IsRecording") != FeatureStatus_Available
        || GetFeatureStatus(FeatureType_Native, "SourceTV_GetDemoFileName") != FeatureStatus_Available
        || !SourceTV_IsActive() || !SourceTV_IsRecording()) return;
    char filename[PLATFORM_MAX_PATH];
    if (!SourceTV_GetDemoFileName(filename, sizeof(filename)) || !filename[0]) return;
    strcopy(g_MatchDemoFile, sizeof(g_MatchDemoFile), filename);
    if (!g_MatchDemoColumnReady || !g_bDatabaseReady) return;
    char escapedFile[PLATFORM_MAX_PATH * 2 + 1], escapedId[128], query[1024];
    EscapeSqlString(g_MatchDemoFile, escapedFile, sizeof(escapedFile));
    EscapeSqlString(g_sCurrentLogId, escapedId, sizeof(escapedId));
    FormatEx(query, sizeof(query),
        "UPDATE whaletracker_logs SET demo_filename = '%s' WHERE log_id = '%s' AND demo_filename IS NULL",
        escapedFile, escapedId);
    QueueSaveQuery(query, 0, false);
    // The ordinary upsert below also carries this filename if its first row
    // has not been inserted yet. COALESCE preserves the first recorded demo.
}
