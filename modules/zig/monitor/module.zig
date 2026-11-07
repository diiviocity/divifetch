// monitor module: connected DRM outputs and their preferred mode
// from /sys/class/drm/<conn>/modes. Up to four outputs, "; "-joined.
// the kind spells monitor: display is a blip machine builtin (the
// generator's const carries the list), so its forms never reach the
// entry walk.
const std = @import("std");
const util = @import("../util.zig");

var value_buf: [160]u8 = undefined;
var enabled_buf: [16]u8 = undefined;
var modes_buf: [1024]u8 = undefined;
var path_buf: [96]u8 = undefined;

pub fn preset(io: std.Io) []const u8 {
    var dir = std.Io.Dir.openDirAbsolute(io, "/sys/class/drm", .{ .iterate = true }) catch return "?";
    defer dir.close(io);

    var count: usize = 0;
    var pos: usize = 0;
    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        // connector nodes look like "card0-eDP-1"; cardN devices don't
        const dash = std.mem.findScalar(u8, entry.name, '-') orelse continue;
        if (dash == 0 or !std.mem.startsWith(u8, entry.name, "card")) continue;

        var enabled = false;
        {
            const epath = std.mem.print(&path_buf, "/sys/class/drm/{s}/enabled", .{entry.name}) catch continue;
            const line = util.readFirstLine(epath, &enabled_buf) orelse continue;
            enabled = std.mem.eql(u8, std.mem.trim(u8, enabled_buf[0..line.len], " \t"), "enabled");
        }
        if (!enabled) continue;

        var res: []const u8 = "";
        {
            const mpath = std.mem.print(&path_buf, "/sys/class/drm/{s}/modes", .{entry.name}) catch continue;
            const block = util.readWholeFile(mpath, &modes_buf) orelse continue;
            if (block.len == 0) continue;
            // each mode line is "<WxH> <refresh> ..."; line one preferred
            const nl = std.mem.findScalar(u8, block, '\n') orelse block.len;
            const first = std.mem.trim(u8, block[0..nl], " \t\r");
            const sp = std.mem.findScalar(u8, first, ' ') orelse first.len;
            res = first[0..sp];
        }
        if (res.len == 0) continue;

        const sep: []const u8 = if (count == 0) "" else "; ";
        const written = std.mem.print(value_buf[pos..], "{s}{s}", .{ sep, res }) catch return value_buf[0..pos];
        pos += written.len;

        count += 1;
        if (count >= 4) break;
    }

    if (count == 0) return "?";
    return value_buf[0..pos];
}
