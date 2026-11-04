// theme module: GTK theme / icon theme / font, parsed from
// $XDG_CONFIG_HOME (or $HOME/.config) gtk-3.0 then gtk-4.0
// settings.ini. Zero spawn; "?" when neither file yields anything.
const std = @import("std");
const util = @import("../util.zig");

var value_buf: [256]u8 = undefined;
var init_buf: [2048]u8 = undefined;
var theme_buf: [64]u8 = undefined;
var icon_buf: [64]u8 = undefined;
var font_buf: [64]u8 = undefined;
var path_buf: [128]u8 = undefined;

/// Scans one settings.ini, filling whichever of the three bufs is empty.
fn scanIni(content: []const u8, theme: *[]const u8, icons: *[]const u8, font: *[]const u8) void {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const eq = std.mem.findScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const val = std.mem.trim(u8, line[eq + 1 ..], " \t");
        if (val.len == 0) continue;
        if (theme.*.len == 0 and std.mem.eql(u8, key, "gtk-theme-name")) {
            theme.* = util.snapshot(&theme_buf, val);
        } else if (icons.*.len == 0 and std.mem.eql(u8, key, "gtk-icon-theme-name")) {
            icons.* = util.snapshot(&icon_buf, val);
        } else if (font.*.len == 0 and std.mem.eql(u8, key, "gtk-font-name")) {
            font.* = util.snapshot(&font_buf, val);
        }
    }
}

pub fn preset(environ: *const std.process.Environ.Map) []const u8 {
    var theme: []const u8 = "";
    var icons: []const u8 = "";
    var font: []const u8 = "";

    // config root: XDG_CONFIG_HOME when non-empty, else $HOME/.config
    const base: []const u8 = blk: {
        if (environ.get("XDG_CONFIG_HOME")) |x| {
            if (x.len != 0) break :blk util.snapshot(&path_buf, x);
        }
        const home = environ.get("HOME") orelse return "?";
        break :blk std.mem.print(&path_buf, "{s}/.config", .{home}) catch return "?";
    };

    const versions = [_][]const u8{ "gtk-3.0", "gtk-4.0" };
    for (versions) |version| {
        if (theme.len != 0 and icons.len != 0 and font.len != 0) break;

        // base may point at path_buf; the ini path overwrites it — build
        // from that same buffer before it changes. Copy base out first.
        var base_a: [128]u8 = undefined;
        const base_copy = util.snapshot(&base_a, base);

        const ipath = std.mem.print(&path_buf, "{s}/{s}/settings.ini", .{ base_copy, version }) catch continue;

        const content = util.readWholeFile(ipath, &init_buf) orelse continue;
        scanIni(content, &theme, &icons, &font);
    }

    var done: usize = 0;
    var fields_buf: [3][]const u8 = undefined;
    if (theme.len != 0) {
        fields_buf[done] = theme;
        done += 1;
    }
    if (icons.len != 0) {
        fields_buf[done] = icons;
        done += 1;
    }
    if (font.len != 0) {
        fields_buf[done] = font;
        done += 1;
    }
    if (done == 0) return "?";

    var pos: usize = 0;
    for (fields_buf[0..done], 0..) |field, i| {
        if (i != 0) {
            pos += (std.mem.print(value_buf[pos..], " / ", .{}) catch return value_buf[0..pos]).len;
        }
        pos += (std.mem.print(value_buf[pos..], "{s}", .{field}) catch return value_buf[0..pos]).len;
    }
    return value_buf[0..pos];
}
