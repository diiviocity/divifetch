// swap module: SwapTotal/SwapFree from /proc/meminfo, same
// used/total presentation as the memory module. "?" means no swap.
// the BSDs answer from the kernel's swap counters: openbsd via the
// vm.uvmexp fields, freebsd via vm.swap_total / vm.swap_reserved.
const std = @import("std");
const util = @import("../util.zig");

var value_buf: [64]u8 = undefined;
var file_buf: [8192]u8 = undefined;

fn memInfoValue(line: []const u8, key: []const u8) ?u64 {
    if (!std.mem.startsWith(u8, line, key)) return null;
    const rest = std.mem.trim(u8, line[key.len..], " \t");
    const end = std.mem.findAny(u8, rest, " \t") orelse rest.len;
    return std.fmt.parseInt(u64, rest[0..end], 10) catch null;
}

pub fn preset() []const u8 {
    if (@import("builtin").os.tag == .openbsd) return openbsdPreset();
    if (@import("builtin").os.tag == .freebsd) return freebsdPreset();
    if (@import("builtin").os.tag == .macos) return macosPreset();

    const content = util.readWholeFile("/proc/meminfo", &file_buf) orelse return "?";

    var total: u64 = 0;
    var free: u64 = 0;
    var found = false;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (memInfoValue(line, "SwapTotal:")) |v| {
            total = v;
            found = true;
        } else if (memInfoValue(line, "SwapFree:")) |v| {
            free = v;
        }
    }
    if (!found or total == 0) return "?";

    const free_capped = @min(free, total);
    const used_kb: f64 = @floatFromInt(total - free_capped);
    const total_kb: f64 = @floatFromInt(total);

    if (total_kb >= 1024.0)
        return std.mem.print(&value_buf, "{d:.1} GiB / {d:.1} GiB", .{ used_kb / 1024.0, total_kb / 1024.0 }) catch "?";
    return std.mem.print(&value_buf, "{d:.0} MiB / {d:.0} MiB", .{ used_kb, total_kb }) catch "?";
}


fn openbsdPreset() []const u8 {
    const obs = @import("../openbsd.zig");
    const u = obs.uvm() orelse return "?";
    if (u.swpages <= 0) return "?"; // no swap configured

    const page: u64 = @intCast(@max(0, u.pagesize));
    const page_ok: u64 = if (page == 0) 4096 else page;
    const total: u64 = @as(u64, @intCast(u.swpages)) * page_ok;
    const used: u64 = @as(u64, @intCast(@max(0, u.swpginuse))) * page_ok;
    const used_capped = @min(used, total);

    const used_mib: f64 = @as(f64, @floatFromInt(used_capped)) / (1024.0 * 1024.0);
    const total_mib: f64 = @as(f64, @floatFromInt(total)) / (1024.0 * 1024.0);

    if (total_mib >= 1024.0)
        return std.mem.print(&value_buf, "{d:.1} GiB / {d:.1} GiB", .{ used_mib / 1024.0, total_mib / 1024.0 }) catch "?";
    return std.mem.print(&value_buf, "{d:.0} MiB / {d:.0} MiB", .{ used_mib, total_mib }) catch "?";
}

// macOS: vm.swapusage. dynamic_pager grows swapfiles on demand, so a
// total of 0 (no swapfile yet) is the "no swap" answer.
fn macosPreset() []const u8 {
    const m = @import("../macos.zig");
    const usage = m.swapUsage() orelse return "?";
    if (usage.total == 0) return "?";
    const used = @min(usage.used, usage.total);

    const used_mib: f64 = @as(f64, @floatFromInt(used)) / (1024.0 * 1024.0);
    const total_mib: f64 = @as(f64, @floatFromInt(usage.total)) / (1024.0 * 1024.0);

    if (total_mib >= 1024.0)
        return std.mem.print(&value_buf, "{d:.1} GiB / {d:.1} GiB", .{ used_mib / 1024.0, total_mib / 1024.0 }) catch "?";
    return std.mem.print(&value_buf, "{d:.0} MiB / {d:.0} MiB", .{ used_mib, total_mib }) catch "?";
}

fn freebsdPreset() []const u8 {
    const f = @import("../freebsd.zig");
    const total = f.swapTotal() orelse return "?";
    if (total <= 0) return "?"; // no swap configured
    const used: i64 = f.swapReserved() orelse 0;

    const used_mib: f64 = @as(f64, @floatFromInt(@max(0, used))) / (1024.0 * 1024.0);
    const total_mib: f64 = @as(f64, @floatFromInt(total)) / (1024.0 * 1024.0);

    if (total_mib >= 1024.0)
        return std.mem.print(&value_buf, "{d:.1} GiB / {d:.1} GiB", .{ used_mib / 1024.0, total_mib / 1024.0 }) catch "?";
    return std.mem.print(&value_buf, "{d:.0} MiB / {d:.0} MiB", .{ used_mib, total_mib }) catch "?";
}
