int g_SeenSearchGeneration[MAXPLAYERS + 1];

bool WhaleTracker_CanSeeIdentity(int viewer, const char[] steamId)
{
    return GetFeatureStatus(FeatureType_Native, "Oblivion_IsSteamHidden") != FeatureStatus_Available
        || !Oblivion_IsSteamHidden(viewer, steamId);
}

void RequestSeenHistoryMenu(int client, const char[] search)
{
    char term[128],escaped[256];CopyLowercase(search,term,sizeof(term));
    EscapeSqlString(term,escaped,sizeof(escaped));
    DataPack pack=new DataPack();pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(++g_SeenSearchGeneration[client]);pack.WriteString(search);
    char query[4096];
    FormatEx(query,sizeof(query),
        "SELECT w.steamid, COALESCE(NULLIF(pr.newname, ''), NULLIF(fs.last_name, ''), NULLIF(w.cached_personaname, ''), w.steamid), "
        ... "COALESCE((SELECT nh.name FROM filters_steam_name_history nh WHERE nh.steamid64 = BINARY w.steamid AND INSTR(nh.name_lower, q.term) > 0 ORDER BY nh.last_seen DESC LIMIT 1), '') "
        ... "FROM whaletracker w LEFT JOIN filters_steam_names fs ON fs.steamid64 = w.steamid "
        ... "LEFT JOIN prename_rules pr ON pr.pattern COLLATE utf8mb4_uca1400_ai_ci = w.steamid "
        ... "CROSS JOIN (SELECT '%s' AS term) q "
        ... "WHERE INSTR(w.steamid,q.term)>0 OR INSTR(COALESCE(w.cached_personaname_lower,''),q.term)>0 "
        ... "OR INSTR(LOWER(COALESCE(pr.newname,'')),q.term)>0 OR INSTR(COALESCE(fs.last_name_lower,''),q.term)>0 "
        ... "OR EXISTS (SELECT 1 FROM filters_steam_name_history nh WHERE nh.steamid64 = BINARY w.steamid AND INSTR(nh.name_lower,q.term)>0) "
        ... "ORDER BY (w.steamid=q.term) DESC, (COALESCE(fs.last_name_lower,'')=q.term) DESC, COALESCE(w.last_seen,0) DESC, w.steamid ASC LIMIT 50",
        escaped);
    g_hDatabase.Query(WhaleTracker_SeenHistoryMenuReady,query,pack);
}

public void WhaleTracker_SeenHistoryMenuReady(Database db, DBResultSet rows, const char[] error, any data)
{
    DataPack pack=view_as<DataPack>(data);pack.Reset();
    int client=GetClientOfUserId(pack.ReadCell()),generation=pack.ReadCell();
    char search[128];pack.ReadString(search,sizeof(search));delete pack;
    if(client<=0 || !IsClientInGame(client) || generation!=g_SeenSearchGeneration[client])return;
    if(error[0])
    {
        LogError("[WhaleTracker] Seen name-history search failed: %s",error);
        CPrintToChat(client,"{gold}[WhaleTracker]{default} Name search is temporarily unavailable.");return;
    }
    Menu menu=new Menu(WhaleTracker_SeenHistorySelection);menu.SetTitle("Last seen: %s",search);
    StringMap added=new StringMap();char steamId[STEAMID64_LEN],name[128],alias[128],display[256];
    int count;
    while(rows!=null && rows.FetchRow())
    {
        rows.FetchString(0,steamId,sizeof(steamId));
        if(!WhaleTracker_CanSeeIdentity(client,steamId))continue;
        rows.FetchString(1,name,sizeof(name));rows.FetchString(2,alias,sizeof(alias));
        int online=WhaleTracker_FindClientBySteamId64(steamId);
        if(online>0)GetClientName(online,name,sizeof(name));
        if(alias[0] && !StrEqual(alias,name,false))FormatEx(display,sizeof(display),"%s (was %s)%s",name,alias,online>0?" [online]":"");
        else FormatEx(display,sizeof(display),"%s%s",name,online>0?" [online]":"");
        menu.AddItem(steamId,display);added.SetValue(steamId,1);count++;
    }
    // Brand-new clients may not have a lifetime row yet; retain online lookup.
    char onlineName[256];int online=FindOnlineSeenMatch(search,steamId,sizeof(steamId),onlineName,sizeof(onlineName));
    if(online>0 && !added.ContainsKey(steamId) && WhaleTracker_CanSeeIdentity(client,steamId))
    {
        GetClientName(online,name,sizeof(name));FormatEx(display,sizeof(display),"%s [online]",name);
        menu.AddItem(steamId,display);count++;
    }
    delete added;
    if(!count){delete menu;CPrintToChat(client,"{gold}[WhaleTracker]{default} No recorded name matched '%s'.",search);return;}
    menu.ExitButton=true;menu.Display(client,MENU_TIME_FOREVER);
}

public int WhaleTracker_SeenHistorySelection(Menu menu, MenuAction action, int client, int item)
{
    if(action==MenuAction_End){delete menu;return 0;}
    if(action!=MenuAction_Select || !IsClientInGame(client))return 0;
    char steamId[STEAMID64_LEN],name[256];menu.GetItem(item,steamId,sizeof(steamId),_,name,sizeof(name));
    if(!WhaleTracker_CanSeeIdentity(client,steamId))return 0;
    int online=WhaleTracker_FindClientBySteamId64(steamId);
    if(online>0)GetClientChatDisplayName(online,name,sizeof(name));
    RequestSeenTimesBySteamId(client,steamId,name,online>0?online:client);
    return 0;
}
