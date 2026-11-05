// gpu module: GPUs via /sys/class/drm card devices. Zero spawn: reads the
// vendor id and the DRIVER= line of each card's uevent, with a
// product_name override when a driver exposes one (some amdgpu setups do).
// A full vendor:device -> marketing-name decode table was consciously
// skipped - divifetch doesn't embed databases.
const std = @import("std");
const util = @import("../util.zig");

var value_buf: [192]u8 = undefined;
var uevent_buf: [2048]u8 = undefined;
var id_buf: [32]u8 = undefined;
var product_buf: [64]u8 = undefined;
var path_buf: [96]u8 = undefined;

const Vendors = [_]struct { id: u16, name: []const u8 }{
    .{ .id = 0x1002, .name = "AMD" },
    .{ .id = 0x1022, .name = "AMD" },
    .{ .id = 0x10de, .name = "NVIDIA" },
    .{ .id = 0x8086, .name = "Intel" },
    .{ .id = 0x1af4, .name = "virtio" },
    .{ .id = 0x15ad, .name = "VMware" },
    .{ .id = 0x1b36, .name = "QEMU" },
};

pub fn preset(io: std.Io) []const u8 {
    var dir = std.Io.Dir.openDirAbsolute(io, "/sys/class/drm", .{ .iterate = true }) catch return "?";
    defer dir.close(io);

    var count: usize = 0;
    var pos: usize = 0;
    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        // card devices only, not "card0-DP-1" connectors
        if (!std.mem.startsWith(u8, entry.name, "card")) continue;
        if (std.mem.findScalar(u8, entry.name, '-') != null) continue;

        // vendor id
        const vpath = std.mem.print(&path_buf, "/sys/class/drm/{s}/device/vendor", .{entry.name}) catch continue;
        const vraw = util.readFirstLine(vpath, &id_buf) orelse continue;
        const vid = std.fmt.parseInt(u16, vraw, 0) catch continue;
        var vname: []const u8 = "";
        for (Vendors) |v| {
            if (v.id == vid) {
                vname = v.name;
                break;
            }
        }
        if (vname.len == 0) continue;

        // driver name via DRIVER= line in the device uevent
        var dname: []const u8 = "";
        {
            const dpath = std.mem.print(&path_buf, "/sys/class/drm/{s}/device/uevent", .{entry.name}) catch "";
            if (dpath.len != 0) {
                if (util.readWholeFile(dpath, &uevent_buf)) |uevent| {
                    var ulines = std.mem.splitScalar(u8, uevent, '\n');
                    while (ulines.next()) |uline| {
                        if (std.mem.startsWith(u8, uline, "DRIVER=")) {
                            dname = std.mem.trimEnd(u8, uline["DRIVER=".len..], " \t\r");
                            break;
                        }
                    }
                }
            }
        }

        // product_name override, when the driver exposes one
        var pname: []const u8 = "";
        {
            const ppath = std.mem.print(&path_buf, "/sys/class/drm/{s}/device/product_name", .{entry.name}) catch "";
            if (ppath.len != 0) {
                if (util.readFirstLine(ppath, &product_buf)) |pr| {
                    pname = std.mem.trim(u8, product_buf[0..pr.len], " \t");
                }
            }
        }

        const tail = if (pname.len != 0) pname else if (dname.len != 0) dname else "";
        const sep: []const u8 = if (count == 0) "" else "; ";
        const written = if (tail.len != 0)
            std.mem.print(value_buf[pos..], "{s}{s} ({s})", .{ sep, vname, tail })
        else
            std.mem.print(value_buf[pos..], "{s}{s}", .{ sep, vname });
        pos += (written catch return value_buf[0..pos]).len;

        count += 1;
        if (count >= 3) break;
    }

    if (count == 0) return "?";
    return value_buf[0..pos];
}
