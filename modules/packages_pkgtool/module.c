#include "module.h"
const char* packages_pkgtool_module_preset(char* result, size_t result_size) {
    DIR* dir = opendir("/var/log/packages");
    struct dirent* e;
    int count = 0;
    if (!dir) { snprintf(result, result_size, "?"); return result; }
    while ((e = readdir(dir)) != NULL)
        if (e->d_name[0] != '.') count++;
    closedir(dir);
    snprintf(result, result_size, "%d (pkgtool)", count);
    return result;
}
