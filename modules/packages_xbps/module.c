char* packages_xbps_module_preset(char* result, size_t result_size) {
    DIR* dir = opendir("/var/db/xbps");
    if (!dir) { snprintf(result, result_size, "?"); return result; }
    char path[256] = "";
    struct dirent* e;
    while ((e = readdir(dir)) != NULL) { if (strncmp(e->d_name, "pkgdb-", 6) == 0) { snprintf(path, sizeof(path), "/var/db/xbps/%s", e->d_name); break; } }
    closedir(dir);
    if (!path[0]) { snprintf(result, result_size, "?"); return result; }
    FILE* f = fopen(path, "r");
    if (!f) { snprintf(result, result_size, "?"); return result; }
    int count = 0;
    char line[256];
    while (fgets(line, sizeof(line), f)) if (strstr(line, "<string>installed</string>")) count++;
    fclose(f);
    snprintf(result, result_size, "%d (xbps)", count);
    return result;
}
