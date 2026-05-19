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

#define STEAMID64_LEN 32
#define MENU_TITLE "Whale Tracker Stats"
#define DB_CONFIG_DEFAULT "default"
#define SAVE_QUERY_MAXLEN 4096
#define MAX_CONCURRENT_SAVE_QUERIES 4
#define WHALE_POINTS_SQL_EXPR "ROUND(1000.0 * SQRT(((CASE WHEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) > 0 THEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) ELSE 1 END)) / (((CASE WHEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) > 0 THEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) ELSE 1 END)) + 400.0)) * (((CASE WHEN playtime > 0 THEN playtime ELSE 0 END) / 3600.0) / (((CASE WHEN playtime > 0 THEN playtime ELSE 0 END) / 3600.0) + 20.0)) * ((5.0 * (((CASE WHEN kills > 0 THEN kills ELSE 0 END) + ((CASE WHEN assists > 0 THEN assists ELSE 0 END) * 0.35)) / ((CASE WHEN deaths > 0 THEN deaths ELSE 0 END) + 20.0))) + LN(1.0 + ((CASE WHEN damage_dealt > 0 THEN damage_dealt ELSE 0 END) / (150.0 * ((CASE WHEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) > 0 THEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) ELSE 1 END))))) + (0.60 * LN(1.0 + ((CASE WHEN healing > 0 THEN healing ELSE 0 END) / (100.0 * ((CASE WHEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) > 0 THEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) ELSE 1 END)))))) + (0.90 * LN(1.0 + ((60.0 * (CASE WHEN total_ubers > 0 THEN total_ubers ELSE 0 END)) / ((CASE WHEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) > 0 THEN ((CASE WHEN kills > 0 THEN kills ELSE 0 END) + (CASE WHEN deaths > 0 THEN deaths ELSE 0 END)) ELSE 1 END)))))))"
#define WHALE_RANK_MIN_KD_SUM 200
#define WHALE_RANK_MIN_PLAYTIME_SECONDS 10800
#define WHALE_KILLSTREAK_BONUS_INTERVAL 5
#define WHALE_MULTIKILL_MAX_LEVEL 5
#define WT_BONUS_POINTS_SOUND "xp_gain"
#define WHALE_LEADERBOARD_PAGE_SIZE 10
#define WT_MARKET_GARDENER_DEF_INDEX 416
#define WT_HANDSHAKE_DEF_INDEX 609
#define WT_AIRSHOT_MIN_HEIGHT 90.0
#define WHALETRACKER_SCHEMA_VERSION 2
#define TF_CLASS_HEAVY          6
#define TF_CLASS_MEDIC          5

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
    MarkNativeAsOptional("PointsStore_GetBonusPoints");
    MarkNativeAsOptional("PointsStore_ApplyBonusPoints");
    MarkNativeAsOptional("PointsStore_SpendBonusPoints");
    RegPluginLibrary("whaletracker");
    CreateNative("WhaleTracker_GetCumulativeKills", Native_WhaleTracker_GetCumulativeKills);
    CreateNative("WhaleTracker_AreStatsLoaded", Native_WhaleTracker_AreStatsLoaded);
    CreateNative("WhaleTracker_HasPlaytimeHours", Native_WhaleTracker_HasPlaytimeHours);
    CreateNative("WhaleTracker_GetWhalePoints", Native_WhaleTracker_GetWhalePoints);
    CreateNative("WhaleTracker_ComputeWhalePoints", Native_WhaleTracker_ComputeWhalePoints);
    CreateNative("WhaleTracker_IsCurrentRoundMvp", Native_WhaleTracker_IsCurrentRoundMvp);
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
    int totalMedicKills;
    int totalHeavyKills;
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

    float connectTime;


}

WhaleStats g_Stats[MAXPLAYERS + 1];
WhaleStats g_MapStats[MAXPLAYERS + 1];
int g_KillSaveCounter[MAXPLAYERS + 1];
bool g_bStatsDirty[MAXPLAYERS + 1];
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

char g_sDatabaseConfig[64];
ArrayList g_SaveQueue = null;
int g_PendingSaveQueries = 0;
bool g_bShuttingDown = false;
Handle g_hOnlineTimer = null;
Handle g_hReconnectTimer = null;
Handle g_hSchemaRetryTimer = null;
Handle g_hSavePumpTimer = null;
Handle g_hAirshotForward = null;
Handle g_hMedicDropForward = null;
Handle g_hKillstreakForward = null;
Handle g_hKillstreakEndForward = null;
Handle g_hMultikillForward = null;

char g_sRoundMvpSteamId[4][STEAMID64_LEN];
char g_sLastRoundMvpSteamId[4][STEAMID64_LEN];
StringMap g_MapMvpHistory = null;

bool g_bFavoriteClassLoaded[MAXPLAYERS + 1];
bool g_bFavoriteClassPending[MAXPLAYERS + 1];
int g_iFavoriteClassCache[MAXPLAYERS + 1];
float g_fMultikillTimes[MAXPLAYERS + 1][WHALE_MULTIKILL_MAX_LEVEL];
int g_iLastMultikillAnnounced[MAXPLAYERS + 1];

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
