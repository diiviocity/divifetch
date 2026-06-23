#define _POSIX_C_SOURCE 200809L
#include "module.h"
static int terminal_module_proc_stat(pid_t pid, char* comm, size_t comm_size, pid_t* ppid) {
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
static int terminal_module_is_skip(const char* name) {
    static const char* skip[] = {"sh", "ash", "bash", "zsh", "ksh", "mksh", "csh", "tcsh", "fish", "dash", "nu", "elvish", "pwsh", "sudo", "su", "login", "make", NULL};
    int i;
    for (i = 0; skip[i]; i++)
        if (strcmp(name, skip[i]) == 0) return 1;
    return 0;
}
static int terminal_module_version(const char* cmd, bool use_version, char* out, size_t out_size) {
    char buf[512];
    snprintf(buf, sizeof(buf), use_version ? "%s --version 2>&1" : "%s -v 2>&1", cmd);
    FILE* f = popen(buf, "r");
    if (!f) return -1;
    int ok = fgets(out, (int)out_size, f) != NULL;
    pclose(f);
    if (!ok) return -1;
    size_t len = strlen(out);
    while (len > 0 && (out[len-1] == '\n' || out[len-1] == '\r')) out[--len] = '\0';
    return len > 0 ? 0 : -1;
}
static void terminal_module_extract_ver(char* s) {
    char* p = s;
    while (*p && !(*p >= '0' && *p <= '9')) p++;
    char* start = p;
    while (*p && ((*p >= '0' && *p <= '9') || *p == '.')) p++;
    *p = '\0';
    memmove(s, start, strlen(start) + 1);
}
static const char* terminal_module_pretty(const char* comm) {
    static const struct { const char* proc; const char* name; } map[] = {
        { "gnome-terminal",  "GNOME Terminal" },
        { "konsole",         "Konsole"        },
        { "xfce4-terminal",  "Xfce Terminal"  },
        { "alacritty",       "Alacritty"      },
        { "kitty",           "kitty"          },
        { "foot",            "foot"           },
        { "wezterm-gui",     "WezTerm"        },
        { "wezterm",         "WezTerm"        },
        { "ghostty",         "Ghostty"        },
        { "st",              "st"             },
        { "urxvt",           "urxvt"          },
        { "terminator",      "Terminator"     },
        { "tilix",           "Tilix"          },
        { "xterm",           "XTerm"          },
        { "ratty",           "Ratty"          },
        { NULL, NULL }
    };
    int i;
    for (i = 0; map[i].proc; i++)
        if (strncmp(comm, map[i].proc, strlen(map[i].proc)) == 0)
            return map[i].name;
    return NULL;
}
const char* terminal_module_preset(char* result, size_t result_size) {
    static const struct { const char* env; const char* name; } hints[] = {
        { "KITTY_PID",             "kitty"         },
        { "ALACRITTY_SOCKET",      "alacritty"     },
        { "WEZTERM_PANE",          "wezterm"       },
        { "GHOSTTY_RESOURCES_DIR", "ghostty"       },
        { "FOOT_SERVER_SOCKET",    "foot"          },
        { "KONSOLE_VERSION",       "konsole"       },
        { "XTERM_VERSION",         "xterm"         },
        { NULL, NULL }
    };
    char comm[64] = "";
    int i;
    for (i = 0; hints[i].env; i++) {
        if (getenv(hints[i].env)) { snprintf(comm, sizeof(comm), "%s", hints[i].name); break; }
    }
    if (!comm[0]) {
        pid_t pid = getppid();
        pid_t ppid;
        int depth;
        for (depth = 0; pid > 1 && depth < 32; depth++) {
            if (terminal_module_proc_stat(pid, comm, sizeof(comm), &ppid) != 0) break;
            if (!terminal_module_is_skip(comm)) break;
            comm[0] = '\0';
            pid = ppid;
        }
    }
    if (!comm[0]) {
        const char* term = getenv("TERM");
        if (term && term[0]) snprintf(comm, sizeof(comm), "%s", term);
        else { snprintf(result, result_size, "?"); return result; }
    }
    const char* pretty = terminal_module_pretty(comm);
    const char* exe = (strncmp(comm, "wezterm-gui", 11) == 0) ? "wezterm" : comm;
    char ver[128] = "";
    if (terminal_module_version(exe, false, ver, sizeof(ver)) == 0) terminal_module_extract_ver(ver);
    if (!ver[0]) {  if (terminal_module_version(exe, true, ver, sizeof(ver)) == 0) terminal_module_extract_ver(ver); }
    const char* display = pretty ? pretty : comm;
    if (ver[0]) snprintf(result, result_size, "%s %s", display, ver);
    else        snprintf(result, result_size, "%s", display);
    return result;
}
