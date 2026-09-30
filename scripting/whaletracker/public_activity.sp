// Preserve actor identity for announcements that would otherwise use sender 0.
void WhaleTracker_PublicMessage(int actor, int other, bool center, const char[] format, any ...)
{
    if (PublicActivity_IsPairExcluded(actor, other)) return;
    char message[512];
    VFormat(message, sizeof(message), format, 5);
    for (int viewer = 1; viewer <= MaxClients; viewer++)
    {
        if (!IsClientInGame(viewer) || Oblivion_ShouldHide(viewer, actor)
            || Oblivion_ShouldHide(viewer, other)) continue;
        if (center) PrintCenterText(viewer, "%s", message);
        else CPrintToChatEx(viewer, actor, "%s", message);
    }
}
