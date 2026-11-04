// uptime module: total uptime from /proc/uptime, formatted d/h/m
// (the BSDs from kern.boottime with clock_gettime(2)).
const std = @import("std");
const util = @import("../util.zig");

var value_buf: [32]u8 = undefined;
var line_buf: [64]u8 = undefined;

pub fn preset() []const u8 {
    if (@import("builtin").os.tag == .openbsd) {
        const obs = @import("../openbsd.zig");
        var s: u64 = obs.uptimeSeconds() orelse return "?";
        const d = s / 86400;
        s %= 86400;
        const h = s / 3600;
        s %= 3600;
        const m = s / 60;
        s %= 60;

        if (d != 0)
            return std.mem.print(&value_buf, "{d}d {d}h {d}m", .{ d, h, m }) catch "?";
        if (h != 0)
            return std.mem.print(&value_buf, "{d}h {d}m", .{ h, m }) catch "?";
        return std.mem.print(&value_buf, "{d}m {d}s", .{ m, s }) catch "?";
    }
    if (@import("builtin").os.tag == .freebsd) {
        const f = @import("../freebsd.zig");
        var s: u64 = f.uptimeSeconds() orelse return "?";
        const d = s / 86400;
        s %= 86400;
        const h = s / 3600;
        s %= 3600;
        const m = s / 60;
        s %= 60;

        if (d != 0)
            return std.mem.print(&value_buf, "{d}d {d}h {d}m", .{ d, h, m }) catch "?";
        if (h != 0)
            return std.mem.print(&value_buf, "{d}h {d}m", .{ h, m }) catch "?";
        return std.mem.print(&value_buf, "{d}m {d}s", .{ m, s }) catch "?";
    }
    const line = util.readFirstLine("/proc/uptime", &line_buf) orelse return "?";
    // /proc/uptime is "<seconds> <idle_seconds>"
    const token = line[0 .. std.mem.findScalar(u8, line, ' ') orelse line.len];
    const seconds = std.fmt.parseFloat(f64, token) catch return "?";
    if (seconds < 0) return "?";

    var s: u64 = @intFromFloat(seconds);
    const d = s / 86400;
    s %= 86400;
    const h = s / 3600;
    s %= 3600;
    const m = s / 60;
    s %= 60;

    if (d != 0)
        return std.mem.print(&value_buf, "{d}d {d}h {d}m", .{ d, h, m }) catch "?";
    if (h != 0)
        return std.mem.print(&value_buf, "{d}h {d}m", .{ h, m }) catch "?";
    return std.mem.print(&value_buf, "{d}m {d}s", .{ m, s }) catch "?";
}
