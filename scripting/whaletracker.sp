#pragma semicolon 1

#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <morecolors>
#undef REQUIRE_EXTENSIONS
#include <SteamWorks>
#define REQUIRE_EXTENSIONS
#include <geoip>
#include <adt_array>
#include <datapack>
#include <adt_trie>
#pragma newdecls required

// Sorted by reference count
#define STEAMID64_LEN 32
#define SAVE_QUERY_MAXLEN 4096
#define WT_BONUS_CHANCE_ALWAYS 1.0
#define MAX_CONCURRENT_SAVE_QUERIES 4
#define WT_SECONDS_PER_HOUR 3600
#define WT_TRACE_HULL_HALF_WIDTH 24.0
#define WT_TEAM_RED 2
#define WT_SECONDS_PER_MINUTE 60
#define WT_MATCH_LOG_MAX_DAMAGE_PER_MINUTE 3000.0
#define WT_WHALE_POINTS_LOG_BASE_E 2.718281828
#define WHALE_POINTS_SQL_EXPR "ROUND(1000.0 * SQRT(((CASE WHEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) > 0 THEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) ELSE 1 END)) / (((CASE WHEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) > 0 THEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) ELSE 1 END)) + 400.0)) * (((CASE WHEN playtime > 0 THEN playtime ELSE 0 END) / 3600.0) / (((CASE WHEN playtime > 0 THEN playtime ELSE 0 END) / 3600.0) + 20.0)) * ((5.0 * (((CASE WHEN kills > 0 THEN kills ELSE 0 END) + ((CASE WHEN assists > 0 THEN assists ELSE 0 END) * 0.35)) / ((CASE WHEN deaths > 0 THEN deaths ELSE 0 END) + 20.0))) + LN(1.0 + ((CASE WHEN damage_dealt > 0 THEN damage_dealt ELSE 0 END) / (150.0 * ((CASE WHEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) > 0 THEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) ELSE 1 END))))) + (0.60 * LN(1.0 + ((CASE WHEN healing > 0 THEN healing ELSE 0 END) / (100.0 * ((CASE WHEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) > 0 THEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) ELSE 1 END)))))) + (0.90 * LN(1.0 + ((60.0 * (CASE WHEN total_ubers > 0 THEN total_ubers ELSE 0 END)) / ((CASE WHEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) > 0 THEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) ELSE 1 END)))))))"
#define WT_TEAM_BLUE 3
#define WT_TEAM_FIRST_PLAYING WT_TEAM_RED
#define WHALE_LEADERBOARD_PAGE_SIZE 10
#define WT_SCORE_PROP_AVAILABLE 1
#define WT_SCORE_PROP_MISSING 2
#define WT_WHALE_POINTS_MAX_FLOAT 2147483000.0
#define WHALETRACKER_SCHEMA_VERSION 2
#define DB_CONFIG_DEFAULT "default"
#define WT_TRACE_DOWN_DISTANCE -16384.0
#define WT_MARKET_GARDENER_DEF_INDEX 416
#define WT_HANDSHAKE_DEF_INDEX 609
#define WT_SOLDIER_SYNC_EXCLUDED_DEF_INDEX 730
#define WT_SCORE_PROP_UNKNOWN 0
#define WT_WHALE_POINTS_SCALE 1000.0
#define WT_WHALE_POINTS_COMBAT_WEIGHT 5.0
#define WT_WHALE_POINTS_ASSIST_WEIGHT 0.35
#define WT_WHALE_POINTS_DEATH_OFFSET 20.0
#define WT_WHALE_POINTS_DAMAGE_SCALE 150.0
#define WT_WHALE_POINTS_HEALING_WEIGHT 0.60
#define WT_WHALE_POINTS_HEALING_SCALE 100.0
#define WT_WHALE_POINTS_UBER_WEIGHT 0.90
#define WT_WHALE_POINTS_UBER_SCALE 60.0
#define WT_WHALE_POINTS_CONFIDENCE_ENGAGEMENT_OFFSET 400.0
#define WT_WHALE_POINTS_CONFIDENCE_HOURS_OFFSET 20.0
#define WT_NATIVE_MAX_PLAYTIME_HOURS 596523
#define TF_CLASS_MEDIC          5
#define WT_MEDIC_ASSISTS_LIFE_BONUS_INTERVAL 4
#define MENU_TITLE "Whale Tracker Stats"
#define WT_TEAM_SPECTATOR 1
#define WT_BONUS_POINTS_SOUND "xp_gain"
#define TF_CLASS_HEAVY          6

native int Filters_GetChatName(int client, char[] buffer, int maxlen);
native int Filters_GetSteamIdColorTag(const char[] steamId, char[] buffer, int maxlen);
native bool SaySounds_PlayCommand(int client, const char[] commandName, bool ignoreOptIn = false);
forward bool WhaleTracker_RustQueueSqlWrite(const char[] query, int userId, bool forceSync);
forward void WhaleTracker_RustInit();
forward void WhaleTracker_RustFlushSqlBatch();
forward void WhaleTracker_RustShutdown();

public APLRes AskPluginLoad2(Handle self, bool late, char[] error, int err_max)
{
    MarkNativeAsOptional("SDKHook");
    MarkNativeAsOptional("SDKUnhook");
    MarkNativeAsOptional("SteamWorks_GetPublicIP");
    MarkNativeAsOptional("Filters_GetChatName");
    MarkNativeAsOptional("Filters_GetSteamIdColorTag");
    MarkNativeAsOptional("SaySounds_PlayCommand");
    MarkNativeAsOptional("DGM_GetGameMode");
    MarkNativeAsOptional("DGM_RealPlayerCount");
    MarkNativeAsOptional("DGM_GetGameModeKeyForMap");
    MarkNativeAsOptional("DGM_IsSmallFormatGamemode");
    MarkNativeAsOptional("DGM_NormalizeMapName");
    MarkNativeAsOptional("DGM_CurrentNormalizedMap");
    MarkNativeAsOptional("DGM_GetServerCapacity");
    MarkNativeAsOptional("DGM_ServerCapacitycheck");
    MarkNativeAsOptional("DGM_IsRoundRunning");
    MarkNativeAsOptional("PointsStore_GetBonusPoints");
    MarkNativeAsOptional("PointsStore_ApplyBonusPoints");
    MarkNativeAsOptional("PointsStore_ApplyBonusPointsSteamId");
    MarkNativeAsOptional("PointsStore_SpendBonusPoints");
    RegPluginLibrary("whaletracker");
    CreateNative("WhaleTracker_GetCumulativeKills", Native_WhaleTracker_GetCumulativeKills);
    CreateNative("WhaleTracker_AreStatsLoaded", Native_WhaleTracker_AreStatsLoaded);
    CreateNative("WhaleTracker_HasPlaytimeHours", Native_WhaleTracker_HasPlaytimeHours);
    CreateNative("WhaleTracker_GetWhalePoints", Native_WhaleTracker_GetWhalePoints);
    CreateNative("WhaleTracker_ComputeWhalePoints", Native_WhaleTracker_ComputeWhalePoints);
    CreateNative("WhaleTracker_GetLastRecordedName", Native_WhaleTracker_GetLastRecordedName);
    CreateNative("WhaleTracker_GetLastSeen", Native_WhaleTracker_GetLastSeen);
    return APLRes_Success;
}

enum
{
    CLASS_UNKNOWN = TFClass_Unknown,
    CLASS_SCOUT = TFClass_Scout,
    CLASS_SNIPER = TFClass_Sniper,
    CLASS_SOLDIER = TFClass_Soldier,
    CLASS_DEMOMAN = TFClass_DemoMan,
    CLASS_MEDIC = TFClass_Medic,
    CLASS_HEAVY = TFClass_Heavy,
    CLASS_PYRO = TFClass_Pyro,
    CLASS_SPY = TFClass_Spy,
    CLASS_ENGINEER = TFClass_Engineer,
    CLASS_MIN = CLASS_SCOUT,
    CLASS_MAX = CLASS_ENGINEER,
    CLASS_COUNT = CLASS_MAX + 1
}

enum WeaponCategory
{
    WeaponCategory_None = 0,
    WeaponCategory_Shotguns = 1,
    WeaponCategory_Scatterguns,
    WeaponCategory_Pistols,
    WeaponCategory_RocketLaunchers,
    WeaponCategory_GrenadeLaunchers,
    WeaponCategory_StickyLaunchers,
    WeaponCategory_Snipers,
    WeaponCategory_Revolvers,
    WeaponCategory_Count = WeaponCategory_Revolvers
}
#define WEAPON_CATEGORY_COUNT 8

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom);
void RequestClientStateLoads(int client);
int GetWhalePointsForClient(int client);
Database GetSyncDatabaseHandle();
DBResultSet SQLQuerySync(const char[] query);
bool SQLFastQuerySync(const char[] query);
void GetSyncDatabaseError(char[] error, int maxlen);

enum struct WhaleStats
{
    bool loaded;
    char steamId[STEAMID64_LEN];
    char firstSeen[32];
    int firstSeenTimestamp;

    int kills;
    int deaths;
    int totalHealing;
    int totalUbers;
    int totalMedicDrops;
    int totalAirshots;
    int totalCrossbowHits;
    int totalMarketGardenHits;
    int totalHeadshots;
    int totalBackstabs;
    int totalAssists;
    int totalDamage;
    int totalDamageTaken;
    int totalUberDrops;
    int weaponShots[WEAPON_CATEGORY_COUNT + 1];
    int weaponHits[WEAPON_CATEGORY_COUNT + 1];
    int lastSeen;

    int bestKillstreak;
    int bestUbersLife;

    int playtime; // seconds

    // runtime counters (not persisted directly)
    int currentKillstreak;
    int currentUbersLife;
    int currentAssistsLife;

    float connectTime;

    bool isAdmin;

}

WhaleStats g_Stats[MAXPLAYERS + 1];
WhaleStats g_MapStats[MAXPLAYERS + 1];
int g_KillSaveCounter[MAXPLAYERS + 1];
bool g_bStatsDirty[MAXPLAYERS + 1];
float g_fLastHitscanAccuracyHit[MAXPLAYERS + 1][WEAPON_CATEGORY_COUNT + 1];
Handle g_hPeriodicSaveTimer = null;
bool g_bStatsLoadPending[MAXPLAYERS + 1];
bool g_bOnlineStateLoadPending[MAXPLAYERS + 1];
bool g_bTrackEligible[MAXPLAYERS + 1];
int g_iDamageGate[MAXPLAYERS + 1];

Database g_hDatabase = null;
Database g_hSyncDatabase = null;
ConVar g_CvarDatabase = null;
ConVar g_hVisibleMaxPlayers = null;
ConVar g_hGameName = null;
ConVar g_hGameUrl = null;
ConVar g_hEnableMatchLogs = null;
ConVar g_hOnlineUpdateInterval = null;
ConVar g_hDeferredSavePump = null;
bool g_bDatabaseReady = false;
bool g_bAsyncDatabaseConnected = false;
bool g_bSyncDatabaseConnected = false;
bool g_bDatabaseConnectInFlight = false;
bool g_bSchemaReady = false;
bool g_bSchemaCheckInFlight = false;

enum MatchStatField
{
    MatchStat_Kills = 0,
    MatchStat_Deaths,
    MatchStat_Assists,
    MatchStat_Damage,
    MatchStat_DamageTaken,
    MatchStat_Healing,
    MatchStat_Headshots,
    MatchStat_Backstabs,
    MatchStat_Ubers,
    MatchStat_Playtime,
    MatchStat_MedicDrops,
    MatchStat_UberDrops,
    MatchStat_Airshots,
    MatchStat_MarketGardenHits,
    MatchStat_ShotsShotguns,
    MatchStat_HitsShotguns,
    MatchStat_ShotsScatterguns,
    MatchStat_HitsScatterguns,
    MatchStat_ShotsPistols,
    MatchStat_HitsPistols,
    MatchStat_ShotsRocketLaunchers,
    MatchStat_HitsRocketLaunchers,
    MatchStat_ShotsGrenadeLaunchers,
    MatchStat_HitsGrenadeLaunchers,
    MatchStat_ShotsStickyLaunchers,
    MatchStat_HitsStickyLaunchers,
    MatchStat_ShotsSnipers,
    MatchStat_HitsSnipers,
    MatchStat_ShotsRevolvers,
    MatchStat_HitsRevolvers,

    MatchStat_BestStreak,
    MatchStat_BestUbersLife,
    MatchStat_IsAdmin,
    MatchStat_Count
};

enum
{
    MATCH_STAT_COUNT = MatchStat_Count
};

StringMap g_DisconnectedStats = null;
StringMap g_MatchNames = null;

char g_sCurrentMap[64];
char g_sCurrentLogId[64];
char g_sLastFinalizedLogId[64];
char g_sOnlineMapName[128];
char g_sHostIp[64];
char g_sPublicHostIp[64];
char g_sHostCity[64];
char g_sHostCountry[3];
char g_sHostCountryLower[3];
char g_sServerFlags[256];
int g_iHostPort = 0;
int g_iMatchStartTime = 0;
bool g_bMatchFinalized = false;

ConVar g_hHostIpCvar = null;
ConVar g_hHostPortCvar = null;
ConVar g_hServerFlags = null;
ConVar g_hMultikillWindow = null;
ConVar g_hBonusDefaultDelay = null;
ConVar g_hRankMinKdSum = null;
ConVar g_hRankMinPlaytimeSeconds = null;
ConVar g_hKillstreakBonusInterval = null;
ConVar g_hSyncKillConfirmWindow = null;
ConVar g_hTopScoreMinPlayers = null;
ConVar g_hTopScorePerMapLimit = null;
ConVar g_hDamageTrackingGate = null;
ConVar g_hDamageSanityMax = null;
ConVar g_hMinMatchRateMinutes = null;
ConVar g_hAirshotMinHeight = null;
ConVar g_hDemoSyncWindow = null;
ConVar g_hSoldierSyncWindow = null;
ConVar g_hDemoSyncPerMap = null;
ConVar g_hSoldierSyncPerMap = null;
ConVar g_hHitscanAccuracyHitDebounce = null;
ConVar g_hMarketGardenKillWindow = null;
ConVar g_hPeriodicSaveInterval = null;

char g_sDatabaseConfig[64];
ArrayList g_SaveQueue = null;
int g_PendingSaveQueries = 0;
bool g_bShuttingDown = false;
Handle g_hOnlineTimer = null;
Handle g_hReconnectTimer = null;
Handle g_hSchemaRetryTimer = null;
Handle g_hSavePumpTimer = null;
Handle g_hAirshotForward = null;
Handle g_hProjectileDirectHitForward = null;
Handle g_hMedicDropForward = null;
Handle g_hKillstreakForward = null;
Handle g_hKillstreakEndForward = null;
Handle g_hMultikillForward = null;

bool g_bFavoriteClassLoaded[MAXPLAYERS + 1];
bool g_bFavoriteClassPending[MAXPLAYERS + 1];
int g_iFavoriteClassCache[MAXPLAYERS + 1];
bool g_bShowCountryLoaded[MAXPLAYERS + 1];
bool g_bShowCountryPending[MAXPLAYERS + 1];
bool g_bShowCountryCache[MAXPLAYERS + 1];
bool g_bShowCountryToggleAfterLoad[MAXPLAYERS + 1];
float g_fMultikillChainExpiresAt[MAXPLAYERS + 1];
int g_iMultikillChainKills[MAXPLAYERS + 1];

float WT_GetConVarFloat(ConVar convar, float fallback)
{
    return convar != null ? convar.FloatValue : fallback;
}

int WT_GetConVarInt(ConVar convar, int fallback)
{
    return convar != null ? convar.IntValue : fallback;
}

float WT_GetBonusDefaultDelay()
{
    return WT_GetConVarFloat(g_hBonusDefaultDelay, 3.0);
}

int WT_GetRankMinKdSum()
{
    return WT_GetConVarInt(g_hRankMinKdSum, 200);
}

int WT_GetRankMinPlaytimeSeconds()
{
    return WT_GetConVarInt(g_hRankMinPlaytimeSeconds, 10800);
}

int WT_GetKillstreakBonusInterval()
{
    int interval = WT_GetConVarInt(g_hKillstreakBonusInterval, 5);
    return interval < 1 ? 1 : interval;
}

float WT_GetSyncKillConfirmWindow()
{
    return WT_GetConVarFloat(g_hSyncKillConfirmWindow, 0.25);
}

int WT_GetTopScoreMinPlayers()
{
    return WT_GetConVarInt(g_hTopScoreMinPlayers, 10);
}

int WT_GetTopScorePerMapLimit()
{
    return WT_GetConVarInt(g_hTopScorePerMapLimit, 15);
}

int WT_GetDamageTrackingGate()
{
    return WT_GetConVarInt(g_hDamageTrackingGate, 200);
}

int WT_GetDamageSanityMax()
{
    return WT_GetConVarInt(g_hDamageSanityMax, 500);
}

float WT_GetMultikillWindow()
{
    return WT_GetConVarFloat(g_hMultikillWindow, 3.0);
}

float WT_GetMinMatchRateMinutes()
{
    return WT_GetConVarFloat(g_hMinMatchRateMinutes, 1.0);
}

float WT_GetAirshotMinHeight()
{
    return WT_GetConVarFloat(g_hAirshotMinHeight, 100.0);
}

float WT_GetDemoSyncWindow()
{
    return WT_GetConVarFloat(g_hDemoSyncWindow, 0.5);
}

float WT_GetSoldierSyncWindow()
{
    return WT_GetConVarFloat(g_hSoldierSyncWindow, 1.0);
}

int WT_GetDemoSyncPerMap()
{
    return WT_GetConVarInt(g_hDemoSyncPerMap, 0);
}

int WT_GetSoldierSyncPerMap()
{
    return WT_GetConVarInt(g_hSoldierSyncPerMap, 0);
}

float WT_GetHitscanAccuracyHitDebounce()
{
    return WT_GetConVarFloat(g_hHitscanAccuracyHitDebounce, 0.05);
}

float WT_GetMarketGardenKillWindow()
{
    return WT_GetConVarFloat(g_hMarketGardenKillWindow, 0.25);
}

float WT_GetPeriodicSaveInterval()
{
    float interval = WT_GetConVarFloat(g_hPeriodicSaveInterval, 30.0);
    return interval < 1.0 ? 1.0 : interval;
}

char g_SaveQueryBuffers[MAX_CONCURRENT_SAVE_QUERIES][SAVE_QUERY_MAXLEN];
int g_SaveQueryUserIds[MAX_CONCURRENT_SAVE_QUERIES];
bool g_SaveQuerySlotUsed[MAX_CONCURRENT_SAVE_QUERIES];

#include "include/dgm_api.inc"
#undef REQUIRE_PLUGIN
#include "include/points_store_api.inc"
#define REQUIRE_PLUGIN
#include "include/whaletracker.inc"
#include "whaletracker/motd_whaletracker.sp"
#undef REQUIRE_EXTENSIONS
#include "whaletracker/rust_sql_outlet_whaletracker.sp"
#define REQUIRE_EXTENSIONS
#include "whaletracker/runtime_whaletracker.sp"
#include "whaletracker/database_whaletracker.sp"
#include "whaletracker/gameplay_whaletracker.sp"
#include "whaletracker/commands_whaletracker.sp"
