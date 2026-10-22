// Calculated-cache observations only: no polling, extra SQL, or frame hooks.
#define WT_POINTS_GAIN_NOTIFY_DELAY 5.0
bool g_bPointsGainBaselineLoaded[MAXPLAYERS + 1];
int g_iPointsGainBaseline[MAXPLAYERS + 1];
int g_iPointsGainPending[MAXPLAYERS + 1];
int g_iPointsGainScheduled[MAXPLAYERS + 1];
Handle g_hPointsGainTimer[MAXPLAYERS + 1];

int WhaleTracker_AddPendingPointsGain(int pending, int gain)
{
    // Multiple qualifying calculations before a round start share one message.
    return gain > 2147483647 - pending ? 2147483647 : pending + gain;
}

void WhaleTracker_AcceptCalculatedPoints(int client, int points, int rank, int matchesUsed)
{
    points = points > 0 ? points : 0;
    rank = rank > 0 ? rank : 0;
    int displayedPoints = rank > 0 ? points : 0;
    if (g_bPointsGainBaselineLoaded[client])
    {
        int gain = displayedPoints - g_iPointsGainBaseline[client];
        if (gain > 9)
        {
            g_iPointsGainPending[client] = WhaleTracker_AddPendingPointsGain(g_iPointsGainPending[client], gain);
        }
    }
    // Initial login/reload is a baseline, never a gain from an invented zero.
    g_bPointsGainBaselineLoaded[client] = true;
    g_iPointsGainBaseline[client] = displayedPoints;
    g_iRollingPointsCache[client] = points;
    g_iRollingRankCache[client] = rank;
    g_iRollingMatchesCache[client] = matchesUsed > 0 ? matchesUsed : 0;
    g_bRollingPointsLoaded[client] = true;
}

void WhaleTracker_ResetPointsGainClient(int client)
{
    delete g_hPointsGainTimer[client];
    g_bPointsGainBaselineLoaded[client] = false;
    g_iPointsGainBaseline[client] = 0;
    g_iPointsGainPending[client] = 0;
    g_iPointsGainScheduled[client] = 0;
}

void WhaleTracker_PausePointsGainTimers()
{
    // Map changes cancel timers, but connected players retain earned notices.
    for (int client = 1; client <= MaxClients; client++)
    {
        if (g_hPointsGainTimer[client] == null) continue;
        delete g_hPointsGainTimer[client];
        g_iPointsGainPending[client] = WhaleTracker_AddPendingPointsGain(
            g_iPointsGainPending[client], g_iPointsGainScheduled[client]);
        g_iPointsGainScheduled[client] = 0;
    }
}

void WhaleTracker_SchedulePointsGainNotifications()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client)
            || g_iPointsGainPending[client] <= 9 || g_hPointsGainTimer[client] != null) continue;
        g_hPointsGainTimer[client] = CreateTimer(WT_POINTS_GAIN_NOTIFY_DELAY,
            Timer_NotifyPointsGain, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
        if (g_hPointsGainTimer[client] != null)
        {
            g_iPointsGainScheduled[client] = g_iPointsGainPending[client];
            g_iPointsGainPending[client] = 0;
        }
    }
}

public Action Timer_NotifyPointsGain(Handle timer, any serial)
{
    int client = GetClientFromSerial(serial);
    if (client <= 0 || g_hPointsGainTimer[client] != timer) return Plugin_Stop;
    g_hPointsGainTimer[client] = null;
    int gain = g_iPointsGainScheduled[client];
    g_iPointsGainScheduled[client] = 0;
    if (!IsClientInGame(client) || IsFakeClient(client) || gain <= 9) return Plugin_Stop;

    CPrintToChat(client, "{gold}[WhaleTracker]{default} Your whalepoints went up by %s%d!",
        gain > 19 ? "{green}" : "{lightgreen}", gain);
    if (GetFeatureStatus(FeatureType_Native, "SaySounds_PlayCommandAs") == FeatureStatus_Available)
    {
        // Never force playback: opt-in, group preferences and volume still apply.
        SaySounds_PlayCommandAs(client, client, WT_BONUS_POINTS_SOUND, false);
    }
    return Plugin_Stop;
}
