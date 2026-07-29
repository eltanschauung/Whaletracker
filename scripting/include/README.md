# SourceMod API Includes

Only plugin-facing natives and forwards are listed here; third-party includes are not part of this API list.

## dgm_api.inc
- `DGM_GetGameMode` - Writes the current display gamemode into a buffer.
- `DGM_RealPlayerCount` - Counts real human players on the server.
- `DGM_RealTeamPlayerCount` - Counts real human players on a team.
- `DGM_GetGameModeKey` - Writes the current stable gamemode key into a buffer.
- `DGM_GetGameModeKeyForMap` - Resolves a map name to its stable gamemode key.
- `DGM_IsSmallFormatGamemode` - Returns whether the current gamemode is small-format.
- `DGM_NormalizeMapName` - Writes a normalized map name for config lookups.
- `DGM_CurrentNormalizedMap` - Writes the normalized current map name into a buffer.
- `DGM_GetServerCapacity` - Returns the configured server capacity.
- `DGM_GetPopulationRatio` - Returns real players divided by server capacity.
- `DGM_ServerCapacitycheck` - Returns whether population meets a capacity ratio.
- `DGM_IsRoundRunning` - Returns whether a round is active.
- `DGM_GetLastRoundDurationSeconds` - Returns the previous round length in seconds.
- `DGM_GetRoundDurationSeconds` - Returns the seconds between two round timestamps.

## points_store_api.inc
- `PointsStore_AreBonusPointsLoaded` - Returns whether a client's currency cache is ready.
- `PointsStore_GetBonusPoints` - Returns a client's current currency balance.
- `PointsStore_ApplyBonusPoints` - Applies a currency delta to a connected client.
- `PointsStore_ApplyBonusPointsSteamId` - Applies a currency delta to a SteamID64, including offline players.
- `PointsStore_SpendBonusPoints` - Spends a connected client's currency without chat or sound output.
- `PointsStore_HasPurchase` - Returns whether a client owns a shop item.
- `PointsStore_GetPurchasePrice` - Returns the price paid for a shop item.

## server_mail.inc
- `ServerMail_Send` - Sends ordinary mail between connected clients.
- `ServerMail_SendCustom` - Sends custom-titled mail between connected clients.
- `ServerMail_SendCurrency` - Sends currency mail between connected clients.
- `ServerMail_SendSteamId` - Sends ordinary mail to an offline-capable SteamID64.
- `ServerMail_SendCustomSteamId` - Sends custom-titled mail to an offline-capable SteamID64.
- `ServerMail_SendCurrencySteamId` - Sends idempotent currency mail to an offline-capable SteamID64.
- `ServerMail_OnMailSendResult` - Reports the confirmed result of an API mail insert.

## whaletracker_api.inc
- `WhaleTracker_GetCumulativeKills` - Returns a client's cumulative tracked kills.
- `WhaleTracker_AreStatsLoaded` - Returns whether a client's WhaleTracker stats are loaded.
- `WhaleTracker_HasPlaytimeHours` - Returns whether a client's loaded playtime meets an hour threshold.
- `WhaleTracker_GetRankedPlaytimeHours` - Returns whole playtime hours for a ranked client or Steam identity.
- `WhaleTracker_GetWhalePoints` - Returns a client's current Whale Points total.
- `WhaleTracker_ComputeWhalePoints` - Computes Whale Points from raw cumulative totals.
- `WhaleTracker_GetLastRecordedName` - Writes the best recorded name for a SteamID64 into a buffer.
- `WhaleTracker_GetLastSeen` - Returns the best known last_seen timestamp for a SteamID64.
- `WhaleTracker_OnAirshot` - Fires when WhaleTracker records an airshot.
- `WhaleTracker_OnProjectileDirectHit` - Fires when WhaleTracker records a confirmed projectile direct hit.
- `WhaleTracker_OnMedicDrop` - Fires when WhaleTracker records a medic dropping full uber.
- `WhaleTracker_OnKillstreak` - Fires when WhaleTracker records a killstreak milestone.
- `WhaleTracker_OnKillstreakEnd` - Fires when WhaleTracker records the end of a killstreak.
- `WhaleTracker_OnMultikill` - Fires when WhaleTracker records a multikill milestone.
