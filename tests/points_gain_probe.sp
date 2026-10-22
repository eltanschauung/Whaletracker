#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>

int g_iRollingPointsCache[MAXPLAYERS + 1], g_iRollingRankCache[MAXPLAYERS + 1];
int g_iRollingMatchesCache[MAXPLAYERS + 1];
bool g_bRollingPointsLoaded[MAXPLAYERS + 1];
int checks, failures, prints, sounds;
int currentSerial = 1001;
bool optedIn = true, apiAvailable = true;
char printed[256];
#define WT_BONUS_POINTS_SOUND "xp_gain"

bool TestInGame(int client) { return client == 1; }
bool TestFake(int client) { return client != 1; }
int TestSerial(int client) { return currentSerial; }
int TestFromSerial(int serial) { return serial == currentSerial ? 1 : 0; }
Handle TestTimer(float interval, Timer callback, any serial, int flags)
{
    if (interval != 5.0 || flags != TIMER_FLAG_NO_MAPCHANGE || serial != currentSerial) failures++;
    return CreateDataPack(); // Valid disposable handle; no real scheduling.
}
FeatureStatus TestFeature(FeatureType type, const char[] name)
{
    return apiAvailable ? FeatureStatus_Available : FeatureStatus_Unavailable;
}
void CPrintToChat(int client, const char[] message, any ...)
{
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
#include "points_gain_whaletracker.sp"

void Check(bool value) { checks++; if (!value) failures++; }
void FireNotice()
{
    Handle timer = g_hPointsGainTimer[1];
    Check(timer != null);
    Timer_NotifyPointsGain(timer, currentSerial);
    delete timer;
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
    Check(g_iPointsGainScheduled[1] == 10 && g_iPointsGainPending[1] == 20);
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
    PrintToServer("[PointsGainProbe] %d checks, %d failures", checks, failures);
}
