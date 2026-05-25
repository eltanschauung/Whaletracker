bool g_bPlayerTakenDirectHit[MAXPLAYERS + 1];
bool g_bInExplosiveJump[MAXPLAYERS + 1];
int g_iPendingMarketGardenAttacker[MAXPLAYERS + 1];
float g_fPendingMarketGardenTime[MAXPLAYERS + 1];

#define WT_MARKET_GARDEN_KILL_WINDOW 0.25

public void Event_RoundWin(Event event, const char[] name, bool dontBroadcast)
{
    WhaleTracker_RecordRoundStatistics(event);
}

bool IsTopScoringPlayerOnTeam(int client)
{
    if (!IsValidClient(client) || !IsClientInGame(client) || IsFakeClient(client))
    {
        return false;
    }

    int team = GetClientTeam(client);
    if (team != 2 && team != 3)
    {
        return false;
    }

    int clientScore = GetTrackedClientScore(client);
    if (clientScore <= 0)
    {
        return false;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (i == client || !IsValidClient(i) || !IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) != team)
        {
            continue;
        }

        if (GetTrackedClientScore(i) > clientScore)
        {
            return false;
        }
    }

    return true;
}

bool HasMultipleDominationsAfterKill(int client, int victim)
{
    if (!IsValidClient(client) || !IsClientInGame(client) || !HasEntProp(client, Prop_Send, "m_bPlayerDominated"))
    {
        return false;
    }

    int dominationCount = 0;
    bool countedVictim = false;

    for (int target = 1; target <= MaxClients; target++)
    {
        if (target == client || !IsValidClient(target) || !IsClientInGame(target))
        {
            continue;
        }

        if (GetEntProp(client, Prop_Send, "m_bPlayerDominated", _, target) != 0)
        {
            dominationCount++;
            if (target == victim)
            {
                countedVictim = true;
            }
        }
    }

    if (IsValidClient(victim) && !countedVictim)
    {
        dominationCount++;
    }

    return dominationCount > 1;
}

int GetTrackedClientScore(int client)
{
    static int scorePropState = 0;
    if (scorePropState == 2 || (scorePropState == 1 && !HasEntProp(client, Prop_Send, "m_iScore")))
    {
        return GetClientFrags(client);
    }

    if (HasEntProp(client, Prop_Send, "m_iScore"))
    {
        scorePropState = 1;
        return GetEntProp(client, Prop_Send, "m_iScore");
    }

    scorePropState = 2;
    return GetClientFrags(client);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client))
        return;

    g_bPlayerTakenDirectHit[client] = false;
    g_bInExplosiveJump[client] = false;
    ResetMarketGardenKillCandidate(client);
    ResetLifeCounters(g_Stats[client]);
    ResetLifeCounters(g_MapStats[client]);
}

public void Event_ExplosiveJump(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client))
    {
        return;
    }

    g_bInExplosiveJump[client] = true;
}

public void Event_ExplosiveJumpLanded(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client))
    {
        return;
    }

    g_bInExplosiveJump[client] = false;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (entity <= MaxClients || !IsSupstatsDirectHitProjectileClassname(classname))
    {
        return;
    }

    SDKHook(entity, SDKHook_Touch, OnProjectileTouch);
}

public void OnProjectileTouch(int entity, int other)
{
    if (other > 0 && other <= MaxClients)
    {
        g_bPlayerTakenDirectHit[other] = true;
    }
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attackerUserId = event.GetInt("attacker");
    int attacker = GetClientOfUserId(attackerUserId);
    int assister = GetClientOfUserId(event.GetInt("assister"));
    int deathFlags = event.GetInt("death_flags");
    int victimClass = view_as<int>(TF2_GetPlayerClass(victim));
    bool victimIsHuman = IsValidClient(victim) && !IsFakeClient(victim);
    bool attackerIsHuman = IsValidClient(attacker) && !IsFakeClient(attacker) && attacker != victim;
    bool attackerScoredMedicDrop = false;
    bool victimMedicDrop = false;

    if (!(deathFlags & TF_DEATHFLAG_DEADRINGER))
    {
        victimMedicDrop = victimIsHuman && IsMedicDrop(victim);

        if (victimIsHuman && attackerIsHuman && WhaleTracker_IsTrackingEnabled(attacker))
        {
            int custom = event.GetInt("customkill");
            bool backstab = (custom == TF_CUSTOM_BACKSTAB);
            bool medicDrop = victimMedicDrop;

            ApplyKillStats(g_Stats[attacker], backstab, medicDrop);
            ApplyKillStats(g_MapStats[attacker], backstab, medicDrop);
            RegisterMultikill(attacker);
            int killstreak = g_Stats[attacker].currentKillstreak;
            if (killstreak > 0 && killstreak % WHALE_KILLSTREAK_BONUS_INTERVAL == 0)
            {
                FireKillstreakForward(attacker, killstreak);
            }
            if (IsTopScoringPlayerOnTeam(victim))
            {
                ApplyBonusPoints(attacker, 1, true, true, 1.0, "top_score_kill", victim);
            }
            if (ConsumeMarketGardenKill(attacker, victim))
            {
                ApplyBonusPoints(attacker, 1, true, true, 1.0, "market_garden_kill");
            }
            if (victimClass == TF_CLASS_MEDIC)
            {
                g_Stats[attacker].totalMedicKills++;
                // Medic kills are tracked as stats, but no longer award bonus points.
                // ApplyBonusPoints(attacker, 1, true, true, 1.0, "medic_kill");
                if (medicDrop)
                {
                    ApplyBonusPoints(attacker, 3, true, true, 1.0, "medic_uber_drop_kill");
                }
            }
            if (victimClass == TF_CLASS_HEAVY)
            {
                g_Stats[attacker].totalHeavyKills++;
                // Heavy kills are tracked as stats, but no longer award bonus points.
                // ApplyBonusPoints(attacker, 1, true, true, 1.0, "heavy_kill");
            }
            if (deathFlags & TF_DEATHFLAG_KILLERDOMINATION)
            {
                if (HasMultipleDominationsAfterKill(attacker, victim))
                {
                    ApplyBonusPoints(attacker, 1, true, true, 1.0, "multiple_dominations");
                }
            }
            if (deathFlags & TF_DEATHFLAG_KILLERREVENGE)
            {
                ApplyBonusPoints(attacker, 1, true, true, 1.0, "player_revenge", victim);
            }
            attackerScoredMedicDrop = medicDrop;
            MarkClientDirty(attacker);
        }

        if (victimIsHuman && IsValidClient(assister) && assister != victim && WhaleTracker_IsTrackingEnabled(assister))
        {
            ApplyAssistStats(g_Stats[assister]);
            ApplyAssistStats(g_MapStats[assister]);
            if (deathFlags & TF_DEATHFLAG_ASSISTERDOMINATION)
            {
                if (HasMultipleDominationsAfterKill(assister, victim))
                {
                    ApplyBonusPoints(assister, 1, true, true, 1.0, "multiple_dominations");
                }
            }
            if (deathFlags & TF_DEATHFLAG_ASSISTERREVENGE)
            {
                ApplyBonusPoints(assister, 1, true, true, 1.0, "player_revenge", victim);
            }
            MarkClientDirty(assister);
        }

        if (IsValidClient(victim) && WhaleTracker_IsTrackingEnabled(victim))
        {
            int victimKillstreak = g_Stats[victim].currentKillstreak;
            if (attackerIsHuman && victimKillstreak >= WHALE_KILLSTREAK_BONUS_INTERVAL)
            {
                FireKillstreakEndForward(attacker, victim, victimKillstreak);
            }

            if (attackerScoredMedicDrop)
            {
                g_Stats[victim].totalUberDrops++;
                g_MapStats[victim].totalUberDrops++;
            }
            ApplyCumulativeDeathStats(g_Stats[victim], attackerUserId != 0);
            ApplyDeathStats(g_MapStats[victim]);
            MarkClientDirty(victim);
        }

        if (victimMedicDrop)
        {
            AnnounceMedicDrop(attacker, victim);
        }
    }
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
    if (attacker == victim)
        return Plugin_Continue;

    int damageInt = RoundToFloor(damage);
    if (damageInt < 0 || damageInt > 500)
    {
        damageInt = 0;
    }

    // Gate expensive tracking: allow attackers to become eligible after 200 damage dealt and only if not spectator.
    if (IsValidClient(attacker) && !IsFakeClient(attacker) && GetClientTeam(attacker) > 1 && !g_bTrackEligible[attacker])
    {
        if (!WhaleTracker_CheckDamageGate(attacker, damageInt))
        {
            // Still below threshold; skip further processing for this attacker.
            return Plugin_Continue;
        }
    }
    // Victims in spectator are ignored.
    if (IsValidClient(victim) && GetClientTeam(victim) <= 1)
    {
        return Plugin_Continue;
    }

    bool isHeadshot = (damagecustom == TF_CUSTOM_HEADSHOT || damagecustom == TF_CUSTOM_HEADSHOT_DECAPITATION);
    if (isHeadshot && IsValidClient(attacker) && !IsFakeClient(attacker))
    {
        RecordHeadshotEvent(attacker);
    }

    if (CheckIfAfterburn(damagecustom) || CheckIfBleedDmg(damagetype))
        return Plugin_Continue;

    if (damage <= 0.0)
        return Plugin_Continue;

    bool wasDirectHit = false;
    if (IsValidClient(victim))
    {
        wasDirectHit = g_bPlayerTakenDirectHit[victim];
        g_bPlayerTakenDirectHit[victim] = false;
    }

    if (IsValidClient(victim) && !IsFakeClient(victim) && IsValidClient(attacker) && !IsFakeClient(attacker) && WhaleTracker_IsTrackingEnabled(attacker))
    {
        if (IsSupstatsAirshot(attacker, victim, weapon, wasDirectHit))
        {
            g_Stats[attacker].totalAirshots += 1;
            if (g_hAirshotForward != null)
            {
                Call_StartForward(g_hAirshotForward);
                Call_PushCell(attacker);
                Call_PushCell(victim);
                int _ret;
                Call_Finish(_ret);
            }
        }

        if (IsMarketGardenerHit(attacker, weapon))
        {
            g_Stats[attacker].totalMarketGardenHits += 1;
            g_MapStats[attacker].totalMarketGardenHits += 1;
            MarkMarketGardenKillCandidate(attacker, victim);
        }

        g_Stats[attacker].totalDamage += damageInt;
        g_MapStats[attacker].totalDamage += damageInt;
        if (!TrackAccuracyEvent(attacker, weapon, true))
        {
            if (!TrackAccuracyEvent(attacker, inflictor, true))
            {
                int activeWeapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
                if (activeWeapon > MaxClients)
                {
                    TrackAccuracyEvent(attacker, activeWeapon, true);
                }
            }
        }
        MarkClientDirty(attacker);
    }

    if (IsValidClient(victim) && !IsFakeClient(victim) && WhaleTracker_IsTrackingEnabled(victim))
    {
        g_Stats[victim].totalDamageTaken += damageInt;
        g_MapStats[victim].totalDamageTaken += damageInt;
        MarkClientDirty(victim);
    }

    return Plugin_Continue;
}

public Action TF2_CalcIsAttackCritical(int client, int weapon, char[] weaponname, bool& result)
{
    if (!WhaleTracker_IsTrackingEnabled(client))
        return Plugin_Continue;

    if (CheckIfAfterburn(0) || CheckIfBleedDmg(0))
        return Plugin_Continue;

    TrackAccuracyEvent(client, weapon, false);
    return Plugin_Continue;
}

public void Event_PlayerHealed(Event event, const char[] name, bool dontBroadcast)
{
    int healer = GetClientOfUserId(event.GetInt("healer"));
    if (!WhaleTracker_IsTrackingEnabled(healer))
        return;

    int amount = event.GetInt("amount");
    if (amount > 0)
    {
        ApplyHealingStats(g_Stats[healer], amount);
        ApplyHealingStats(g_MapStats[healer], amount);
        MarkClientDirty(healer);
    }
}

public void Event_UberDeployed(Event event, const char[] name, bool dontBroadcast)
{
    int medic = GetClientOfUserId(event.GetInt("userid"));
    if (!WhaleTracker_IsTrackingEnabled(medic))
        return;

    ApplyUberStats(g_Stats[medic]);
    ApplyUberStats(g_MapStats[medic]);
    ApplyBonusPoints(medic, 1, true, true, 1.0, "uber_deployed");
    MarkClientDirty(medic);
}

bool IsMedicDrop(int victim)
{
    if (!IsValidClient(victim) || IsFakeClient(victim))
        return false;

    if (TF2_GetPlayerClass(victim) != TFClass_Medic)
        return false;

    int medigun = -1;
    medigun = GetPlayerWeaponSlot(victim, 1);

    if (medigun <= MaxClients || !IsValidEntity(medigun))
        return false;
    if (!HasEntProp(medigun, Prop_Send, "m_flChargeLevel"))
        return false;

    return (GetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel") >= 1.0);
}

void AnnounceMedicDrop(int attacker, int medic)
{
    if (!IsValidClient(medic) || IsFakeClient(medic))
        return;

    char medicName[256];
    BuildMedicDropDisplayName(medic, medicName, sizeof(medicName));

    if (!IsValidClient(attacker) || IsFakeClient(attacker) || attacker == medic)
    {
        CPrintToChatAll("%s dropped!", medicName);
        FireMedicDropForward(attacker, medic);
        return;
    }

    char attackerName[256];
    BuildMedicDropDisplayName(attacker, attackerName, sizeof(attackerName));

    CPrintToChatAll("%s dropped %s!", attackerName, medicName);
    FireMedicDropForward(attacker, medic);
}

void BuildMedicDropDisplayName(int client, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    char colorTag[32];
    GetClientFiltersNameColorTag(client, colorTag, sizeof(colorTag));
    TrimString(colorTag);

    if (colorTag[0] == '\0')
    {
        strcopy(colorTag, sizeof(colorTag), "gold");
    }
    else if (StrEqual(colorTag, "teamcolor", false) || StrEqual(colorTag, "{teamcolor}", false))
    {
        BuildMedicDropTeamColorTag(client, colorTag, sizeof(colorTag));
    }

    if (colorTag[0] == '{')
    {
        Format(buffer, maxlen, "%s%N{default}", colorTag, client);
        return;
    }

    Format(buffer, maxlen, "{%s}%N{default}", colorTag, client);
}

void BuildMedicDropTeamColorTag(int client, char[] colorTag, int maxlen)
{
    switch (GetClientTeam(client))
    {
        case 2: strcopy(colorTag, maxlen, "{red}");
        case 3: strcopy(colorTag, maxlen, "{blue}");
        default: strcopy(colorTag, maxlen, "{default}");
    }
}

void FireMedicDropForward(int attacker, int medic)
{
    if (g_hMedicDropForward == null)
    {
        return;
    }

    Call_StartForward(g_hMedicDropForward);
    Call_PushCell(attacker);
    Call_PushCell(medic);
    int _ret;
    Call_Finish(_ret);
}

void FireKillstreakForward(int client, int killstreak)
{
    if (g_hKillstreakForward == null)
    {
        return;
    }

    Call_StartForward(g_hKillstreakForward);
    Call_PushCell(client);
    Call_PushCell(killstreak);
    int _ret;
    Call_Finish(_ret);
}

void FireKillstreakEndForward(int attacker, int victim, int killstreak)
{
    if (g_hKillstreakEndForward == null)
    {
        return;
    }

    Call_StartForward(g_hKillstreakEndForward);
    Call_PushCell(attacker);
    Call_PushCell(victim);
    Call_PushCell(killstreak);
    int _ret;
    Call_Finish(_ret);
}

void RegisterMultikill(int client)
{
    float now = GetGameTime();
    float window = 3.0;
    if (g_hMultikillWindow != null)
    {
        window = g_hMultikillWindow.FloatValue;
    }

    if (g_iMultikillChainKills[client] <= 0 || now > g_fMultikillChainExpiresAt[client])
    {
        g_iMultikillChainKills[client] = 1;
    }
    else
    {
        g_iMultikillChainKills[client]++;
    }

    g_fMultikillChainExpiresAt[client] = now + window;

    int kills = g_iMultikillChainKills[client];
    if (kills >= 2 && kills <= WHALE_MULTIKILL_MAX_LEVEL)
    {
        FireMultikillForward(client, kills);
    }
}

void FireMultikillForward(int client, int kills)
{
    if (g_hMultikillForward == null)
    {
        return;
    }

    Call_StartForward(g_hMultikillForward);
    Call_PushCell(client);
    Call_PushCell(kills);
    int _ret;
    Call_Finish(_ret);
}

public void Event_ResetMultikillAll(Event event, const char[] name, bool dontBroadcast)
{
    ResetMultikillAll();
}

void ResetMultikillAll()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        ResetMultikillClient(client);
    }
}

void ResetMultikillClient(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    g_iMultikillChainKills[client] = 0;
    g_fMultikillChainExpiresAt[client] = 0.0;

    ResetMarketGardenKillCandidate(client);
}

bool IsSupstatsAirshot(int attacker, int victim, int weapon, bool wasDirectHit)
{
    if (!IsValidClient(attacker) || IsFakeClient(attacker) || !IsValidClient(victim) || IsFakeClient(victim))
        return false;

    if (GetClientTeam(victim) == GetClientTeam(attacker))
        return false;

    int primary = GetPlayerWeaponSlot(attacker, 0);
    if (primary <= MaxClients || primary != weapon)
    {
        return false;
    }

    TFClassType attackerClass = TF2_GetPlayerClass(attacker);
    if ((attackerClass == TFClass_Soldier || attackerClass == TFClass_DemoMan) && wasDirectHit)
    {
        return IsVictimAirshotEligible(victim);
    }

    if (attackerClass == TFClass_Medic)
    {
        char classname[64];
        GetEntityClassname(weapon, classname, sizeof(classname));
        if (StrEqual(classname, "tf_weapon_crossbow", false))
        {
            return IsVictimAirshotEligible(victim);
        }
    }

    return false;
}

bool IsVictimAirshotEligible(int victim)
{
    int flags = GetEntityFlags(victim);
    if ((flags & (FL_ONGROUND | FL_INWATER)) != 0)
    {
        return false;
    }

    float distance = DistanceAboveGroundBox(victim);
    return distance >= WT_AIRSHOT_MIN_HEIGHT;
}

bool IsSupstatsDirectHitProjectileClassname(const char[] classname)
{
    return StrEqual(classname, "tf_projectile_rocket", false)
        || StrEqual(classname, "tf_projectile_pipe", false);
}

int GetWeaponDefIndexSafe(int weapon)
{
    if (weapon <= MaxClients || !IsValidEntity(weapon) || !HasEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"))
    {
        return -1;
    }

    return GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
}

bool IsMarketGardenerWeapon(int weapon)
{
    int def = GetWeaponDefIndexSafe(weapon);
    return def == WT_MARKET_GARDENER_DEF_INDEX || def == WT_HANDSHAKE_DEF_INDEX;
}

bool IsMarketGardenerHit(int attacker, int weapon)
{
    bool validAttacker = IsValidClient(attacker);
    bool inExplosiveJump = validAttacker ? g_bInExplosiveJump[attacker] : false;

    if (!inExplosiveJump)
    {
        return false;
    }

    if (!validAttacker)
    {
        return false;
    }

    if (IsMarketGardenerWeapon(weapon))
    {
        return true;
    }
    return false;
}

void MarkMarketGardenKillCandidate(int attacker, int victim)
{
    if (!IsValidClient(attacker) || !IsValidClient(victim) || attacker == victim)
    {
        return;
    }

    g_iPendingMarketGardenAttacker[victim] = attacker;
    g_fPendingMarketGardenTime[victim] = GetGameTime();
}

bool ConsumeMarketGardenKill(int attacker, int victim)
{
    if (!IsValidClient(attacker) || !IsValidClient(victim))
    {
        return false;
    }

    bool isMarketGardenKill = g_iPendingMarketGardenAttacker[victim] == attacker
        && g_fPendingMarketGardenTime[victim] > 0.0
        && GetGameTime() - g_fPendingMarketGardenTime[victim] <= WT_MARKET_GARDEN_KILL_WINDOW;

    ResetMarketGardenKillCandidate(victim);
    return isMarketGardenKill;
}

void ResetMarketGardenKillCandidate(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    g_iPendingMarketGardenAttacker[client] = 0;
    g_fPendingMarketGardenTime[client] = 0.0;
}

float DistanceAboveGroundBox(int victim)
{
    float start[3];
    float end[3];
    float hullMins[3] = { -24.0, -24.0, 0.0 };
    float hullMaxs[3] = { 24.0, 24.0, 0.0 };
    float direction[3] = { 0.0, 0.0, -16384.0 };

    GetClientAbsOrigin(victim, start);
    AddVectors(direction, start, end);

    Handle trace = TR_TraceHullFilterEx(start, end, hullMins, hullMaxs, MASK_PLAYERSOLID, TraceEntityFilterPlayer);

    float distance = -1.0;
    if (TR_DidHit(trace))
    {
        TR_GetEndPosition(end, trace);
        distance = GetVectorDistance(start, end, false);
    }
    CloseHandle(trace);
    return distance;
}

public bool TraceEntityFilterPlayer(int entity, int contentsMask)
{
    return entity > MaxClients || !entity;
}

void FormatMatchDuration(int seconds, char[] buffer, int maxlen)
{
    if (maxlen <= 0)
    {
        return;
    }

    if (seconds <= 0)
    {
        strcopy(buffer, maxlen, "0s");
        return;
    }

    int hours = seconds / 3600;
    int minutes = (seconds % 3600) / 60;
    int secs = seconds % 60;

    if (hours > 0)
    {
        Format(buffer, maxlen, "%dh %dm", hours, minutes);
    }
    else if (minutes > 0)
    {
        Format(buffer, maxlen, "%dm %ds", minutes, secs);
    }
    else
    {
        Format(buffer, maxlen, "%ds", secs);
    }
}

int GetWeaponCategoryFromDefIndex(int defIndex)
{
    switch (defIndex)
    {
        case 9, 10, 11, 12, 199, 425, 527, 1153:
            return WeaponCategory_Shotguns;
        case 13, 200, 15029, 669, 45, 448, 772, 1103:
            return WeaponCategory_Scatterguns;
        case 22, 23, 209, 773, 449, 160, 161:
            return WeaponCategory_Pistols;
        case 18, 205, 658, 513, 414, 441, 1104, 730, 228:
            return WeaponCategory_RocketLaunchers;
        case 19, 206, 1151, 308:
            return WeaponCategory_GrenadeLaunchers;
        case 20, 207, 661, 265, 130:
            return WeaponCategory_StickyLaunchers;
        case 14, 201, 664, 402, 230, 851, 752, 526:
            return WeaponCategory_Snipers;
        case 24, 210, 224, 61, 525, 460:
            return WeaponCategory_Revolvers;
    }

    return WeaponCategory_None;
}

stock bool CheckIfAfterburn(int damagecustom)
{
    return (damagecustom == TF_CUSTOM_BURNING || damagecustom == TF_CUSTOM_BURNING_FLARE);
}

stock bool CheckIfBleedDmg(int damageType)
{
    return (damageType & DMG_SLASH) != 0;
}

void SendMatchStatsMessage(int viewer, int target)
{
    if (!IsValidClient(viewer) || IsFakeClient(viewer))
        return;

    if (!IsValidClient(target) || IsFakeClient(target))
    {
        CPrintToChat(viewer, "{green}[WhaleTracker]{default} No valid player selected.");
        return;
    }

    bool targetInGame = IsClientInGame(target);
    if (targetInGame)
    {
        AccumulatePlaytime(target);
    }

    EnsureClientSteamId(target);
    WhaleStats matchStats;
    matchStats = g_MapStats[target];
    bool hasActivity = HasMapActivity(matchStats) || matchStats.playtime > 0;

    if (!targetInGame && !hasActivity)
    {
        CPrintToChat(viewer, "{green}[WhaleTracker]{default} %N has no current match data.", target);
        return;
    }

    char playerName[MAX_NAME_LENGTH];
    if (targetInGame)
    {
        GetClientName(target, playerName, sizeof(playerName));
        RememberMatchPlayerName(matchStats.steamId, playerName);
    }
    else if (!GetStoredMatchPlayerName(matchStats.steamId, playerName, sizeof(playerName)))
    {
        strcopy(playerName, sizeof(playerName), matchStats.steamId);
    }

    char colorTag[32];
    GetClientFiltersNameColorTag(target, colorTag, sizeof(colorTag));

    int kills = matchStats.kills;
    int deaths = matchStats.deaths;
    int assists = matchStats.totalAssists;
    int damage = matchStats.totalDamage;
    int damageTaken = matchStats.totalDamageTaken;
    int healing = matchStats.totalHealing;
    int headshots = matchStats.totalHeadshots;
    int backstabs = matchStats.totalBackstabs;
    int ubers = matchStats.totalUbers;

    int lifetimeKills = g_Stats[target].kills;
    int lifetimeDeaths = g_Stats[target].deaths;
    float lifetimeKd = (lifetimeDeaths > 0) ? float(lifetimeKills) / float(lifetimeDeaths) : float(lifetimeKills);

    float kd = (deaths > 0) ? float(kills) / float(deaths) : float(kills);
    float dpm = 0.0, dtpm = 0.0;
    float minutes = (matchStats.playtime > 0) ? float(matchStats.playtime) / 60.0 : 0.0;
    if (minutes > 1.0)
    {
        dpm = (minutes > 0.0) ? float(damage) / minutes : 0.0;
        dtpm = (minutes > 0.0) ? float(damageTaken) / minutes : 0.0;
    }

    char timeBuffer[32];
    FormatMatchDuration(matchStats.playtime, timeBuffer, sizeof(timeBuffer));

    CPrintToChat(viewer, "{green}[WhaleTracker]{default} {%s}%s{default} — This Match: K %d | D %d | KD %.2f | A %d | Dmg %d | Dmg/min %.1f",
        colorTag, playerName, kills, deaths, kd, assists, damage, dpm);
    CPrintToChat(viewer, "Taken %d | Taken/min %.1f | Heal %d | HS %d | BS %d | Ubers %d | Time %s",
        damageTaken, dtpm, healing, headshots, backstabs, ubers, timeBuffer);
    CPrintToChat(viewer, "{green}[WhaleTracker]{default} Lifetime Kills: %d | Deaths %d | KD: %.2f", lifetimeKills, lifetimeDeaths, lifetimeKd);
    CPrintToChat(viewer, "{green}[WhaleTracker]{default} Visit kogasa.tf/stats for full");
}
