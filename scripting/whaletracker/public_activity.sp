// Preserve actor identity for announcements that would otherwise use sender 0.
void WhaleTracker_BroadcastMessage(int actor, bool center, const char[] format, any ...)
{
    char message[512];
    VFormat(message, sizeof(message), format, 4);
    for (int viewer = 1; viewer <= MaxClients; viewer++)
    {
        if (!IsClientInGame(viewer)) continue;
        if (center) PrintCenterText(viewer, "%s", message);
        else CPrintToChatEx(viewer, actor, "%s", message);
    }
}
