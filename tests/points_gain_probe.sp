#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#define STEAMID64_LEN 32

int g_iRollingPointsCache[MAXPLAYERS + 1], g_iRollingRankCache[MAXPLAYERS + 1];
int g_iRollingMatchesCache[MAXPLAYERS + 1];
bool g_bRollingPointsLoaded[MAXPLAYERS + 1];
int checks, failures, prints, sounds;
int currentSerial = 1001;
bool optedIn = true, apiAvailable = true;
char printed[256];
float testGameTime = 100.0, lastTimerDelay;
int testUnixTime = 1000, retryCount, sqlReads, refreshedPoints;
bool fakeRowRead, fakeRowAvailable = true;
char g_sCurrentLogId[128] = "test-log";
enum struct ProbeStats
{
    char steamId[32];
}
ProbeStats g_Stats[MAXPLAYERS + 1];
#define WT_BONUS_POINTS_SOUND "xp_gain"

bool TestInGame(int client) { return client == 1; }
bool TestFake(int client) { return client != 1; }
int TestSerial(int client) { if (client != 1) failures++; return currentSerial; }
int TestFromSerial(int serial) { return serial == currentSerial ? 1 : 0; }
Handle TestTimer(float interval, Timer callback, any serial, int flags)
{
    if (interval < 0.1 || interval > 5.0 || flags != TIMER_FLAG_NO_MAPCHANGE
        || serial != currentSerial || callback != Timer_NotifyPointsGain) failures++;
    lastTimerDelay = interval;
    return CreateDataPack(); // Valid disposable handle; no real scheduling.
}
float TestGameTime() { return testGameTime; }
int TestUnixTime() { return testUnixTime; }
int TestRowCount(Handle query)
{
    if (query == null) failures++;
    sqlReads++;
    return fakeRowAvailable ? 1 : 0;
}
bool TestFetchRow(Handle query)
{
    if (query == null) failures++;
    if (fakeRowRead) return false;
    fakeRowRead = true;
    return true;
}
int TestFetchString(Handle query, int field, char[] output, int size)
{
    if (query == null || field != 0) failures++;
    return strcopy(output, size, "test-player");
}
int TestFetchInt(Handle query, int field)
{
    if (query == null || field < 1 || field > 3) failures++;
    return field == 1 ? refreshedPoints : (field == 2 ? 5 : 35);
}
void WhaleTracker_QueueRoundPointsRefresh(int requestedAt, const char[] logId, int generation)
{
    if (!WhaleTracker_IsCurrentRoundPointsRefresh(generation)
        || requestedAt != 1000 || !StrEqual(logId, "test-log")) failures++;
    retryCount++;
}
FeatureStatus TestFeature(FeatureType type, const char[] name)
{
    if (type != FeatureType_Native || !StrEqual(name, "SaySounds_PlayCommandAs")) failures++;
    return apiAvailable ? FeatureStatus_Available : FeatureStatus_Unavailable;
}
void CPrintToChat(int client, const char[] message, any ...)
{
    if (client != 1) failures++;
    prints++;
    VFormat(printed, sizeof(printed), message, 3);
}
bool SaySounds_PlayCommandAs(int source, int target, const char[] command, bool force)
{
    if (source != 1 || target != 1 || force || !StrEqual(command, "xp_gain")) failures++;
    if (optedIn) sounds++;
    return optedIn;
}
#define IsClientInGame TestInGame
#define IsFakeClient TestFake
#define GetClientSerial TestSerial
#define GetClientFromSerial TestFromSerial
#define CreateTimer TestTimer
#define GetFeatureStatus TestFeature
#define GetGameTime TestGameTime
#define GetTime TestUnixTime
#define SQL_GetRowCount TestRowCount
#define SQL_FetchRow TestFetchRow
#define SQL_FetchString TestFetchString
#define SQL_FetchInt TestFetchInt
#include "points_gain_whaletracker.sp"
#include "round_points_refresh_callback.sp"

void Check(bool value) { checks++; if (!value) failures++; }
void FireNotice()
{
    Handle timer = g_hPointsGainTimer[1];
    Check(timer != null);
    Timer_NotifyPointsGain(timer, currentSerial);
    delete timer;
}

void ResetFixture(int points = 1000)
{
    WhaleTracker_PausePointsGainTimers();
    WhaleTracker_ResetPointsGainClient(1);
    strcopy(g_Stats[1].steamId, sizeof(g_Stats[].steamId), "test-player");
    testGameTime = 100.0;
    testUnixTime = 1000;
    fakeRowAvailable = true;
    retryCount = 0;
    WhaleTracker_AcceptCalculatedPoints(1, points, 5, 35);
}

void CompleteRefresh(int generation, int points, int requestedAt = 1000)
{
    DataPack pack = new DataPack();
    pack.WriteCell(requestedAt);
    pack.WriteString("test-log");
    pack.WriteCell(generation);
    fakeRowRead = false;
    refreshedPoints = points;
    Handle result = CreateDataPack(); // A disposable stand-in, never a database.
    SQL_OnRoundPointsRefreshed(null, result, "", pack);
    delete result;
}

public void OnPluginStart()
{
    WhaleTracker_AcceptCalculatedPoints(1, 1000, 5, 35);
    Check(g_iPointsGainPending[1] == 0); // Initial login/reload isn't a gain.
    WhaleTracker_AcceptCalculatedPoints(1, 1009, 5, 35);
    Check(g_iPointsGainPending[1] == 0);
    WhaleTracker_AcceptCalculatedPoints(1, 1019, 5, 35);
    Check(g_iPointsGainPending[1] == 10 && prints == 0);
    WhaleTracker_SchedulePointsGainNotifications();
    Handle first = g_hPointsGainTimer[1];
    WhaleTracker_SchedulePointsGainNotifications();
    Check(g_hPointsGainTimer[1] == first); // Repeated round event can't duplicate.
    FireNotice();
    Check(prints == 1 && sounds == 1 && StrContains(printed, "{lightgreen}10!") != -1);
    WhaleTracker_SchedulePointsGainNotifications();
    Check(g_hPointsGainTimer[1] == null);
    WhaleTracker_AcceptCalculatedPoints(1, 1038, 4, 36);
    WhaleTracker_SchedulePointsGainNotifications();
    optedIn = false;
    FireNotice();
    Check(prints == 2 && sounds == 1 && StrContains(printed, "{lightgreen}19!") != -1);
    WhaleTracker_AcceptCalculatedPoints(1, 1058, 4, 36);
    WhaleTracker_SchedulePointsGainNotifications();
    apiAvailable = false;
    FireNotice();
    Check(prints == 3 && sounds == 1 && StrContains(printed, "{green}20!") != -1);
    WhaleTracker_AcceptCalculatedPoints(1, 1000, 4, 36);
    WhaleTracker_AcceptCalculatedPoints(1, 1000, 4, 36);
    Check(g_iPointsGainPending[1] == 0); // Drops and unchanged refreshes don't notify.
    WhaleTracker_AcceptCalculatedPoints(1, 1010, 4, 36);
    WhaleTracker_SchedulePointsGainNotifications();
    WhaleTracker_AcceptCalculatedPoints(1, 1030, 4, 36);
    Check(g_iPointsGainScheduled[1] == 30 && g_iPointsGainPending[1] == 0);
    WhaleTracker_PausePointsGainTimers();
    Check(g_hPointsGainTimer[1] == null && g_iPointsGainPending[1] == 30);
    WhaleTracker_SchedulePointsGainNotifications();
    Check(g_iPointsGainScheduled[1] == 30 && g_iPointsGainPending[1] == 0);
    Handle pending = g_hPointsGainTimer[1];
    Check(Timer_NotifyPointsGain(null, currentSerial) == Plugin_Stop && g_hPointsGainTimer[1] == pending);
    Check(Timer_NotifyPointsGain(pending, currentSerial + 1) == Plugin_Stop && prints == 3);
    WhaleTracker_ResetPointsGainClient(1);
    currentSerial++;
    Check(!g_bPointsGainBaselineLoaded[1] && g_iPointsGainPending[1] == 0 && g_hPointsGainTimer[1] == null);
    WhaleTracker_AcceptCalculatedPoints(1, 5000, 1, 100);
    Check(g_iPointsGainPending[1] == 0); // Reused slot doesn't inherit baseline.
    Check(WhaleTracker_AddPendingPointsGain(2147483640, 20) == 2147483647);
    WhaleTracker_ResetPointsGainClient(1);
    WhaleTracker_AcceptCalculatedPoints(1, 5000, 0, 34);
    Check(g_iPointsGainBaseline[1] == 0); // Match sm_points unranked semantics.

    // Reproduce the reported +21: round start beats asynchronous publication.
    ResetFixture(9634);
    int generation = WhaleTracker_BeginRoundPointsRefresh();
    WhaleTracker_SchedulePointsGainNotifications();
    Check(g_hPointsGainTimer[1] == null);
    testGameTime = 102.0;
    CompleteRefresh(generation, 9655);
    Check(g_iRollingPointsCache[1] == 9655 && g_iPointsGainScheduled[1] == 21);
    Check(g_hPointsGainTimer[1] != null && lastTimerDelay == 3.0);
    int before = prints;
    FireNotice();
    Check(prints == before + 1 && StrContains(printed, "{green}21!") != -1);
    CompleteRefresh(generation, 9700); // Duplicate completion cannot change state.
    Check(g_iRollingPointsCache[1] == 9655 && g_hPointsGainTimer[1] == null);

    // Publication first: still wait for round start and its five-second delay.
    ResetFixture();
    generation = WhaleTracker_BeginRoundPointsRefresh();
    CompleteRefresh(generation, 1020);
    Check(g_hPointsGainTimer[1] == null && g_iPointsGainPending[1] == 20);
    WhaleTracker_SchedulePointsGainNotifications();
    Check(g_hPointsGainTimer[1] != null && lastTimerDelay == 5.0);

    // Slow publication: do not wait a whole round or another five seconds.
    ResetFixture();
    generation = WhaleTracker_BeginRoundPointsRefresh();
    WhaleTracker_SchedulePointsGainNotifications();
    testGameTime = 110.0;
    CompleteRefresh(generation, 1020);
    Check(g_hPointsGainTimer[1] != null && lastTimerDelay == 0.1);
    WhaleTracker_AcceptCalculatedPoints(1, 1032, 5, 35); // !points during delay.
    Check(g_iPointsGainScheduled[1] == 32 && g_iPointsGainPending[1] == 0);

    // A manual mid-round observation alone still waits for next round start.
    ResetFixture();
    WhaleTracker_SchedulePointsGainNotifications();
    WhaleTracker_AcceptCalculatedPoints(1, 1020, 5, 35);
    Check(g_hPointsGainTimer[1] == null && g_iPointsGainPending[1] == 20);
    WhaleTracker_SchedulePointsGainNotifications();
    Check(g_iPointsGainScheduled[1] == 20);

    // Rapid rounds: only the latest refresh can accept points or open the gate.
    ResetFixture();
    int staleGeneration = WhaleTracker_BeginRoundPointsRefresh();
    WhaleTracker_SchedulePointsGainNotifications();
    generation = WhaleTracker_BeginRoundPointsRefresh();
    WhaleTracker_SchedulePointsGainNotifications();
    int readsBefore = sqlReads;
    CompleteRefresh(staleGeneration, 1099);
    Check(g_iRollingPointsCache[1] == 1000 && sqlReads == readsBefore);
    Check(g_bPointsGainRefreshPending && g_hPointsGainTimer[1] == null);
    CompleteRefresh(generation, 1020);
    Check(!g_bPointsGainRefreshPending && g_iPointsGainScheduled[1] == 20);

    // Empty cache generation retries without arming a stale gain notification.
    ResetFixture();
    generation = WhaleTracker_BeginRoundPointsRefresh();
    WhaleTracker_SchedulePointsGainNotifications();
    fakeRowAvailable = false;
    CompleteRefresh(generation, 1020);
    Check(retryCount == 1 && g_bPointsGainRefreshPending && g_hPointsGainTimer[1] == null);
    fakeRowAvailable = true;
    CompleteRefresh(generation, 1020);
    Check(g_iPointsGainScheduled[1] == 20 && g_hPointsGainTimer[1] != null);

    // A live command and the subsequent automatic refresh observe one gain.
    ResetFixture();
    generation = WhaleTracker_BeginRoundPointsRefresh();
    WhaleTracker_SchedulePointsGainNotifications();
    WhaleTracker_AcceptCalculatedPoints(1, 1020, 5, 35);
    CompleteRefresh(generation, 1020);
    Check(g_iPointsGainScheduled[1] == 20 && g_iPointsGainPending[1] == 0);
    Check(g_hPointsGainTimer[1] != null);

    // A failed query retries the same generation; it cannot open the gate.
    ResetFixture();
    generation = WhaleTracker_BeginRoundPointsRefresh();
    WhaleTracker_SchedulePointsGainNotifications();
    DataPack failedRequest = new DataPack();
    failedRequest.WriteCell(1000);
    failedRequest.WriteString("test-log");
    failedRequest.WriteCell(generation);
    SQL_OnRoundPointsRefreshed(null, null, "simulated error", failedRequest);
    Check(retryCount == 1 && g_bPointsGainRefreshPending && g_hPointsGainTimer[1] == null);
    CompleteRefresh(generation, 1020);
    Check(g_iPointsGainScheduled[1] == 20);

    // Timeout or invalid log releases the gate without inventing a fresh result.
    ResetFixture();
    generation = WhaleTracker_BeginRoundPointsRefresh();
    WhaleTracker_SchedulePointsGainNotifications();
    testUnixTime = 1061;
    CompleteRefresh(generation, 1020);
    Check(!g_bPointsGainRefreshPending && g_hPointsGainTimer[1] == null);
    Check(g_iRollingPointsCache[1] == 1000);
    ResetFixture();
    generation = WhaleTracker_BeginRoundPointsRefresh();
    strcopy(g_sCurrentLogId, sizeof(g_sCurrentLogId), "new-test-log");
    CompleteRefresh(generation, 1020);
    Check(!g_bPointsGainRefreshPending && g_iRollingPointsCache[1] == 1000);
    strcopy(g_sCurrentLogId, sizeof(g_sCurrentLogId), "test-log");

    // Map end invalidates in-flight callbacks and preserves earned notices.
    ResetFixture();
    generation = WhaleTracker_BeginRoundPointsRefresh();
    WhaleTracker_AcceptCalculatedPoints(1, 1020, 5, 35);
    WhaleTracker_SchedulePointsGainNotifications();
    WhaleTracker_PausePointsGainTimers();
    CompleteRefresh(generation, 1099);
    Check(!g_bPointsGainRefreshPending && g_hPointsGainTimer[1] == null);
    Check(g_iPointsGainPending[1] == 20 && g_iRollingPointsCache[1] == 1020);
    WhaleTracker_SchedulePointsGainNotifications();
    Check(g_iPointsGainScheduled[1] == 20 && lastTimerDelay == 5.0);
    WhaleTracker_ResetPointsGainClient(1);
    PrintToServer("[PointsGainProbe] %d checks, %d failures", checks, failures);
}
