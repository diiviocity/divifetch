char* battery_module_preset(char* result, size_t result_size) {
    DIR* dir = opendir("/sys/class/power_supply");
    if (!dir) { snprintf(result, result_size, "?"); return result; }
    struct dirent* e;
    while ((e = readdir(dir)) != NULL) {
        if (strncmp(e->d_name, "BAT", 3) != 0) continue;
        char path[128], buf[32];
        snprintf(path, sizeof(path), "/sys/class/power_supply/%s/capacity", e->d_name);
        FILE* f = fopen(path, "r");
        if (!f) continue;
        int ok = fgets(buf, sizeof(buf), f) != NULL;
        fclose(f);
        if (!ok) continue;
        size_t len = strlen(buf);
        while (len > 0 && (buf[len-1] == '\n' || buf[len-1] == '\r')) buf[--len] = '\0';
        char cap[16];
        snprintf(cap, sizeof(cap), "%s", buf);
        char status[32] = "Unknown";
        snprintf(path, sizeof(path), "/sys/class/power_supply/%s/status", e->d_name);
        f = fopen(path, "r");
        if (f) {
            if (fgets(status, sizeof(status), f)) {
                len = strlen(status);
                while (len > 0 && (status[len-1] == '\n' || status[len-1] == '\r')) status[--len] = '\0';
            }
            fclose(f);
        }
        snprintf(result, result_size, "%s%% (%s)", cap, status);
        closedir(dir);
        return result;
    }
    closedir(dir);
    snprintf(result, result_size, "?");
    return result;
}
