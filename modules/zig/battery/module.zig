// battery module: capacity + status of the first BAT* power supply
// (the BSDs read the same pair from the kernel's power tree: openbsd
// out of the apm device, freebsd out of hw.acpi.battery.*; macOS asks
// IOKit's power sources, the pmset(1) keys, dlopen'd).
const std = @import("std");
const util = @import("../util.zig");

var value_buf: [64]u8 = undefined;
var path_buf: [96]u8 = undefined;
var cap_buf: [32]u8 = undefined;
var status_buf: [32]u8 = undefined;

pub fn preset(io: std.Io) []const u8 {
    if (@import("builtin").os.tag == .macos) {
        const m = @import("../macos.zig");
        const bat = m.battery() orelse return "?";
        return std.mem.print(&value_buf, "{d}% ({s})", .{ bat.percent, bat.status }) catch "?";
    }
    if (@import("builtin").os.tag == .freebsd) {
        const f = @import("../freebsd.zig");
        const life_raw = f.batteryLife() orelse return "?";
        if (life_raw < 0 or life_raw > 100) return "?"; // no battery
        const life: u8 = @intCast(life_raw);
        const state = f.batteryState() orelse 0;
        // hw.acpi.battery.state is a bitmask: 1 discharging, 2 charging,
        // 4 critical; 7 carries them all when nothing is present.
        const F_CHARGING: i32 = 2;
        const state_str = if (state & F_CHARGING != 0) "Charging" else "Discharging";
        return std.mem.print(&value_buf, "{d}% ({s})", .{ life, state_str }) catch "?";
    }
    if (@import("builtin").os.tag == .openbsd) {
        const obs = @import("../openbsd.zig");
        // APM_IOC_GETPOWER's battery_state spells apm(8) -b: 0 high,
        // 1 low, 2 critical, 3 charging, 4 absent, 0xff unknown.
        const APM_BATT_ABSENT: u8 = 4; // spelled by apm(8), not by the header
        const info = obs.apmInfo() orelse return "?";
        if (info.battery_life == obs.APM_BATT_LIFE_UNKNOWN or
            info.battery_state == obs.APM_BATT_UNKNOWN or
            info.battery_state == APM_BATT_ABSENT)
            return "?";
        const state = if (info.battery_state == obs.APM_BATT_CHARGING)
            "Charging"
        else
            "Discharging";
        return std.mem.print(&value_buf, "{d}% ({s})", .{ info.battery_life, state }) catch "?";
    }
    var dir = std.Io.Dir.openDirAbsolute(io, "/sys/class/power_supply", .{ .iterate = true }) catch
        return "?";
    defer dir.close(io);

    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (!std.mem.startsWith(u8, entry.name, "BAT")) continue;

        const cap_path = std.mem.print(&path_buf, "/sys/class/power_supply/{s}/capacity", .{entry.name}) catch continue;
        var cap = util.readFirstLine(cap_path, &cap_buf) orelse continue;

        // Read the status next; path_buf is reused for the second path, but
        // cap lives in its own buffer, so both stay valid at once.
        const status_path = std.mem.print(&path_buf, "/sys/class/power_supply/{s}/status", .{entry.name}) catch continue;
        var status = util.readFirstLine(status_path, &status_buf) orelse "Unknown";

        if (util.trimTrailingNewlines(cap).len == 0) continue;
        cap = util.trimTrailingNewlines(cap);
        status = util.trimTrailingNewlines(status);

        return std.mem.print(&value_buf, "{s}% ({s})", .{ cap, status }) catch "?";
    }
    return "?";
}
