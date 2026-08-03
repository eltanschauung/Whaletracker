bool g_bPlayerTakenDirectHit[MAXPLAYERS + 1];
bool g_bPlayerTakenReflectDirectHit[MAXPLAYERS + 1];
bool g_bInExplosiveJump[MAXPLAYERS + 1];
int g_iPendingMarketGardenAttacker[MAXPLAYERS + 1];
float g_fPendingMarketGardenTime[MAXPLAYERS + 1];
int g_iPendingReflectAttacker[MAXPLAYERS + 1];
bool g_bPendingReflectDirectHit[MAXPLAYERS + 1];
float g_fPendingReflectTime[MAXPLAYERS + 1];
int g_iPendingDemoSyncAttacker[MAXPLAYERS + 1];
float g_fPendingDemoSyncStickyTime[MAXPLAYERS + 1];
int g_iPendingDemoSyncKillAttacker[MAXPLAYERS + 1];
float g_fPendingDemoSyncKillTime[MAXPLAYERS + 1];
int g_iPendingSoldierSyncAttacker[MAXPLAYERS + 1];
float g_fPendingSoldierSyncRocketTime[MAXPLAYERS + 1];
int g_iPendingSoldierSyncKillAttacker[MAXPLAYERS + 1];
float g_fPendingSoldierSyncKillTime[MAXPLAYERS + 1];
int g_iPendingJuggleAttackerUserId[MAXPLAYERS + 1];
float g_fPendingJuggleDirectHitTime[MAXPLAYERS + 1];
char g_sRoundTopScoringSteamId[STEAMID64_LEN];
int g_iRoundTopScoringScore = 0;

public void Event_RoundWin(Event event, const char[] name, bool dontBroadcast)
{
    AwardRoundTopScoringPlayerBonus();
    WhaleTracker_RecordRoundStatistics(event);
}

bool ShouldAwardTopScoringPlayerBonus()
{
    int realPlayers = WhaleTracker_GetCurrentPlayerCount();
    return realPlayers >= 10 && realPlayers >= WT_GetTopScoreMinPlayers();
}

bool IsTopScoringEnemyPlayer(int attacker, int victim)
{
    if (!IsValidClient(attacker) || !IsClientInGame(attacker) || IsFakeClient(attacker))
    {
        return false;
    }

    int attackerTeam = GetClientTeam(attacker);
    int victimTeam = GetClientTeam(victim);
    if ((attackerTeam != WT_TEAM_RED && attackerTeam != WT_TEAM_BLUE)
        || (victimTeam != WT_TEAM_RED && victimTeam != WT_TEAM_BLUE)
        || attackerTeam == victimTeam)
    {
        return false;
    }

    return IsTopScoringPlayerOnTeam(victim);
}

bool IsTopScoringPlayerOnTeam(int client)
{
    if (!IsValidClient(client) || !IsClientInGame(client) || IsFakeClient(client))
    {
        return false;
    }

    int team = GetClientTeam(client);
    if (team != WT_TEAM_RED && team != WT_TEAM_BLUE)
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

void ResetRoundTopScoringPlayer()
{
    g_sRoundTopScoringSteamId[0] = '\0';
    g_iRoundTopScoringScore = 0;
}

void UpdateRoundTopScoringPlayerCandidate(int client)
{
    if (!IsValidClient(client) || !IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    int team = GetClientTeam(client);
    if (team != WT_TEAM_RED && team != WT_TEAM_BLUE)
    {
        return;
    }

    int score = GetTrackedClientScore(client);
    if (score <= g_iRoundTopScoringScore)
    {
        return;
    }

    char steamId[STEAMID64_LEN];
    if (!GetClientAuthId(client, AuthId_SteamID64, steamId, sizeof(steamId)) || steamId[0] == '\0')
    {
        return;
    }

    strcopy(g_sRoundTopScoringSteamId, sizeof(g_sRoundTopScoringSteamId), steamId);
    g_iRoundTopScoringScore = score;
}

void RefreshRoundTopScoringPlayerCandidate()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        UpdateRoundTopScoringPlayerCandidate(i);
    }
}

void AwardRoundTopScoringPlayerBonus()
{
    if (!ShouldAwardTopScoringPlayerBonus())
    {
        return;
    }

    RefreshRoundTopScoringPlayerCandidate();
    if (g_sRoundTopScoringSteamId[0] == '\0' || g_iRoundTopScoringScore <= 0)
    {
        return;
    }

    ApplyBonusPointsSteamId(g_sRoundTopScoringSteamId, 3, true, true, "top_scoring_player", 2);
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
    int resource = GetPlayerResourceEntity();
    if (resource != -1)
    {
        if (HasEntProp(resource, Prop_Send, "m_iTotalScore"))
        {
            return GetEntProp(resource, Prop_Send, "m_iTotalScore", _, client);
        }

        if (HasEntProp(resource, Prop_Send, "m_iScore"))
        {
            return GetEntProp(resource, Prop_Send, "m_iScore", _, client);
        }
    }

    return GetClientFrags(client);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client))
        return;

    g_bPlayerTakenDirectHit[client] = false;
    g_bPlayerTakenReflectDirectHit[client] = false;
    g_bInExplosiveJump[client] = false;
    ResetMarketGardenKillCandidate(client);
    ResetReflectKillCandidate(client);
    ResetDemoSyncState(client);
    ResetSoldierSyncState(client);
    ResetJuggleState(client);
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
    if (entity <= MaxClients)
    {
        return;
    }

    if (IsSupstatsDirectHitProjectileClassname(classname) || IsReflectBonusProjectileClassname(classname))
    {
        SDKHook(entity, SDKHook_Touch, OnProjectileTouch);
    }

    if (StrEqual(classname, "tf_projectile_healing_bolt", false))
    {
        SDKHook(entity, SDKHook_Touch, OnCrossbowBoltTouch);
    }
}

public void OnProjectileTouch(int entity, int other)
{
    if (other > 0 && other <= MaxClients)
    {
        char classname[64];
        GetEntityClassname(entity, classname, sizeof(classname));

        if (IsSupstatsDirectHitProjectileClassname(classname))
        {
            g_bPlayerTakenDirectHit[other] = true;
        }

        if (IsReflectBonusProjectileClassname(classname))
        {
            g_bPlayerTakenReflectDirectHit[other] = true;
        }
    }
}

public void OnCrossbowBoltTouch(int entity, int other)
{
    if (!IsValidClient(other) || IsFakeClient(other))
    {
        return;
    }

    int attacker = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
    if (!IsValidClient(attacker) || IsFakeClient(attacker) || !WhaleTracker_IsTrackingEnabled(attacker))
    {
        return;
    }

    if (GetClientTeam(attacker) != GetClientTeam(other))
    {
        return;
    }

    int weapon = -1;
    if (HasEntProp(entity, Prop_Send, "m_hLauncher"))
    {
        weapon = GetEntPropEnt(entity, Prop_Send, "m_hLauncher");
    }

    if (IsMedicCrossbowHit(attacker, other, weapon))
    {
        RecordCrossbowHit(attacker);
        if (IsVictimAirshotEligible(other))
        {
            RecordSupstatsAirshot(attacker, other);
        }
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
    bool victimUberBonusEligible = true;
    int victimUberPercent = -1;

    if (!(deathFlags & TF_DEATHFLAG_DEADRINGER))
    {
        if (victimIsHuman && victimClass == TF_CLASS_MEDIC)
        {
            victimUberPercent = GetMedicUberPercent(victim);
            victimUberBonusEligible = IsMedicUberBonusEligible(victim);
        }
        victimMedicDrop = victimIsHuman && IsMedicDrop(victim);

        if (victimIsHuman && attackerIsHuman && WhaleTracker_IsTrackingEnabled(attacker))
        {
            int custom = event.GetInt("customkill");
            bool backstab = (custom == TF_CUSTOM_BACKSTAB);
            bool medicDrop = victimMedicDrop;

            if (backstab && DistanceAboveGroundBox(attacker) >= WT_GetAirborneBackstabMinHeight())
            {
                ApplyBonusPoints(attacker, 1, true, true, WT_BONUS_CHANCE_ALWAYS, "Airborne backstab", victim, WT_GetBonusDefaultDelay(), 3);
            }

            ApplyKillStats(g_Stats[attacker], backstab, medicDrop);
            ApplyKillStats(g_MapStats[attacker], backstab, medicDrop);
            WhaleTracker_CheckPlaytimeMilestones(attacker);
            RegisterMultikill(attacker);
            int killstreak = g_Stats[attacker].currentKillstreak;
            int killstreakBonusInterval = WT_GetKillstreakBonusInterval();
            if (killstreak > 0 && killstreak % killstreakBonusInterval == 0)
            {
                FireKillstreakForward(attacker, killstreak);
            }
            if (ShouldAwardTopScoringPlayerBonus() && IsTopScoringEnemyPlayer(attacker, victim))
            {
                ApplyBonusPoints(attacker, 1, true, true, WT_BONUS_CHANCE_ALWAYS, "top_score_kill", victim, WT_GetBonusDefaultDelay(), 10);
            }
            if (ConsumeMarketGardenKill(attacker, victim))
            {
                char marketGardenType[32];
                GetMarketGardenKillBonusType(attacker, marketGardenType, sizeof(marketGardenType));
                ApplyBonusPoints(attacker, 1, true, true, WT_BONUS_CHANCE_ALWAYS, marketGardenType, 0, WT_GetBonusDefaultDelay(), 5);
            }
            bool reflectDirectHit = false;
            if (ConsumeReflectKill(attacker, victim, reflectDirectHit))
            {
                AwardReflectBonus(attacker, reflectDirectHit);
            }
            if (ConsumeDemoSyncKill(attacker, victim))
            {
                ApplyBonusPoints(attacker, 1, true, true, WT_BONUS_CHANCE_ALWAYS, "demo_sync_kill", 0, WT_GetBonusDefaultDelay(), 3);
            }
            if (ConsumeSoldierSyncKill(attacker, victim))
            {
                ApplyBonusPoints(attacker, 2, true, true, WT_BONUS_CHANCE_ALWAYS, "soldier_sync_kill", 0, WT_GetBonusDefaultDelay(), 3);
            }
            if (victimClass == TF_CLASS_MEDIC)
            {
                if (medicDrop && victimUberBonusEligible)
                {
                    ApplyBonusPoints(attacker, 3, true, true, WT_BONUS_CHANCE_ALWAYS, "medic_uber_drop_kill", 0, WT_GetBonusDefaultDelay(), 2);
                }
                if (victimUberBonusEligible && victimUberPercent >= 90)
                {
                    char reason[64];
                    FormatEx(reason, sizeof(reason), "Medic high Übercharge kill (%d%%)", victimUberPercent);
                    ApplyBonusPoints(attacker, 1, true, true, WT_BONUS_CHANCE_ALWAYS, reason, victim, WT_GetBonusDefaultDelay(), 2);
                }
            }
            if (deathFlags & TF_DEATHFLAG_KILLERDOMINATION)
            {
                if (HasMultipleDominationsAfterKill(attacker, victim))
                {
                    ApplyBonusPoints(attacker, 1, true, true, WT_BONUS_CHANCE_ALWAYS, "multiple_dominations", 0, WT_GetBonusDefaultDelay(), 3);
                }
            }
            if (deathFlags & TF_DEATHFLAG_KILLERREVENGE)
            {
                ApplyBonusPoints(attacker, 1, true, true, WT_BONUS_CHANCE_ALWAYS, "player_revenge", victim, WT_GetBonusDefaultDelay(), 3);
            }
            attackerScoredMedicDrop = medicDrop;
            MarkClientDirty(attacker);
        }

        if (victimIsHuman && IsValidClient(assister) && assister != victim && WhaleTracker_IsTrackingEnabled(assister))
        {
            ApplyAssistStats(g_Stats[assister]);
            ApplyAssistStats(g_MapStats[assister]);
            int assistsLife = g_Stats[assister].currentAssistsLife;
            if (view_as<int>(TF2_GetPlayerClass(assister)) == TF_CLASS_MEDIC
                && assistsLife > 0
                && assistsLife % WT_MEDIC_ASSISTS_LIFE_BONUS_INTERVAL == 0)
            {
                char reason[32];
                Format(reason, sizeof(reason), "Assists: %d", assistsLife);
                ApplyBonusPoints(assister, 1, true, true, WT_BONUS_CHANCE_ALWAYS, reason, 0, WT_GetBonusDefaultDelay(), 4);
            }
            if (deathFlags & TF_DEATHFLAG_ASSISTERDOMINATION)
            {
                if (HasMultipleDominationsAfterKill(assister, victim))
                {
                    ApplyBonusPoints(assister, 1, true, true, WT_BONUS_CHANCE_ALWAYS, "multiple_dominations", 0, WT_GetBonusDefaultDelay(), 3);
                }
            }
            if (deathFlags & TF_DEATHFLAG_ASSISTERREVENGE)
            {
                ApplyBonusPoints(assister, 1, true, true, WT_BONUS_CHANCE_ALWAYS, "player_revenge", victim, WT_GetBonusDefaultDelay(), 3);
            }
            MarkClientDirty(assister);
        }

        if (IsValidClient(victim) && WhaleTracker_IsTrackingEnabled(victim))
        {
            int victimKillstreak = g_Stats[victim].currentKillstreak;
            if (attackerIsHuman && victimKillstreak >= WT_GetKillstreakBonusInterval())
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
        if (victimUberPercent >= 90 && victimUberPercent <= 99)
        {
            AnnounceHighUberDeath(victim, victimUberPercent);
        }

        RefreshRoundTopScoringPlayerCandidate();
    }
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
    if (attacker == victim)
        return Plugin_Continue;

    int damageInt = RoundToFloor(damage);
    if (damageInt < 0 || damageInt > WT_GetDamageSanityMax())
    {
        damageInt = 0;
    }

    bool wasDirectHit = false;
    bool wasReflectDirectHit = false;
    if (IsValidClient(victim))
    {
        wasDirectHit = g_bPlayerTakenDirectHit[victim];
        wasReflectDirectHit = g_bPlayerTakenReflectDirectHit[victim];
        g_bPlayerTakenDirectHit[victim] = false;
        g_bPlayerTakenReflectDirectHit[victim] = false;
    }

    bool reflectBonusEligible = IsReflectBonusDamage(attacker, victim, inflictor);

    // Gate expensive tracking until an attacker has dealt enough damage and is not spectator.
    if (IsValidClient(attacker) && !IsFakeClient(attacker) && GetClientTeam(attacker) >= WT_TEAM_FIRST_PLAYING && !g_bTrackEligible[attacker])
    {
        if (!WhaleTracker_CheckDamageGate(attacker, damageInt) && !reflectBonusEligible)
        {
            // Still below threshold; skip further processing for this attacker.
            return Plugin_Continue;
        }
    }
    // Victims in spectator are ignored.
    if (IsValidClient(victim) && GetClientTeam(victim) < WT_TEAM_FIRST_PLAYING)
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

    if (IsValidClient(victim) && !IsFakeClient(victim) && IsValidClient(attacker) && !IsFakeClient(attacker) && WhaleTracker_IsTrackingEnabled(attacker))
    {
        if (GetClientTeam(attacker) != GetClientTeam(victim))
        {
            if (reflectBonusEligible)
            {
                MarkReflectKillCandidate(attacker, victim, wasReflectDirectHit);
            }

            if (IsWeaponClass(weapon, "tf_weapon_pipebomblauncher"))
            {
                MarkDemoSyncStickyDamage(attacker, victim);
            }

            bool isRocketLauncherDamage = IsSoldierSyncRocketLauncherDamage(attacker, weapon);
            if (IsValidProjectileDirectHit(attacker, victim, weapon, wasDirectHit))
            {
                FireProjectileDirectHitForward(attacker, victim, weapon);
                RegisterJuggleDirectHit(attacker, victim);
                if (IsWeaponClass(weapon, "tf_weapon_grenadelauncher"))
                {
                    MarkDemoSyncKillCandidate(attacker, victim);
                }
            }

            if (isRocketLauncherDamage)
            {
                MarkSoldierSyncKillCandidate(attacker, victim);
                MarkSoldierSyncRocketDamage(attacker, victim);
            }
        }

        if (IsMedicCrossbowHit(attacker, victim, weapon))
        {
            RecordCrossbowHit(attacker);
        }

        if (IsSupstatsAirshot(attacker, victim, weapon, wasDirectHit, reflectBonusEligible && wasReflectDirectHit))
        {
            RecordSupstatsAirshot(attacker, victim);
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

public void TF2Shotgun_OnPelletShot(int attacker, int victim, int pellets, int total, bool kill)
{
    if (pellets != 10 || total != 10
        || !IsValidClient(attacker) || IsFakeClient(attacker)
        || !IsValidClient(victim) || IsFakeClient(victim)
        || attacker == victim || !WhaleTracker_IsTrackingEnabled(attacker))
    {
        return;
    }

    g_Stats[attacker].totalMeatshots++;
    MarkClientDirty(attacker);
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
    if (WhaleTracker_IsRoundRunning() && IsMedicUberBonusEligible(medic))
    {
        ApplyBonusPoints(medic, 1, true, true, WT_BONUS_CHANCE_ALWAYS, "uber_deployed", 0, WT_GetBonusDefaultDelay(), 4);
    }
    MarkClientDirty(medic);
}

bool IsMedicUberBonusEligible(int medic)
{
    if (!IsValidClient(medic) || IsFakeClient(medic) || TF2_GetPlayerClass(medic) != TFClass_Medic)
    {
        return false;
    }

    int medigun = GetPlayerWeaponSlot(medic, 1);
    int defIndex = GetWeaponDefIndexSafe(medigun);
    return defIndex != WT_VACCINATOR_DEF_INDEX;
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

int GetMedicUberPercent(int medic)
{
    if (!IsValidClient(medic) || IsFakeClient(medic) || TF2_GetPlayerClass(medic) != TFClass_Medic)
    {
        return -1;
    }

    int medigun = GetPlayerWeaponSlot(medic, 1);
    if (medigun <= MaxClients || !IsValidEntity(medigun) || !HasEntProp(medigun, Prop_Send, "m_flChargeLevel"))
    {
        return -1;
    }

    int percent = RoundToFloor(GetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel") * 100.0);
    return percent > 100 ? 100 : percent;
}

void AnnounceHighUberDeath(int medic, int percent)
{
    char medicName[256];
    BuildMedicDropDisplayName(medic, medicName, sizeof(medicName));
    CPrintToChatAll("%s died with %d%% Über!", medicName, percent);
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
        case WT_TEAM_RED: strcopy(colorTag, maxlen, "{red}");
        case WT_TEAM_BLUE: strcopy(colorTag, maxlen, "{blue}");
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
    float window = WT_GetMultikillWindow();

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
    if (kills >= 2 && kills <= 5)
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

void FireProjectileDirectHitForward(int attacker, int victim, int weapon)
{
    if (g_hProjectileDirectHitForward == null)
    {
        return;
    }

    Call_StartForward(g_hProjectileDirectHitForward);
    Call_PushCell(attacker);
    Call_PushCell(victim);
    Call_PushCell(weapon);
    int _ret;
    Call_Finish(_ret);
}

public void Event_ResetMultikillAll(Event event, const char[] name, bool dontBroadcast)
{
    ResetRoundTopScoringPlayer();
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
    ResetReflectKillCandidate(client);
}

bool IsSupstatsAirshot(int attacker, int victim, int weapon, bool wasDirectHit, bool wasReflectedDirectHit = false)
{
    if (!IsValidClient(attacker) || IsFakeClient(attacker) || !IsValidClient(victim) || IsFakeClient(victim))
        return false;

    if (wasReflectedDirectHit && TF2_GetPlayerClass(attacker) == TFClass_Pyro
        && GetClientTeam(victim) != GetClientTeam(attacker))
    {
        return IsVictimAirshotEligible(victim);
    }

    int primary = GetPlayerWeaponSlot(attacker, 0);
    if (primary <= MaxClients || primary != weapon)
    {
        return false;
    }

    TFClassType attackerClass = TF2_GetPlayerClass(attacker);
    if ((attackerClass == TFClass_Soldier || attackerClass == TFClass_DemoMan) && wasDirectHit)
    {
        if (GetClientTeam(victim) == GetClientTeam(attacker))
        {
            return false;
        }

        return IsVictimAirshotEligible(victim);
    }

    return IsMedicCrossbowAirshot(attacker, victim, weapon);
}

bool IsMedicCrossbowAirshot(int attacker, int victim, int weapon)
{
    return IsMedicCrossbowHit(attacker, victim, weapon) && IsVictimAirshotEligible(victim);
}

bool IsMedicCrossbowHit(int attacker, int victim, int weapon)
{
    if (!IsValidClient(attacker) || IsFakeClient(attacker) || !IsValidClient(victim) || IsFakeClient(victim))
        return false;

    if (TF2_GetPlayerClass(attacker) != TFClass_Medic)
        return false;

    int primary = GetPlayerWeaponSlot(attacker, 0);
    if (primary <= MaxClients || primary != weapon)
    {
        return false;
    }

    char classname[64];
    GetEntityClassname(weapon, classname, sizeof(classname));
    if (!StrEqual(classname, "tf_weapon_crossbow", false))
    {
        return false;
    }

    return true;
}

void RecordCrossbowHit(int attacker)
{
    g_Stats[attacker].totalCrossbowHits += 1;
    MarkClientDirty(attacker);
}

void RecordSupstatsAirshot(int attacker, int victim)
{
    g_Stats[attacker].totalAirshots += 1;
    g_MapStats[attacker].totalAirshots += 1;
    if (g_hAirshotForward != null)
    {
        Call_StartForward(g_hAirshotForward);
        Call_PushCell(attacker);
        Call_PushCell(victim);
        int _ret;
        Call_Finish(_ret);
    }
}

bool IsVictimAirshotEligible(int victim)
{
    int flags = GetEntityFlags(victim);
    if ((flags & (FL_ONGROUND | FL_INWATER)) != 0)
    {
        return false;
    }

    float distance = DistanceAboveGroundBox(victim);
    return distance >= WT_GetAirshotMinHeight();
}

bool IsSupstatsDirectHitProjectileClassname(const char[] classname)
{
    return StrEqual(classname, "tf_projectile_rocket", false)
        || StrEqual(classname, "tf_projectile_pipe", false);
}

bool IsReflectBonusProjectileClassname(const char[] classname)
{
    return StrEqual(classname, "tf_projectile_arrow", false)
        || StrEqual(classname, "tf_projectile_healing_bolt", false)
        || StrEqual(classname, "tf_projectile_pipe", false)
        || StrEqual(classname, "tf_projectile_pipe_remote", false)
        || StrEqual(classname, "tf_projectile_rocket", false)
        || StrEqual(classname, "tf_projectile_sentryrocket", false)
        || StrEqual(classname, "tf_projectile_stun_ball", false);
}

bool IsReflectBonusInflictor(int inflictor)
{
    if (inflictor <= MaxClients || !IsValidEntity(inflictor))
    {
        return false;
    }

    char classname[64];
    GetEntityClassname(inflictor, classname, sizeof(classname));
    return IsReflectBonusProjectileClassname(classname)
        && HasEntProp(inflictor, Prop_Send, "m_iDeflected")
        && GetEntProp(inflictor, Prop_Send, "m_iDeflected") > 0;
}

bool IsReflectBonusDamage(int attacker, int victim, int inflictor)
{
    if (!IsValidClient(attacker) || IsFakeClient(attacker) || !IsValidClient(victim) || IsFakeClient(victim))
    {
        return false;
    }

    if (!WhaleTracker_IsTrackingEnabled(attacker) || TF2_GetPlayerClass(attacker) != TFClass_Pyro)
    {
        return false;
    }

    if (GetClientTeam(attacker) == GetClientTeam(victim))
    {
        return false;
    }

    return IsReflectBonusInflictor(inflictor);
}

void AwardReflectBonus(int attacker, bool wasDirectHit)
{
    ApplyBonusPoints(attacker, 1, true, true, WT_BONUS_CHANCE_ALWAYS, "reflect", 0, WT_GetBonusDefaultDelay(), 0);

    if (wasDirectHit)
    {
        ApplyBonusPoints(attacker, 2, true, true, WT_BONUS_CHANCE_ALWAYS, "reflect_direct_hit", 0, WT_GetBonusDefaultDelay(), 3);
    }
}

void MarkReflectKillCandidate(int attacker, int victim, bool wasDirectHit)
{
    if (!IsValidClient(attacker) || !IsValidClient(victim) || attacker == victim)
    {
        return;
    }

    g_iPendingReflectAttacker[victim] = attacker;
    g_bPendingReflectDirectHit[victim] = wasDirectHit;
    g_fPendingReflectTime[victim] = GetGameTime();
}

bool ConsumeReflectKill(int attacker, int victim, bool &wasDirectHit)
{
    wasDirectHit = false;
    if (!IsValidClient(attacker) || !IsValidClient(victim))
    {
        return false;
    }

    if (g_iPendingReflectAttacker[victim] != attacker)
    {
        return false;
    }

    if (GetGameTime() - g_fPendingReflectTime[victim] > WT_GetSyncKillConfirmWindow())
    {
        ResetReflectKillCandidate(victim);
        return false;
    }

    wasDirectHit = g_bPendingReflectDirectHit[victim];
    ResetReflectKillCandidate(victim);
    return true;
}

void ResetReflectKillCandidate(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    g_iPendingReflectAttacker[client] = 0;
    g_bPendingReflectDirectHit[client] = false;
    g_fPendingReflectTime[client] = 0.0;
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

void GetMarketGardenKillBonusType(int client, char[] type, int maxlen)
{
    if (IsValidClient(client) && TF2_GetPlayerClass(client) == TFClass_DemoMan)
    {
        strcopy(type, maxlen, "market_garden_kill_demoman");
        return;
    }

    strcopy(type, maxlen, "market_garden_kill");
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
        && GetGameTime() - g_fPendingMarketGardenTime[victim] <= WT_GetMarketGardenKillWindow();

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

bool IsWeaponClass(int weapon, const char[] expectedClassname)
{
    if (weapon <= MaxClients || !IsValidEntity(weapon))
    {
        return false;
    }

    char classname[64];
    GetEntityClassname(weapon, classname, sizeof(classname));
    return StrEqual(classname, expectedClassname, false);
}

bool IsSoldierSyncRocketLauncherDamage(int attacker, int weapon)
{
    if (!IsValidClient(attacker) || !g_bInExplosiveJump[attacker])
    {
        return false;
    }

    if (!IsWeaponClass(weapon, "tf_weapon_rocketlauncher"))
    {
        return false;
    }

    return GetWeaponDefIndexSafe(weapon) != WT_SOLDIER_SYNC_EXCLUDED_DEF_INDEX;
}

bool IsValidProjectileDirectHit(int attacker, int victim, int weapon, bool wasDirectHit)
{
    if (!wasDirectHit || !IsValidClient(attacker) || IsFakeClient(attacker) || !IsValidClient(victim) || IsFakeClient(victim))
    {
        return false;
    }

    if (GetClientTeam(attacker) == GetClientTeam(victim))
    {
        return false;
    }

    int primary = GetPlayerWeaponSlot(attacker, 0);
    return primary > MaxClients && primary == weapon;
}

void RegisterJuggleDirectHit(int attacker, int victim)
{
    if (!IsVictimAirshotEligible(victim))
    {
        ResetJuggleState(victim);
        return;
    }

    int attackerUserId = GetClientUserId(attacker);
    float now = GetGameTime();
    bool completedJuggle = g_iPendingJuggleAttackerUserId[victim] == attackerUserId
        && g_fPendingJuggleDirectHitTime[victim] > 0.0
        && now - g_fPendingJuggleDirectHitTime[victim] <= WT_GetJuggleWindow();

    if (completedJuggle)
    {
        ResetJuggleState(victim);
        ApplyBonusPoints(attacker, 2, true, true, WT_BONUS_CHANCE_ALWAYS, "Juggle", 0, WT_GetBonusDefaultDelay(), 3);
        return;
    }

    g_iPendingJuggleAttackerUserId[victim] = attackerUserId;
    g_fPendingJuggleDirectHitTime[victim] = now;
}

void ResetJuggleState(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    g_iPendingJuggleAttackerUserId[client] = 0;
    g_fPendingJuggleDirectHitTime[client] = 0.0;
}

void MarkDemoSyncStickyDamage(int attacker, int victim)
{
    g_iPendingDemoSyncAttacker[victim] = attacker;
    g_fPendingDemoSyncStickyTime[victim] = GetGameTime();
}

void MarkDemoSyncKillCandidate(int attacker, int victim)
{
    if (g_iPendingDemoSyncAttacker[victim] != attacker)
    {
        return;
    }

    if (GetGameTime() - g_fPendingDemoSyncStickyTime[victim] > WT_GetDemoSyncWindow())
    {
        ResetDemoSyncState(victim);
        return;
    }

    g_iPendingDemoSyncKillAttacker[victim] = attacker;
    g_fPendingDemoSyncKillTime[victim] = GetGameTime();
}

bool ConsumeDemoSyncKill(int attacker, int victim)
{
    if (!IsValidClient(attacker) || !IsValidClient(victim))
    {
        return false;
    }

    if (g_iPendingDemoSyncKillAttacker[victim] != attacker)
    {
        return false;
    }

    if (GetGameTime() - g_fPendingDemoSyncKillTime[victim] > WT_GetSyncKillConfirmWindow())
    {
        ResetDemoSyncState(victim);
        return false;
    }

    ResetDemoSyncState(victim);
    return true;
}

void ResetDemoSyncState(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    g_iPendingDemoSyncAttacker[client] = 0;
    g_fPendingDemoSyncStickyTime[client] = 0.0;
    g_iPendingDemoSyncKillAttacker[client] = 0;
    g_fPendingDemoSyncKillTime[client] = 0.0;
}

void MarkSoldierSyncRocketDamage(int attacker, int victim)
{
    g_iPendingSoldierSyncAttacker[victim] = attacker;
    g_fPendingSoldierSyncRocketTime[victim] = GetGameTime();
}

void MarkSoldierSyncKillCandidate(int attacker, int victim)
{
    if (g_iPendingSoldierSyncAttacker[victim] != attacker)
    {
        return;
    }

    if (GetGameTime() - g_fPendingSoldierSyncRocketTime[victim] > WT_GetSoldierSyncWindow())
    {
        ResetSoldierSyncState(victim);
        return;
    }

    g_iPendingSoldierSyncKillAttacker[victim] = attacker;
    g_fPendingSoldierSyncKillTime[victim] = GetGameTime();
}

bool ConsumeSoldierSyncKill(int attacker, int victim)
{
    if (!IsValidClient(attacker) || !IsValidClient(victim))
    {
        return false;
    }

    if (g_iPendingSoldierSyncKillAttacker[victim] != attacker)
    {
        return false;
    }

    if (GetGameTime() - g_fPendingSoldierSyncKillTime[victim] > WT_GetSyncKillConfirmWindow())
    {
        ResetSoldierSyncState(victim);
        return false;
    }

    ResetSoldierSyncState(victim);
    return true;
}

void ResetSoldierSyncState(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    g_iPendingSoldierSyncAttacker[client] = 0;
    g_fPendingSoldierSyncRocketTime[client] = 0.0;
    g_iPendingSoldierSyncKillAttacker[client] = 0;
    g_fPendingSoldierSyncKillTime[client] = 0.0;
}

float DistanceAboveGroundBox(int victim)
{
    float start[3];
    float end[3];
    float hullMins[3] = { -WT_TRACE_HULL_HALF_WIDTH, -WT_TRACE_HULL_HALF_WIDTH, 0.0 };
    float hullMaxs[3] = { WT_TRACE_HULL_HALF_WIDTH, WT_TRACE_HULL_HALF_WIDTH, 0.0 };
    float direction[3] = { 0.0, 0.0, WT_TRACE_DOWN_DISTANCE };

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

    int hours = seconds / WT_SECONDS_PER_HOUR;
    int minutes = (seconds % WT_SECONDS_PER_HOUR) / WT_SECONDS_PER_MINUTE;
    int secs = seconds % WT_SECONDS_PER_MINUTE;

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
    float minutes = (matchStats.playtime > 0) ? float(matchStats.playtime) / float(WT_SECONDS_PER_MINUTE) : 0.0;
    if (minutes > WT_GetMinMatchRateMinutes())
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
