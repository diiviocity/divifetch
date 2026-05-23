static const char* wm_module_known_wms[] = { "sway", "hyprland", "wayfire", "river", "dwm", "i3", "bspwm", "herbstluftwm", "awesome", "xmonad", "openbox", "fluxbox", "icewm", "jwm", "mutter", "kwin_wayland",  "kwin_x11", "kwin", "muffin", "marco", "metacity", "xfwm4", "compiz",  "enlightenment", "lxqt-session", "plasmashell", NULL };
static int wm_module_try_proc(char* out, size_t out_size) {
    DIR* dir = opendir("/proc");
    if (!dir) return 0;
    struct dirent* entry;
    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_name[0] < '1' || entry->d_name[0] > '9') continue;
        char comm_path[320];
        snprintf(comm_path, sizeof(comm_path), "/proc/%s/comm", entry->d_name);
        FILE* f = fopen(comm_path, "r");
        if (!f) continue;
        char comm[64] = {0};
        fgets(comm, sizeof(comm), f);
        fclose(f);
        size_t len = strlen(comm);
        while (len > 0 && (comm[len-1] == '\n' || comm[len-1] == '\r')) comm[--len] = '\0';
        for (int i = 0; wm_module_known_wms[i]; i++) {
            if (strcasecmp(comm, wm_module_known_wms[i]) == 0) {
                if (strcasecmp(comm, "kwin_wayland") == 0 ||
                    strcasecmp(comm, "kwin_x11")     == 0 ||
                    strcasecmp(comm, "kwin")          == 0)      { snprintf(out, out_size, "KWin"); }
                else if (strcasecmp(comm, "mutter")   == 0)      { snprintf(out, out_size, "Mutter"); }
                else if (strcasecmp(comm, "muffin")   == 0)      { snprintf(out, out_size, "Muffin"); }
                else if (strcasecmp(comm, "xfwm4")    == 0)      { snprintf(out, out_size, "Xfwm4"); }
                else if (strcasecmp(comm, "plasmashell") == 0)   { snprintf(out, out_size, "KDE Plasma"); }
                else                                             { snprintf(out, out_size, "%s", comm); }
                closedir(dir);
                return 1;
            }
        }
    }
    closedir(dir);
    return 0;
}
char* wm_module_preset(char* result, size_t result_size) {
    const char* env_vars[] = {"XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP", "CURRENT_DESKTOP", "SESSION_DESKTOP", "DESKTOP_SESSION", NULL};
    for (int i = 0; env_vars[i]; i++) {
        const char* val = getenv(env_vars[i]);
        if (val && val[0] != '\0') {
            snprintf(result, result_size, "%s", val);
            return result;
        }
    }
    if (getenv("KDE_FULL_SESSION") || getenv("KDE_SESSION_UID") || getenv("KDE_SESSION_VERSION")) { snprintf(result, result_size, "KDE"); return result; }
    if (getenv("GNOME_DESKTOP_SESSION_ID"))                                                       { snprintf(result, result_size, "GNOME"); return result; }
    if (getenv("MATE_DESKTOP_SESSION_ID"))                                                        { snprintf(result, result_size, "MATE"); return result; }
    if (getenv("TDE_FULL_SESSION"))                                                               { snprintf(result, result_size, "Trinity"); return result; }
    if (getenv("HYPRLAND_CMD"))                                                                   { snprintf(result, result_size, "Hyprland"); return result; }
    if (getenv("SWAYSOCK"))                                                                       { snprintf(result, result_size, "Sway"); return result; }
    if (wm_module_try_proc(result, result_size)) return result;
    snprintf(result, result_size, "?");
    return result;
}
