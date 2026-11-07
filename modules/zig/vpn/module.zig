// vpn module: tunnel interface presence under /sys/class/net (the
// BSDs walk libc's getifaddrs(3) chains). tun*/wg*/tap*/ppp* count as
// a VPN being up.
const std = @import("std");
const util = @import("../util.zig");

var value_buf: [48]u8 = undefined;
var iface_buf: [16]u8 = undefined;

pub fn preset(io: std.Io) []const u8 {
    if (@import("builtin").os.tag == .openbsd) {
        const obs = @import("../openbsd.zig");
        if (obs.tunnelIface(&iface_buf)) |iface|
            return std.mem.print(&value_buf, "up ({s})", .{iface}) catch "?";
        return "down";
    }
    if (@import("builtin").os.tag == .macos) {
        // utun* only counts with an IPv4 address on it: macOS keeps
        // several up at all times (see macos.zig tunnelIface).
        const m = @import("../macos.zig");
        if (m.tunnelIface(&iface_buf)) |iface|
            return std.mem.print(&value_buf, "up ({s})", .{iface}) catch "?";
        return "down";
    }
    if (@import("builtin").os.tag == .freebsd) {
        const f = @import("../freebsd.zig");
        if (f.tunnelIface(&iface_buf)) |iface|
            return std.mem.print(&value_buf, "up ({s})", .{iface}) catch "?";
        return "down";
    }
    var dir = std.Io.Dir.openDirAbsolute(io, "/sys/class/net", .{ .iterate = true }) catch return "?";
    defer dir.close(io);

    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        const is_tunnel =
            std.mem.startsWith(u8, entry.name, "tun") or
            std.mem.startsWith(u8, entry.name, "wg") or
            std.mem.startsWith(u8, entry.name, "tap") or
            std.mem.startsWith(u8, entry.name, "ppp");
        if (!is_tunnel) continue;

        // keep a private copy: value_buf formats over it next.
        const iface = util.snapshot(&iface_buf, entry.name);
        return std.mem.print(&value_buf, "up ({s})", .{iface}) catch "?";
    }
    return "down";
}
