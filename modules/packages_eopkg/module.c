#include "module.h"
const char* packages_eopkg_module_preset(char* result, size_t result_size) {
    DIR* dir = opendir("/var/lib/eopkg/package");
    struct dirent* e;
    int count = 0;
    if (!dir) { snprintf(result, result_size, "?"); return result; }
    while ((e = readdir(dir)) != NULL)
        if (e->d_name[0] != '.') count++;
    closedir(dir);
    snprintf(result, result_size, "%d (eopkg)", count);
    return result;
}
