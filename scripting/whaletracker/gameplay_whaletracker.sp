bool g_bPlayerTakenDirectHit[MAXPLAYERS + 1];
bool g_bInExplosiveJump[MAXPLAYERS + 1];

void ClearRoundMvpIdentity()
{
    g_sRoundMvpSteamId[2][0] = '\0';
    g_sRoundMvpSteamId[3][0] = '\0';
}

void ClearLastRoundMvpIdentity()
{
    g_sLastRoundMvpSteamId[2][0] = '\0';
    g_sLastRoundMvpSteamId[3][0] = '\0';
}

void ClearCurrentRoundMvpState()
{
    ClearRoundMvpIdentity();
}

void ClearLastRoundMvpState()
{
    ClearLastRoundMvpIdentity();
}

void SnapshotCurrentRoundMvpStateToLastRound()
{
    strcopy(g_sLastRoundMvpSteamId[2], sizeof(g_sLastRoundMvpSteamId[]), g_sRoundMvpSteamId[2]);
    strcopy(g_sLastRoundMvpSteamId[3], sizeof(g_sLastRoundMvpSteamId[]), g_sRoundMvpSteamId[3]);
}

void ClearRoundMvpForTeam(int team)
{
    if (team != 2 && team != 3)
    {
        return;
    }

    g_sRoundMvpSteamId[team][0] = '\0';

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientConnected(i) || IsFakeClient(i))
        {
            continue;
        }

    }
}

bool InvalidateClientRoundMvp(int client, int team = 0)
{
    if (client <= 0 || client > MaxClients || IsFakeClient(client))
    {
        return false;
    }

    EnsureClientSteamId(client);
    if (g_Stats[client].steamId[0] == '\0')
    {
        return false;
    }

    bool cleared = false;
    if (team == 2 || team == 3)
    {
        if (StrEqual(g_sRoundMvpSteamId[team], g_Stats[client].steamId, false))
        {
            ClearRoundMvpForTeam(team);
            cleared = true;
        }

        return cleared;
    }

    if (StrEqual(g_sRoundMvpSteamId[2], g_Stats[client].steamId, false))
    {
        ClearRoundMvpForTeam(2);
        cleared = true;
    }

    if (StrEqual(g_sRoundMvpSteamId[3], g_Stats[client].steamId, false))
    {
        ClearRoundMvpForTeam(3);
        cleared = true;
    }

    return cleared;
}

bool IsClientCurrentRoundMvp(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client))
    {
        return false;
    }

    int team = GetClientTeam(client);
    if (team != 2 && team != 3)
    {
        return false;
    }

    EnsureClientSteamId(client);
    if (g_Stats[client].steamId[0] == '\0' || g_sRoundMvpSteamId[team][0] == '\0')
    {
        return false;
    }

    return StrEqual(g_Stats[client].steamId, g_sRoundMvpSteamId[team], false);
}

void AssignRoundMvp(int client, int team)
{
    if (team != 2 && team != 3)
    {
        return;
    }

    EnsureClientSteamId(client);
    if (g_Stats[client].steamId[0] == '\0')
    {
        return;
    }

    ClearRoundMvpForTeam(team);
    strcopy(g_sRoundMvpSteamId[team], sizeof(g_sRoundMvpSteamId[]), g_Stats[client].steamId);
    MarkSteamIdAsMapMvp(g_Stats[client].steamId);
}

bool HasSteamIdBeenMapMvp(const char[] steamId)
{
    if (steamId[0] == '\0' || g_MapMvpHistory == null)
    {
        return false;
    }

    int seen = 0;
    return g_MapMvpHistory.GetValue(steamId, seen);
}

void MarkSteamIdAsMapMvp(const char[] steamId)
{
    if (steamId[0] == '\0' || g_MapMvpHistory == null)
    {
        return;
    }

    g_MapMvpHistory.SetValue(steamId, 1, true);
}

public void QueueRoundMvpSelection()
{
    if (g_hRoundMvpTimer != null)
    {
        return;
    }

    if (g_sRoundMvpSteamId[2][0] != '\0' && g_sRoundMvpSteamId[3][0] != '\0')
    {
        return;
    }

    g_hRoundMvpTimer = CreateTimer(0.25, Timer_SetRoundMvps, _, TIMER_FLAG_NO_MAPCHANGE);
}

void LoadRoundMvpCachedPoints(StringMap cachedPoints)
{
    if (cachedPoints == null || !g_bDatabaseReady || GetSyncDatabaseHandle() == null)
    {
        return;
    }

    char inClause[4096];
    int candidateCount = 0;
    inClause[0] = '\0';

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
        {
            continue;
        }

        int team = GetClientTeam(i);
        if (team != 2 && team != 3)
        {
            continue;
        }

        EnsureClientSteamId(i);
        if (g_Stats[i].steamId[0] == '\0' || HasSteamIdBeenMapMvp(g_Stats[i].steamId))
        {
            continue;
        }

        char escapedSteamId[STEAMID64_LEN * 2];
        EscapeSqlString(g_Stats[i].steamId, escapedSteamId, sizeof(escapedSteamId));

        if (candidateCount > 0)
        {
            StrCat(inClause, sizeof(inClause), ",");
        }

        StrCat(inClause, sizeof(inClause), "'");
        StrCat(inClause, sizeof(inClause), escapedSteamId);
        StrCat(inClause, sizeof(inClause), "'");
        candidateCount++;
    }

    if (candidateCount <= 0)
    {
        return;
    }

    char query[6144];
    Format(query, sizeof(query),
        "SELECT steamid, points "
        ... "FROM whaletracker_points_cache "
        ... "WHERE steamid IN (%s)",
        inClause);

    DBResultSet results = SQLQuerySync(query);
    if (results == null)
    {
        char error[256];
        GetSyncDatabaseError(error, sizeof(error));
        LogError("[WhaleTracker] Failed to load round MVP cache points: %s", error);
        if (WhaleTracker_IsConnectionLostError(error))
        {
            WhaleTracker_ScheduleReconnect(2.0);
        }
        return;
    }

    while (SQL_HasResultSet(results) && results.FetchRow())
    {
        char steamId[STEAMID64_LEN];
        results.FetchString(0, steamId, sizeof(steamId));
        TrimString(steamId);
        if (steamId[0] == '\0')
        {
            continue;
        }

        cachedPoints.SetValue(steamId, results.FetchInt(1), true);
    }

    delete results;
}

bool GetRoundMvpCandidatePoints(int client, StringMap cachedPoints, int &points, bool &waitingForStats)
{
    points = 0;
    waitingForStats = false;

    if (!IsClientInGame(client) || IsFakeClient(client))
    {
        return false;
    }

    EnsureClientSteamId(client);
    if (g_Stats[client].steamId[0] == '\0')
    {
        return false;
    }

    if (HasSteamIdBeenMapMvp(g_Stats[client].steamId))
    {
        return false;
    }

    if (cachedPoints != null && cachedPoints.GetValue(g_Stats[client].steamId, points))
    {
        return (points > 0);
    }

    if (!g_Stats[client].loaded)
    {
        if (!g_bStatsLoadPending[client])
        {
            RequestClientStateLoads(client);
        }

        waitingForStats = true;
        return false;
    }

    points = GetWhalePointsForStats(g_Stats[client]);
    return (points > 0);
}

bool CanSelectRoundMvpByKills(int client)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
    {
        return false;
    }

    EnsureClientSteamId(client);
    if (g_Stats[client].steamId[0] == '\0')
    {
        return false;
    }

    return !HasSteamIdBeenMapMvp(g_Stats[client].steamId);
}

bool IsBetterRoundMvpCandidate(int candidate, int candidatePoints, int currentBest, int currentBestPoints)
{
    if (candidate <= 0)
    {
        return false;
    }

    if (currentBest <= 0)
    {
        return true;
    }

    if (candidatePoints > currentBestPoints)
    {
        return true;
    }

    if (candidatePoints < currentBestPoints)
    {
        return false;
    }

    EnsureClientSteamId(candidate);
    EnsureClientSteamId(currentBest);

    if (g_Stats[candidate].steamId[0] != '\0' && g_Stats[currentBest].steamId[0] != '\0')
    {
        int compare = strcmp(g_Stats[candidate].steamId, g_Stats[currentBest].steamId, false);
        if (compare != 0)
        {
            return compare < 0;
        }
    }

    return candidate < currentBest;
}

bool SelectRoundMvpsNow()
{
    bool needRed = (g_sRoundMvpSteamId[2][0] == '\0');
    bool needBlue = (g_sRoundMvpSteamId[3][0] == '\0');
    int redMvp = 0;
    int blueMvp = 0;
    int bestRedKills = 0;
    int bestBlueKills = 0;
    int bestRedPoints = 0;
    int bestBluePoints = 0;
    bool redTeamHasKills = false;
    bool blueTeamHasKills = false;
    bool waitingForStats = false;

    if (!needRed && !needBlue)
    {
        return false;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
        {
            continue;
        }

        int team = GetClientTeam(i);
        if (team != 2 && team != 3)
        {
            continue;
        }

        int kills = g_MapStats[i].kills;
        if (kills > 0)
        {
            if (team == 2)
            {
                redTeamHasKills = true;
            }
            else
            {
                blueTeamHasKills = true;
            }
        }

        if (kills <= 0 || !CanSelectRoundMvpByKills(i))
        {
            continue;
        }

        if (needRed && team == 2 && IsBetterRoundMvpCandidate(i, kills, redMvp, bestRedKills))
        {
            redMvp = i;
            bestRedKills = kills;
            continue;
        }

        if (needBlue && team == 3 && IsBetterRoundMvpCandidate(i, kills, blueMvp, bestBlueKills))
        {
            blueMvp = i;
            bestBlueKills = kills;
        }
    }

    bool fallbackRedToPoints = (needRed && redMvp <= 0 && !redTeamHasKills);
    bool fallbackBlueToPoints = (needBlue && blueMvp <= 0 && !blueTeamHasKills);

    if (fallbackRedToPoints || fallbackBlueToPoints)
    {
        StringMap cachedPoints = new StringMap();
        LoadRoundMvpCachedPoints(cachedPoints);

        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientInGame(i) || IsFakeClient(i))
            {
                continue;
            }

            int team = GetClientTeam(i);
            if ((team == 2 && !fallbackRedToPoints) || (team == 3 && !fallbackBlueToPoints))
            {
                continue;
            }

            if (team != 2 && team != 3)
            {
                continue;
            }

            int points = 0;
            bool clientWaitingForStats = false;
            if (!GetRoundMvpCandidatePoints(i, cachedPoints, points, clientWaitingForStats))
            {
                waitingForStats |= clientWaitingForStats;
                continue;
            }

            if (team == 2 && IsBetterRoundMvpCandidate(i, points, redMvp, bestRedPoints))
            {
                redMvp = i;
                bestRedPoints = points;
                continue;
            }

            if (team == 3 && IsBetterRoundMvpCandidate(i, points, blueMvp, bestBluePoints))
            {
                blueMvp = i;
                bestBluePoints = points;
            }
        }

        delete cachedPoints;
    }

    if (needRed && redMvp > 0)
    {
        AssignRoundMvp(redMvp, 2);
    }

    if (needBlue && blueMvp > 0)
    {
        AssignRoundMvp(blueMvp, 3);
    }

    if (redMvp > 0 && blueMvp > 0)
    {
        CPrintToChatAll("{magenta}MVPs{default} this round: {red}%N{default}, {blue}%N", redMvp, blueMvp);
    }

    if (((needRed && redMvp <= 0) || (needBlue && blueMvp <= 0)) && waitingForStats)
    {
        QueueRoundMvpSelection();
    }

    return (redMvp > 0 || blueMvp > 0);
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    SnapshotCurrentRoundMvpStateToLastRound();
    ClearCurrentRoundMvpState();
    g_hRoundMvpTimer = null;

    QueueRoundMvpSelection();
}

public Action Timer_SetRoundMvps(Handle timer, any data)
{
    if (timer != INVALID_HANDLE && timer != g_hRoundMvpTimer)
    {
        return Plugin_Stop;
    }

    g_hRoundMvpTimer = null;
    SelectRoundMvpsNow();
    return Plugin_Stop;
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client) || IsFakeClient(client))
    {
        return;
    }

    int oldTeam = event.GetInt("oldteam");
    int newTeam = event.GetInt("team");
    bool cleared = InvalidateClientRoundMvp(client, oldTeam);
    if (cleared || oldTeam != newTeam)
    {
        QueueRoundMvpSelection();
    }
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client))
        return;

    g_bPlayerTakenDirectHit[client] = false;
    g_bInExplosiveJump[client] = false;
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
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int assister = GetClientOfUserId(event.GetInt("assister"));
    int deathFlags = event.GetInt("death_flags");
    int victimClass = view_as<int>(TF2_GetPlayerClass(victim));
    bool attackerScoredMedicDrop = false;
    bool victimMedicDrop = false;

    if (!(deathFlags & TF_DEATHFLAG_DEADRINGER))
    {
        victimMedicDrop = IsMedicDrop(victim);

        if (IsValidClient(attacker) && attacker != victim && WhaleTracker_IsTrackingEnabled(attacker))
        {
            int custom = event.GetInt("customkill");
            bool backstab = (custom == TF_CUSTOM_BACKSTAB);
            bool medicDrop = victimMedicDrop;

            ApplyKillStats(g_Stats[attacker], backstab, medicDrop);
            ApplyKillStats(g_MapStats[attacker], backstab, medicDrop);
            int killstreak = g_Stats[attacker].currentKillstreak;
            if (killstreak > 0 && killstreak % WHALE_KILLSTREAK_BONUS_INTERVAL == 0)
            {
                ApplyBonusPoints(attacker, 1, true, true, 1.0, "killstreak", killstreak, 3.0);
                char attackerName[MAX_NAME_LENGTH];
                GetClientName(attacker, attackerName, sizeof(attackerName));
                AnnounceKillstreakMilestone(attackerName, killstreak);
            }
            if (IsClientCurrentRoundMvp(victim))
            {
                ApplyBonusPoints(attacker, 1, true, true, 1.0, "mvp_kill", victim);
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
                ApplyBonusPoints(attacker, 1, true, true, 1.0, "player_dom", victim);
            }
            if (deathFlags & TF_DEATHFLAG_KILLERREVENGE)
            {
                ApplyBonusPoints(attacker, 1, true, true, 1.0, "player_revenge", victim);
            }
            attackerScoredMedicDrop = medicDrop;
            MarkClientDirty(attacker);
        }

        if (IsValidClient(assister) && assister != victim && WhaleTracker_IsTrackingEnabled(assister))
        {
            ApplyAssistStats(g_Stats[assister]);
            ApplyAssistStats(g_MapStats[assister]);
            if (deathFlags & TF_DEATHFLAG_ASSISTERDOMINATION)
            {
                ApplyBonusPoints(assister, 1, true, true, 1.0, "player_dom", victim);
            }
            if (deathFlags & TF_DEATHFLAG_ASSISTERREVENGE)
            {
                ApplyBonusPoints(assister, 1, true, true, 1.0, "player_revenge", victim);
            }
            MarkClientDirty(assister);
        }

        if (IsValidClient(victim) && WhaleTracker_IsTrackingEnabled(victim))
        {
            if (attackerScoredMedicDrop)
            {
                g_Stats[victim].totalUberDrops++;
                g_MapStats[victim].totalUberDrops++;
            }
            ApplyCumulativeDeathStats(g_Stats[victim]);
            ApplyDeathStats(g_MapStats[victim]);
            MarkClientDirty(victim);
        }

        if (victimMedicDrop)
        {
            AnnounceMedicDrop(victim);
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

    if (IsValidClient(attacker) && !IsFakeClient(attacker) && WhaleTracker_IsTrackingEnabled(attacker))
    {
        if (IsSupstatsAirshot(attacker, victim, weapon, wasDirectHit))
        {
            g_Stats[attacker].totalAirshots += 1;
            ApplyBonusPoints(attacker, 1, true, true, 1.0, "airshot");
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
            ApplyBonusPoints(attacker, 1, true, true, 1.0, "market_garden");
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

void AnnounceMedicDrop(int medic)
{
    if (!IsValidClient(medic) || IsFakeClient(medic))
        return;

    char colorTag[32];
    GetClientFiltersNameColorTag(medic, colorTag, sizeof(colorTag));
    TrimString(colorTag);

    if (colorTag[0] == '\0')
    {
        strcopy(colorTag, sizeof(colorTag), "teamcolor");
    }

    if (StrEqual(colorTag, "teamcolor", false) || StrEqual(colorTag, "{teamcolor}", false))
    {
        CPrintToChatAllEx(medic, "{teamcolor}%N{default} dropped!", medic);
        PlayMedicDropSound();
        return;
    }

    CPrintToChatAllEx(medic, "{%s}%N{default} dropped!", colorTag, medic);
    PlayMedicDropSound();
}

void PlayMedicDropSound()
{
    if (!LibraryExists("saysounds"))
        return;

    SaySounds_PlayCommand(0, "holyshit", false);
}

void AnnounceKillstreakMilestone(const char[] clientName, int killstreak, bool playSound = true)
{
    if (killstreak < WHALE_KILLSTREAK_BONUS_INTERVAL || killstreak % WHALE_KILLSTREAK_BONUS_INTERVAL != 0)
        return;

    char label[32];
    char commandName[32];

    if (killstreak >= 30)
    {
        strcopy(label, sizeof(label), "GODLIKE");
        strcopy(commandName, sizeof(commandName), "holyshit");
    }
    else if (killstreak >= 25)
    {
        strcopy(label, sizeof(label), "godlike");
        strcopy(commandName, sizeof(commandName), "godlike");
    }
    else if (killstreak >= 20)
    {
        strcopy(label, sizeof(label), "unstoppable");
        strcopy(commandName, sizeof(commandName), "unstoppable");
    }
    else if (killstreak >= 15)
    {
        strcopy(label, sizeof(label), "dominating");
        strcopy(commandName, sizeof(commandName), "dominating");
    }
    else if (killstreak >= 10)
    {
        strcopy(label, sizeof(label), "on a rampage");
        strcopy(commandName, sizeof(commandName), "rampage");
    }
    else
    {
        strcopy(label, sizeof(label), "on a killing spree");
        strcopy(commandName, sizeof(commandName), "killingspree");
    }

    if (playSound && LibraryExists("saysounds"))
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsValidClient(i) || IsFakeClient(i))
            {
                continue;
            }

            if (!SaySounds_PlayCommand(i, commandName, false))
            {
                continue;
            }

            PrintCenterText(i, "%s is %s! (%d)", clientName, label, killstreak);
        }
        return;
    }

    PrintCenterTextAll("%s is %s! (%d)", clientName, label, killstreak);
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
