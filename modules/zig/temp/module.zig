// temp module: first thermal sensor under /sys/class/hwmon,
// formatted "<n>°C (chip)". The battery module's directory pattern.
// freebsd answers dev.cpu.0.temperature (the first core's reading).
const std = @import("std");
const util = @import("../util.zig");

var value_buf: [64]u8 = undefined;
var name_buf: [48]u8 = undefined;
var raw_buf: [32]u8 = undefined;
var path_buf: [96]u8 = undefined;

pub fn preset(io: std.Io) []const u8 {
    if (@import("builtin").os.tag == .freebsd) {
        const f = @import("../freebsd.zig");
        if (f.cpuTemperature(&value_buf)) |temp| return temp;
        return "?";
    }
    var dir = std.Io.Dir.openDirAbsolute(io, "/sys/class/hwmon", .{ .iterate = true }) catch return "?";
    defer dir.close(io);

    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (!std.mem.startsWith(u8, entry.name, "hwmon")) continue;

        // Chip label from the "name" file (coretemp, amdgpu, ...).
        var chip: []const u8 = "";
        {
            const name_path = std.mem.print(&path_buf, "/sys/class/hwmon/{s}/name", .{entry.name}) catch continue;
            if (util.readFirstLine(name_path, &name_buf)) |label| {
                chip = std.mem.trim(u8, name_buf[0..label.len], " \t");
            }
        }

        // First tempN_input file of this chip, millidegrees Celsius.
        const subdir_path = std.mem.print(&path_buf, "/sys/class/hwmon/{s}", .{entry.name}) catch continue;
        var subdir = std.Io.Dir.openDirAbsolute(io, subdir_path, .{ .iterate = true }) catch continue;
        defer subdir.close(io);
        var fit = subdir.iterate();
        while (fit.next(io) catch null) |file| {
            if (!std.mem.startsWith(u8, file.name, "temp")) continue;
            if (!std.mem.endsWith(u8, file.name, "_input")) continue;

            const tpath = std.mem.print(&path_buf, "/sys/class/hwmon/{s}/{s}", .{ entry.name, file.name }) catch continue;
            const raw = util.readFirstLine(tpath, &raw_buf) orelse continue;
            const milli = std.fmt.parseInt(i64, std.mem.trim(u8, raw, " \t"), 10) catch continue;
            if (milli < 0) continue;
            const celsius = @divTrunc(milli + 500, 1000); // nearest degree

            if (chip.len != 0)
                return std.mem.print(&value_buf, "{d}°C ({s})", .{ celsius, chip }) catch "?";
            return std.mem.print(&value_buf, "{d}°C", .{celsius}) catch "?";
        }
    }
    return "?";
}
