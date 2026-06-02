#include "module.h"
const char* packages_pacman_module_preset(char* result, size_t result_size) {
    DIR* dir = opendir("/var/lib/pacman/local");
    if (!dir) { snprintf(result, result_size, "?"); return result; }
    int count = -1;
    struct dirent* e;
    while ((e = readdir(dir)) != NULL)
        if (e->d_name[0] != '.') count++;
    closedir(dir);
    snprintf(result, result_size, "%d (pacman)", count);
    return result;
}
