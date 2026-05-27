#include "module.h"
const char* memory_module_preset(char* result, size_t result_size) {
    FILE* f = fopen("/proc/meminfo", "r");
    if (!f) { snprintf(result, result_size, "?"); return result; } 
    unsigned long long mem_total = 0, mem_available = 0, mem_free = 0, buffers = 0, cached = 0, shmem = 0, s_reclaimable = 0;
    int found = 0; 
    char line[128];
    while (fgets(line, sizeof(line), f)) {
        unsigned long long val;
        if      (sscanf(line, "MemTotal: %llu", &val) == 1)     { mem_total     = val; found++; }
        else if (sscanf(line, "MemAvailable: %llu", &val) == 1) { mem_available = val; }
        else if (sscanf(line, "MemFree: %llu", &val) == 1)      { mem_free      = val; }
        else if (sscanf(line, "Buffers: %llu", &val) == 1)      { buffers       = val; }
        else if (sscanf(line, "Cached: %llu", &val) == 1)       { cached        = val; }
        else if (sscanf(line, "Shmem: %llu", &val) == 1)        { shmem        = val; }
        else if (sscanf(line, "SReclaimable: %llu", &val) == 1) { s_reclaimable = val; }
    }
    fclose(f); 
    if (!found) {
        snprintf(result, result_size, "?");
        return result;
    } 
    if (mem_available == 0 || mem_available >= mem_total)
        mem_available = mem_free + buffers + cached + s_reclaimable - shmem; 
    unsigned long long used_kb  = mem_total - mem_available;
    unsigned long long total_kb = mem_total;
    double used_mib  = (double)used_kb  / 1024.0;
    double total_mib = (double)total_kb / 1024.0; 
    if (total_mib >= 1024.0) snprintf(result, result_size, "%.1f GiB / %.1f GiB", used_mib / 1024.0, total_mib / 1024.0);
    else snprintf(result, result_size, "%.0f MiB / %.0f MiB", used_mib, total_mib); 
    return result;
}

