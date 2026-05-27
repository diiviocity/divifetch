#include "module.h"
static int shell_module_proc_stat(pid_t pid, char* comm, size_t comm_size, pid_t* ppid) {
    char path[64];
    snprintf(path, sizeof(path), "/proc/%d/stat", (int)pid);
    FILE* f = fopen(path, "r");
    if (!f) return -1;
    char raw[512];
    int ok = fgets(raw, sizeof(raw), f) != NULL;
    fclose(f);
    if (!ok) return -1;
    char* rp = strrchr(raw, ')');
    char* lp = strchr(raw, '(');
    if (!rp || !lp) return -1;
    *rp = '\0';
    snprintf(comm, comm_size, "%s", lp + 1);
    char state; int ip;
    if (sscanf(rp + 1, " %c %d", &state, &ip) < 2) return -1;
    *ppid = (pid_t)ip;
    return 0;
}
static int shell_module_is_shell(const char* name) {
    static const char* shells[] = {"sh", "ash", "bash", "zsh", "ksh", "mksh", "csh", "tcsh", "fish", "dash", "nu", "elvish", "pwsh", NULL};
    for (int i = 0; shells[i]; i++)
        if (strcmp(name, shells[i]) == 0) return 1;
    return 0;
}
static int shell_module_version(const char* cmd, char* out, size_t out_size) {
    char buf[512];
    snprintf(buf, sizeof(buf), "%s --version 2>&1", cmd);
    FILE* f = popen(buf, "r");
    if (!f) return -1;
    int ok = fgets(out, (int)out_size, f) != NULL;
    pclose(f);
    if (!ok) return -1;
    size_t len = strlen(out);
    while (len > 0 && (out[len-1] == '\n' || out[len-1] == '\r')) out[--len] = '\0';
    return len > 0 ? 0 : -1;
}
static void shell_module_extract_ver(char* s) {
    char* p = s;
    while (*p && !(*p >= '0' && *p <= '9')) p++;
    char* start = p;
    while (*p && ((*p >= '0' && *p <= '9') || *p == '.')) p++;
    *p = '\0';
    memmove(s, start, strlen(start) + 1);
}
const char* shell_module_preset(char* result, size_t result_size) {
    pid_t pid = getppid();
    char comm[64] = "";
    pid_t ppid;
    for (int depth = 0; pid > 1 && depth < 16; depth++) {
        if (shell_module_proc_stat(pid, comm, sizeof(comm), &ppid) != 0) break;
        if (shell_module_is_shell(comm)) break;
        comm[0] = '\0';
        pid = ppid;
    }
    if (!comm[0]) {
        const char* env = getenv("SHELL");
        if (!env || !env[0]) { snprintf(result, result_size, "?"); return result; }
        const char* base = strrchr(env, '/');
        snprintf(comm, sizeof(comm), "%s", base ? base + 1 : env);
    }
    char ver[128] = "";
    if (shell_module_version(comm, ver, sizeof(ver)) == 0)
        shell_module_extract_ver(ver);

    if (ver[0]) snprintf(result, result_size, "%s %s", comm, ver);
    else        snprintf(result, result_size, "%s", comm);
    return result;
}
