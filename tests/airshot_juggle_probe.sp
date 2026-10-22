#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>

int g_iPendingJuggleAttackerUserId[MAXPLAYERS + 1];
int g_iJuggleProjectileRef[MAXPLAYERS + 1];
float g_fPendingJuggleDirectHitTime[MAXPLAYERS + 1];
int g_iPendingAirShotAttackerUserId[MAXPLAYERS + 1];
bool g_bPendingAirShotIsJuggle[MAXPLAYERS + 1];
bool eligible = true, scout;
float now = 10.0;
int forwards, timers, checks, failures;

#define TFClass_Scout 1
#define GetClientUserId TestUserId
#define GetGameTime TestTime
#define TF2_GetPlayerClass TestClass
#define CreateTimer TestTimer
int TestUserId(int client) { return client + 100; }
float TestTime() { return now; }
int TestClass(int client) { return scout ? TFClass_Scout : 3; }
bool IsValidClient(int client) { return client >= 1 && client <= 3; }
bool IsVictimAirshotEligible(int client) { return eligible; }
float WT_GetJuggleWindow() { return 1.5; }
void FireJuggle(int attacker, int victim) { forwards++; }
Handle TestTimer(float interval, Timer callback, any data) { timers++; return null; }
public Action Timer_BroadcastAirShot(Handle timer, any data) { return Plugin_Stop; }

#include "airshot_juggle_under_test.inc"

void Check(bool result) { checks++; if (!result) failures++; }

public void OnPluginStart() {
    Check(!RegisterJuggleDirectHit(1, 2, 1001));
    now += 0.2;
    Check(!RegisterJuggleDirectHit(1, 2, 1001)); // Same projectile is not a juggle.
    now += 0.2;
    Check(RegisterJuggleDirectHit(1, 2, 1002));
    Check(forwards == 1 && g_iPendingJuggleAttackerUserId[2] == 0);
    QueueAirShotBroadcast(1, 2);
    Check(!g_bPendingAirShotIsJuggle[2] && timers == 1);
    QueueAirShotBroadcast(1, 2, true);
    QueueAirShotBroadcast(1, 2, false);
    Check(g_bPendingAirShotIsJuggle[2] && timers == 1);
    ResetAirShotBroadcastState(2);
    Check(!g_bPendingAirShotIsJuggle[2] && g_iPendingAirShotAttackerUserId[2] == 0);
    QueueAirShotBroadcast(1, 2, true);
    QueueAirShotBroadcast(3, 2, false);
    Check(!g_bPendingAirShotIsJuggle[2] && g_iPendingAirShotAttackerUserId[2] == TestUserId(3));
    RegisterJuggleDirectHit(1, 2, 1003);
    now += 1.6;
    Check(!RegisterJuggleDirectHit(1, 2, 1004)); // Expired window.
    Check(!RegisterJuggleDirectHit(3, 2, 1005)); // Different attacker.
    eligible = false;
    Check(!RegisterJuggleDirectHit(3, 2, 1006));
    Check(g_iPendingJuggleAttackerUserId[2] == 0);
    eligible = true;
    scout = true;
    Check(!RegisterJuggleDirectHit(1, 2, 1007));
    Check(forwards == 1);
    PrintToServer("[AirshotJuggleProbe] %d checks, %d failures", checks, failures);
}
