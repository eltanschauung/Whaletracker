GlobalForward g_OnAirShot = null;
GlobalForward g_OnLegacyAirshot = null;
GlobalForward g_OnProjectileDirectHit = null;
GlobalForward g_OnMedicDrop = null;
GlobalForward g_OnKillstreak = null;
GlobalForward g_OnKillstreakEnd = null;
GlobalForward g_OnMultikill = null;
GlobalForward g_OnTopScoringPlayerRoundEnd = null;
GlobalForward g_OnAirborneBackstab = null;
GlobalForward g_OnBackstabMilestone = null;
GlobalForward g_OnHeadshotMilestone = null;
GlobalForward g_OnTopScorerKill = null;
GlobalForward g_OnMarketGardenKill = null;
GlobalForward g_OnDemoSyncKill = null;
GlobalForward g_OnSoldierSyncKill = null;
GlobalForward g_OnMedicUberDropKill = null;
GlobalForward g_OnMedicHighUberKill = null;
GlobalForward g_OnMultipleDominations = null;
GlobalForward g_OnRevenge = null;
GlobalForward g_OnMedicAssistMilestone = null;
GlobalForward g_OnMeatshotMilestone = null;
GlobalForward g_OnUberDeployed = null;
GlobalForward g_OnReflectKill = null;
GlobalForward g_OnJuggle = null;
GlobalForward g_OnDropShot = null;

void GameplayEvents_Init()
{
    GameplayEvents_Shutdown();
    g_OnAirShot = new GlobalForward("OnAirShot", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_OnLegacyAirshot = new GlobalForward("WhaleTracker_OnAirshot", ET_Ignore, Param_Cell, Param_Cell);
    g_OnProjectileDirectHit = new GlobalForward("OnProjectileDirectHit", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_OnMedicDrop = new GlobalForward("OnMedicDrop", ET_Ignore, Param_Cell, Param_Cell);
    g_OnKillstreak = new GlobalForward("OnKillstreak", ET_Ignore, Param_Cell, Param_Cell);
    g_OnKillstreakEnd = new GlobalForward("OnKillstreakEnd", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_OnMultikill = new GlobalForward("OnMultikill", ET_Ignore, Param_Cell, Param_Cell);
    g_OnTopScoringPlayerRoundEnd = new GlobalForward("OnTopScoringPlayerRoundEnd", ET_Ignore, Param_String);
    g_OnAirborneBackstab = new GlobalForward("OnAirborneBackstab", ET_Ignore, Param_Cell, Param_Cell);
    g_OnBackstabMilestone = new GlobalForward("OnBackstabMilestone", ET_Ignore, Param_Cell, Param_Cell);
    g_OnHeadshotMilestone = new GlobalForward("OnHeadshotMilestone", ET_Ignore, Param_Cell, Param_Cell);
    g_OnTopScorerKill = new GlobalForward("OnTopScorerKill", ET_Ignore, Param_Cell, Param_Cell);
    g_OnMarketGardenKill = new GlobalForward("OnMarketGardenKill", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_OnDemoSyncKill = new GlobalForward("OnDemoSyncKill", ET_Ignore, Param_Cell, Param_Cell);
    g_OnSoldierSyncKill = new GlobalForward("OnSoldierSyncKill", ET_Ignore, Param_Cell, Param_Cell);
    g_OnMedicUberDropKill = new GlobalForward("OnMedicUberDropKill", ET_Ignore, Param_Cell, Param_Cell);
    g_OnMedicHighUberKill = new GlobalForward("OnMedicHighUberKill", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_OnMultipleDominations = new GlobalForward("OnMultipleDominations", ET_Ignore, Param_Cell);
    g_OnRevenge = new GlobalForward("OnRevenge", ET_Ignore, Param_Cell, Param_Cell);
    g_OnMedicAssistMilestone = new GlobalForward("OnMedicAssistMilestone", ET_Ignore, Param_Cell, Param_Cell);
    g_OnMeatshotMilestone = new GlobalForward("OnMeatshotMilestone", ET_Ignore, Param_Cell, Param_Cell);
    g_OnUberDeployed = new GlobalForward("OnUberDeployed", ET_Ignore, Param_Cell, Param_Cell);
    g_OnReflectKill = new GlobalForward("OnReflectKill", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_OnJuggle = new GlobalForward("OnJuggle", ET_Ignore, Param_Cell, Param_Cell);
    g_OnDropShot = new GlobalForward("OnDropShot", ET_Ignore, Param_Cell, Param_Cell);
}

void GameplayEvents_Shutdown()
{
    delete g_OnAirShot;
    delete g_OnLegacyAirshot;
    delete g_OnProjectileDirectHit;
    delete g_OnMedicDrop;
    delete g_OnKillstreak;
    delete g_OnKillstreakEnd;
    delete g_OnMultikill;
    delete g_OnTopScoringPlayerRoundEnd;
    delete g_OnAirborneBackstab;
    delete g_OnBackstabMilestone;
    delete g_OnHeadshotMilestone;
    delete g_OnTopScorerKill;
    delete g_OnMarketGardenKill;
    delete g_OnDemoSyncKill;
    delete g_OnSoldierSyncKill;
    delete g_OnMedicUberDropKill;
    delete g_OnMedicHighUberKill;
    delete g_OnMultipleDominations;
    delete g_OnRevenge;
    delete g_OnMedicAssistMilestone;
    delete g_OnMeatshotMilestone;
    delete g_OnUberDeployed;
    delete g_OnReflectKill;
    delete g_OnJuggle;
    delete g_OnDropShot;
}

void GameplayEvent_FireTwoCells(GlobalForward event, int first, int second)
{
    if (event == null) return;
    Call_StartForward(event);
    Call_PushCell(first);
    Call_PushCell(second);
    Call_Finish();
}

void GameplayEvent_FireThreeCells(GlobalForward event, int first, int second, int third)
{
    if (event == null) return;
    Call_StartForward(event);
    Call_PushCell(first);
    Call_PushCell(second);
    Call_PushCell(third);
    Call_Finish();
}

void GameplayEvent_FireOneCell(GlobalForward event, int value)
{
    if (event == null) return;
    Call_StartForward(event);
    Call_PushCell(value);
    Call_Finish();
}

void FireLegacyAirShot(int attacker, int victim) { GameplayEvent_FireTwoCells(g_OnLegacyAirshot, attacker, victim); }
void FireAirShot(int attacker, int victim, bool killed) { GameplayEvent_FireThreeCells(g_OnAirShot, attacker, victim, killed); }
void FireProjectileDirectHit(int attacker, int victim, int weapon) { GameplayEvent_FireThreeCells(g_OnProjectileDirectHit, attacker, victim, weapon); }
void FireMedicDrop(int attacker, int medic) { GameplayEvent_FireTwoCells(g_OnMedicDrop, attacker, medic); }
void FireKillstreak(int client, int killstreak) { GameplayEvent_FireTwoCells(g_OnKillstreak, client, killstreak); }
void FireKillstreakEnd(int attacker, int victim, int killstreak) { GameplayEvent_FireThreeCells(g_OnKillstreakEnd, attacker, victim, killstreak); }
void FireMultikill(int client, int kills) { GameplayEvent_FireTwoCells(g_OnMultikill, client, kills); }
void FireAirborneBackstab(int attacker, int victim) { GameplayEvent_FireTwoCells(g_OnAirborneBackstab, attacker, victim); }
void FireBackstabMilestone(int client, int count) { GameplayEvent_FireTwoCells(g_OnBackstabMilestone, client, count); }
void FireHeadshotMilestone(int client, int count) { GameplayEvent_FireTwoCells(g_OnHeadshotMilestone, client, count); }
void FireTopScorerKill(int attacker, int victim) { GameplayEvent_FireTwoCells(g_OnTopScorerKill, attacker, victim); }
void FireMarketGardenKill(int attacker, int victim, int attackerClass) { GameplayEvent_FireThreeCells(g_OnMarketGardenKill, attacker, victim, attackerClass); }
void FireDemoSyncKill(int attacker, int victim) { GameplayEvent_FireTwoCells(g_OnDemoSyncKill, attacker, victim); }
void FireSoldierSyncKill(int attacker, int victim) { GameplayEvent_FireTwoCells(g_OnSoldierSyncKill, attacker, victim); }
void FireMedicUberDropKill(int attacker, int medic) { GameplayEvent_FireTwoCells(g_OnMedicUberDropKill, attacker, medic); }
void FireMedicHighUberKill(int attacker, int medic, int percent) { GameplayEvent_FireThreeCells(g_OnMedicHighUberKill, attacker, medic, percent); }
void FireMultipleDominations(int client) { GameplayEvent_FireOneCell(g_OnMultipleDominations, client); }
void FireRevenge(int client, int victim) { GameplayEvent_FireTwoCells(g_OnRevenge, client, victim); }
void FireMedicAssistMilestone(int medic, int count) { GameplayEvent_FireTwoCells(g_OnMedicAssistMilestone, medic, count); }
void FireMeatshotMilestone(int client, int count) { GameplayEvent_FireTwoCells(g_OnMeatshotMilestone, client, count); }
void FireUberDeployed(int medic, int count) { GameplayEvent_FireTwoCells(g_OnUberDeployed, medic, count); }
void FireReflectKill(int attacker, int victim, bool directHit) { GameplayEvent_FireThreeCells(g_OnReflectKill, attacker, victim, directHit); }
void FireJuggle(int attacker, int victim) { GameplayEvent_FireTwoCells(g_OnJuggle, attacker, victim); }
void FireDropShot(int attacker, int victim) { GameplayEvent_FireTwoCells(g_OnDropShot, attacker, victim); }

void FireTopScoringPlayerRoundEnd(const char[] steamId64)
{
    if (g_OnTopScoringPlayerRoundEnd == null) return;
    Call_StartForward(g_OnTopScoringPlayerRoundEnd);
    Call_PushString(steamId64);
    Call_Finish();
}
