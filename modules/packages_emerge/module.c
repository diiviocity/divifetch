#include "module.h"
const char* packages_emerge_module_preset(char* result, size_t result_size) {
    DIR* cat_dir = opendir("/var/db/pkg");
    if (!cat_dir) { snprintf(result, result_size, "?"); return result; }
    int count = 0;
    struct dirent* cat;
    while ((cat = readdir(cat_dir)) != NULL) {
        if (cat->d_name[0] == '.') continue;
        char path[512];
        snprintf(path, sizeof(path), "/var/db/pkg/%s", cat->d_name);
        DIR* pkg_dir = opendir(path);
        if (!pkg_dir) continue;
        struct dirent* pkg;
        while ((pkg = readdir(pkg_dir)) != NULL) if (pkg->d_name[0] != '.') count++;
        closedir(pkg_dir);
    }
    closedir(cat_dir);
    if (!count) { snprintf(result, result_size, "?"); return result; }
    snprintf(result, result_size, "%d (emerge)", count);
    return result;
}
