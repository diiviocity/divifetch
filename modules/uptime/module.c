#include "module.h"
const char *uptime_module_preset(char *result, size_t result_size) {
    FILE *f = fopen("/proc/uptime", "r");
    if (!f) { snprintf(result, result_size, "?"); return result; }
    double total_seconds;
    if (fscanf(f, "%lf", &total_seconds) != 1) {
        fclose(f);
        snprintf(result, result_size, "?");
        return result;
    }
    fclose(f);
    long s = (long)total_seconds;
    long d = s / 86400; s %= 86400;
    long h = s / 3600; s %= 3600;
    long m = s / 60; s %= 60;
    if (d) snprintf(result, result_size, "%ldd %ldh %ldm", d, h, m);
    else if (h) snprintf(result, result_size, "%ldh %ldm", h, m);
    else snprintf(result, result_size, "%ldm %lds", m, s);
    return result;
}
