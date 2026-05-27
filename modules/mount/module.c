#include "module.h"
static void mount_module_format_size(unsigned long long bytes, char* out, size_t out_size) {
    const char* units[] = { " B", " KiB", " MiB", " GiB", " TiB" };
    int unit_index = 0;
    double size = (double)bytes;
    while (size >= 1024.0 && unit_index < 4) { size /= 1024.0; unit_index++; }
    snprintf(out, out_size, "%.1f%s", size, units[unit_index]);
}
const char* mount_module_preset(const char* path, char* result, size_t result_size) {
    struct statvfs stat;
    if (statvfs(path, &stat) != 0) { snprintf(result, result_size, "?"); return result; }
    unsigned long long total = (unsigned long long)stat.f_blocks * stat.f_frsize;
    unsigned long long free  = (unsigned long long)stat.f_bfree  * stat.f_frsize;
    unsigned long long used  = total - free;
    char used_str[32], total_str[32];
    mount_module_format_size(used,  used_str,  sizeof(used_str));
    mount_module_format_size(total, total_str, sizeof(total_str));
    snprintf(result, result_size, "%s / %s", used_str, total_str);
    return result;
}
