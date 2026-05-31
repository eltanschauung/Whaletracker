#if defined _points_store_api_included
  #endinput
#endif
#define _points_store_api_included

#include <sourcemod>

native bool PointsStore_AreBonusPointsLoaded(int client);
native int PointsStore_GetBonusPoints(int client);
native bool PointsStore_ApplyBonusPoints(int client, int points, bool playSound = true, bool chatAlert = true, float randomChance = 1.0, const char[] type = "", int target = 0, float delay = 3.0, int perMap = 0);
native bool PointsStore_SpendBonusPoints(int client, int points);
native bool PointsStore_HasPurchase(int client, const char[] itemKey);
native int PointsStore_GetPurchasePrice(int client, const char[] itemKey);

public SharedPlugin __pl_points_store =
{
    name = "points_store",
    file = "points_store.smx",
    required = 0,
};

public void __pl_points_store_SetNTVOptional()
{
    MarkNativeAsOptional("PointsStore_AreBonusPointsLoaded");
    MarkNativeAsOptional("PointsStore_GetBonusPoints");
    MarkNativeAsOptional("PointsStore_ApplyBonusPoints");
    MarkNativeAsOptional("PointsStore_SpendBonusPoints");
    MarkNativeAsOptional("PointsStore_HasPurchase");
    MarkNativeAsOptional("PointsStore_GetPurchasePrice");
}
