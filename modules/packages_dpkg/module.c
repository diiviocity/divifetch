#include "module.h"
const char* packages_dpkg_module_preset(char* result, size_t result_size) {
    static const char needle[] = "\nStatus: install ok installed";
    const size_t nlen = sizeof(needle) - 1;
    int count = 0;
    int match = 0;
    char c;
    FILE* f = fopen("/var/lib/dpkg/status", "rb");
    if (!f) { snprintf(result, result_size, "?"); return result; }
    while (fread(&c, 1, 1, f) == 1) {
        if (c == needle[match]) {
            if (++match == (int)nlen) { count++; match = 0; }
        } else {
            match = (c == needle[0]) ? 1 : 0;
        }
    }
    fclose(f);
    snprintf(result, result_size, "%d (dpkg)", count);
    return result;
}
