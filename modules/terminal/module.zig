// terminal module: env hints + PID leaking first, then a walk up the
// process tree skipping shells, falls back to $TERM/$TERM_PROGRAM,
// appends a version when found.
//
// detect() is exported: the font module reuses the same identity
// detection instead of duplicating it (fastfetch shares
// detection/terminalshell across terminal and terminalfont too).
const std = @import("std");
const util = @import("../util.zig");

const hints = [_]struct { env: []const u8, name: []const u8 }{
    .{ .env = "KITTY_PID", .name = "kitty" },
    .{ .env = "ALACRITTY_SOCKET", .name = "alacritty" },
    .{ .env = "WEZTERM_PANE", .name = "wezterm" },
    .{ .env = "GHOSTTY_RESOURCES_DIR", .name = "ghostty" },
    .{ .env = "FOOT_SERVER_SOCKET", .name = "foot" },
    .{ .env = "KONSOLE_VERSION", .name = "konsole" },
    .{ .env = "XTERM_VERSION", .name = "xterm" },
};

const skipped = [_][]const u8{ "sh", "ash", "bash", "zsh", "ksh", "mksh", "csh", "tcsh", "fish", "dash", "nu", "elvish", "pwsh", "sudo", "su", "login", "make", "sshd", "sshd-session", // build tooling: the bake-time walk must see THROUGH v's
    // subcommand processes to the terminal the build ran inside
    "v", "build",
    // the fetch's own binaries: running divifetch inside a chained
    // twin's shell walks past them to the terminal it lives in
    "divifetch", "divifetch-run",
    // tool hosts: opencode runs commands through its own worker chain
    // between the user's shell and the fetch; the climb passes it to
    // reach the terminal the human actually sits in
    "opencode", "generator" };

const pretty_map = [_]struct { proc: []const u8, name: []const u8 }{
    .{ .proc = "gnome-terminal", .name = "GNOME Terminal" },
    .{ .proc = "konsole", .name = "Konsole" },
    .{ .proc = "xfce4-terminal", .name = "Xfce Terminal" },
    .{ .proc = "alacritty", .name = "Alacritty" },
    .{ .proc = "kitty", .name = "kitty" },
    .{ .proc = "foot", .name = "foot" },
    .{ .proc = "wezterm-gui", .name = "WezTerm" },
    .{ .proc = "wezterm", .name = "WezTerm" },
    .{ .proc = "ghostty", .name = "Ghostty" },
    .{ .proc = "st", .name = "st" },
    .{ .proc = "urxvt", .name = "urxvt" },
    .{ .proc = "terminator", .name = "Terminator" },
    .{ .proc = "tilix", .name = "Tilix" },
    .{ .proc = "xterm", .name = "XTerm" },
    .{ .proc = "ratty", .name = "Ratty" },
};

/// What the identity pass found: `name` is the raw process name (comm),
/// `pid` the terminal's own pid when it could be pinned (0 otherwise).
pub const Info = struct {
    name: []const u8,
    pid: std.posix.pid_t,
};

var name_buf: [64]u8 = undefined;
var term_buf: [32]u8 = undefined;
var program_buf: [32]u8 = undefined;

fn fromTermProgram(environ: *const std.process.Environ.Map) ?[]const u8 {
    const raw = environ.get("TERM_PROGRAM") orelse return null;
    if (raw.len == 0) return null;
    const program = util.snapshot(&program_buf, raw);

    // TERM_PROGRAM values are display names ("WezTerm", "ghostty"); map
    // to the raw identities the font parsers key off. Case-insensitive
    // by hand — std.ascii has no indexIgnoreCase in 0.17.
    const mapped = [_]struct { needle: []const u8, name: []const u8 }{
        .{ .needle = "wezterm", .name = "wezterm" },
        .{ .needle = "ghostty", .name = "ghostty" },
        .{ .needle = "foot", .name = "foot" },
        .{ .needle = "kitty", .name = "kitty" },
        .{ .needle = "alacritty", .name = "alacritty" },
        .{ .needle = "konsole", .name = "konsole" },
    };
    for (mapped) |m| {
        var ti: usize = 0;
        while (ti + m.needle.len <= program.len) : (ti += 1) {
            var eq = true;
            for (m.needle, 0..) |nc, j| {
                if (std.ascii.toLower(program[ti + j]) != std.ascii.toLower(nc)) {
                    eq = false;
                    break;
                }
            }
            if (eq) return m.name;
        }
    }
    return null; // unknown provider: don't let it poison the walk
}

/// Detection shared by terminal, terminalfont (via font) — and anything
/// else that needs to know what terminal the shell lives in.
pub fn detect(io: std.Io, environ: *const std.process.Environ.Map) Info {
    _ = io; // identity is file/env-only; kept for signature stability

    // Explicit source-env inheritance: DIVIFETCH_TERMINAL_PID pins the
    // exact terminal (build wrappers / shells can set it so a bake sees
    // the caller's real terminal, even through tooling chains).
    if (environ.get("DIVIFETCH_TERMINAL_PID")) |pid_val| {
        if (std.fmt.parseInt(std.posix.pid_t, std.mem.trim(u8, pid_val, " \t"), 10)) |p| {
            if (p > 0) {
                if (util.procStat(p)) |stat| {
                    if (stat.comm.len != 0) {
                        return .{ .name = util.snapshot(&name_buf, stat.comm), .pid = p };
                    }
                }
            }
        } else |_| {}
    }

    var name: []const u8 = "";
    var pid: std.posix.pid_t = 0;

    for (hints) |hint| {
        if (environ.get(hint.env) == null) continue;

        // Fastfetch's PID shortcut: when the env value IS a pid, the
        // walker can be skipped entirely and identity read from that
        // pid's /proc/<pid>/stat comm (more truthful than the hint).
        var stayed_hint = false;
        if (std.fmt.parseInt(std.posix.pid_t, std.mem.trim(u8, environ.get(hint.env).?, " \t"), 10)) |p| {
            if (util.procStat(p)) |stat| {
                name = util.snapshot(&name_buf, stat.comm);
                pid = p;
            }
            stayed_hint = true;
        } else |_| {}
        if (!stayed_hint) name = hint.name;
        break;
    }

    if (name.len == 0) {
        if (fromTermProgram(environ)) |tp| name = tp;
    }

    if (name.len == 0) {
        var cur = std.os.linux.getppid();
        var depth: usize = 0;
        while (cur > 1 and depth < 32) : (depth += 1) {
            const stat = util.procStat(cur) orelse break;
            if (!util.inList(stat.comm, &skipped)) {
                name = util.snapshot(&name_buf, stat.comm);
                pid = cur;
                break;
            }
            cur = stat.ppid;
        }
    }

    if (name.len == 0) {
        // "$TERM = xterm-kitty" style last chance
        if (util.envAny(environ, &.{"TERM"})) |term| {
            const term_snap = util.snapshot(&term_buf, term);
            const known = [_][]const u8{ "kitty", "alacritty", "foot", "ghostty", "st", "xterm" };
            for (known) |k| {
                if (std.mem.find(u8, term_snap, k) != null) {
                    name = k;
                    break;
                }
            }
        }
    }

    return .{ .name = name, .pid = pid };
}

fn pretty(comm: []const u8) ?[]const u8 {
    for (pretty_map) |p| {
        if (std.mem.startsWith(u8, comm, p.proc)) return p.name;
    }
    return null;
}

var comm_buf: [64]u8 = undefined;
var value_buf: [256]u8 = undefined;
var out_buf: [512]u8 = undefined;

fn versionOf(io: std.Io, exe: []const u8, use_version_arg: bool) []const u8 {
    const flag: []const u8 = if (use_version_arg) "--version" else "-v";
    return util.extractVersion(util.firstLine(util.runCaptureArgv(io, &.{ exe, flag }, &out_buf)));
}

pub fn preset(io: std.Io, environ: *const std.process.Environ.Map) []const u8 {
    var name = detect(io, environ).name;
    if (name.len == 0) return "?";

    name = util.snapshot(&comm_buf, name);
    const exe = if (std.mem.startsWith(u8, name, "wezterm-gui")) "wezterm" else name;

    var ver = versionOf(io, exe, false);
    if (ver.len == 0) ver = versionOf(io, exe, true);
    const display = pretty(name) orelse name;

    if (ver.len != 0) return std.mem.print(&value_buf, "{s} {s}", .{ display, ver }) catch "?";
    return util.snapshot(&value_buf, display);
}
