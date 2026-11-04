// wm module: desktop environment variables first, then a scan of
// /proc/*/comm for a window manager process.
const std = @import("std");
const util = @import("../util.zig");

const env_vars = [_][]const u8{ "XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP", "CURRENT_DESKTOP", "SESSION_DESKTOP", "DESKTOP_SESSION" };

const known_wms = [_][]const u8{ "sway", "hyprland", "wayfire", "river", "dwm", "i3", "bspwm", "herbstluftwm", "awesome", "xmonad", "openbox", "fluxbox", "icewm", "jwm", "mutter", "kwin_wayland", "kwin_x11", "kwin", "muffin", "marco", "metacity", "xfwm4", "compiz", "enlightenment", "lxqt-session", "plasmashell" };

var value_buf: [64]u8 = undefined;
var path_buf: [32]u8 = undefined;
var comm_buf: [64]u8 = undefined;

fn wmName(comm: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(comm, "kwin_wayland") or
        std.ascii.eqlIgnoreCase(comm, "kwin_x11") or
        std.ascii.eqlIgnoreCase(comm, "kwin"))
        return "KWin";
    if (std.ascii.eqlIgnoreCase(comm, "mutter")) return "Mutter";
    if (std.ascii.eqlIgnoreCase(comm, "muffin")) return "Muffin";
    if (std.ascii.eqlIgnoreCase(comm, "xfwm4")) return "Xfwm4";
    if (std.ascii.eqlIgnoreCase(comm, "plasmashell")) return "KDE Plasma";
    return comm;
}

pub fn preset(io: std.Io, environ: *const std.process.Environ.Map) []const u8 {
    if (util.envAny(environ, &env_vars)) |value|
        return util.snapshot(&value_buf, value);

    // Presence-only env tests (the value does not matter).
    const special = [_]struct { env: []const u8, name: []const u8 }{
        .{ .env = "KDE_FULL_SESSION", .name = "KDE" },
        .{ .env = "KDE_SESSION_UID", .name = "KDE" },
        .{ .env = "KDE_SESSION_VERSION", .name = "KDE" },
        .{ .env = "GNOME_DESKTOP_SESSION_ID", .name = "GNOME" },
        .{ .env = "MATE_DESKTOP_SESSION_ID", .name = "MATE" },
        .{ .env = "TDE_FULL_SESSION", .name = "Trinity" },
        .{ .env = "HYPRLAND_CMD", .name = "Hyprland" },
        .{ .env = "SWAYSOCK", .name = "Sway" },
    };
    for (special) |s| {
        if (environ.get(s.env) != null) {
            return util.snapshot(&value_buf, s.name);
        }
    }

    // Last resort: look for a running window manager process.
    var proc_dir = std.Io.Dir.openDirAbsolute(io, "/proc", .{ .iterate = true }) catch return "?";
    defer proc_dir.close(io);

    var it = proc_dir.iterate();
    while (it.next(io) catch null) |entry| {
        // Only numeric (pid) entries.
        if (entry.name.len == 0 or entry.name[0] < '1' or entry.name[0] > '9') continue;

        const comm_path = std.mem.print(&path_buf, "/proc/{s}/comm", .{entry.name}) catch continue;
        var comm = util.readFirstLine(comm_path, &comm_buf) orelse continue;
        comm = util.trimTrailingNewlines(comm);

        if (comm.len != 0 and util.inListIgnoreCase(comm, &known_wms)) {
            return util.snapshot(&value_buf, wmName(comm));
        }
    }

    return "?";
}
