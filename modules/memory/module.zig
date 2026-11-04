// memory module: parses /proc/meminfo, prints used / total (the BSDs
// answer the same pair from the kernel's page counters: openbsd via
// vm.uvmexp, freebsd via vm.stats.vm.* and hw.physmem).
const std = @import("std");
const util = @import("../util.zig");

var value_buf: [64]u8 = undefined;
var file_buf: [8192]u8 = undefined;

/// "MemTotal:  32871228 kB" -> the integer, for the given key.
fn memInfoValue(line: []const u8, key: []const u8) ?u64 {
    if (!std.mem.startsWith(u8, line, key)) return null;
    var rest = std.mem.trim(u8, line[key.len..], " \t");
    const end = std.mem.findAny(u8, rest, " \t") orelse rest.len;
    return std.fmt.parseInt(u64, rest[0..end], 10) catch null;
}

pub fn preset() []const u8 {
    if (@import("builtin").os.tag == .openbsd) return openbsdPreset();
    if (@import("builtin").os.tag == .freebsd) return freebsdPreset();

    const content = util.readWholeFile("/proc/meminfo", &file_buf) orelse return "?";

    var total: u64 = 0;
    var available: u64 = 0;
    var free: u64 = 0;
    var buffers: u64 = 0;
    var cached: u64 = 0;
    var shmem: u64 = 0;
    var s_reclaimable: u64 = 0;
    var found = false;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (memInfoValue(line, "MemTotal:")) |v| {
            total = v;
            found = true;
        } else if (memInfoValue(line, "MemAvailable:")) |v| {
            available = v;
        } else if (memInfoValue(line, "MemFree:")) |v| {
            free = v;
        } else if (memInfoValue(line, "Buffers:")) |v| {
            buffers = v;
        } else if (memInfoValue(line, "Cached:")) |v| {
            cached = v;
        } else if (memInfoValue(line, "Shmem:")) |v| {
            shmem = v;
        } else if (memInfoValue(line, "SReclaimable:")) |v| {
            s_reclaimable = v;
        }
    }
    if (!found) return "?";

    // Old kernels lack MemAvailable: rebuild it the way the C module did,
    // with saturation so a malformed file can't wrap around.
    if (available == 0 or available >= total) {
        available = free + buffers + cached + s_reclaimable;
        available -|= shmem;
        available = @min(available, total);
    }

    const used_mib: f64 = @as(f64, @floatFromInt(total - available)) / 1024.0;
    const total_mib: f64 = @as(f64, @floatFromInt(total)) / 1024.0;

    if (total_mib >= 1024.0)
        return std.mem.print(&value_buf, "{d:.1} GiB / {d:.1} GiB", .{ used_mib / 1024.0, total_mib / 1024.0 }) catch "?";
    return std.mem.print(&value_buf, "{d:.0} MiB / {d:.0} MiB", .{ used_mib, total_mib }) catch "?";
}


fn openbsdPreset() []const u8 {
    const obs = @import("../openbsd.zig");
    const phys = obs.physmem() orelse return "?";
    if (phys <= 0) return "?";
    const u = obs.uvm() orelse return "?";

    // used = everything but free and inactive pages: inactive is
    // openbsd's reclaimable page cache, the MemAvailable analogue.
    const page_size: u64 = @intCast(@max(0, u.pagesize));
    const free: u64 = @intCast(@max(0, u.free));
    const inactive: u64 = @intCast(@max(0, u.inactive));
    const total: u64 = @intCast(phys);
    const reclaimable_pages = free +| inactive;
    const page = if (page_size == 0) 4096 else page_size;
    const reclaimable = reclaimable_pages *| page;
    const used = if (total > reclaimable) total - reclaimable else 0;

    const used_mib: f64 = @as(f64, @floatFromInt(used)) / (1024.0 * 1024.0);
    const total_mib: f64 = @as(f64, @floatFromInt(total)) / (1024.0 * 1024.0);

    if (total_mib >= 1024.0)
        return std.mem.print(&value_buf, "{d:.1} GiB / {d:.1} GiB", .{ used_mib / 1024.0, total_mib / 1024.0 }) catch "?";
    return std.mem.print(&value_buf, "{d:.0} MiB / {d:.0} MiB", .{ used_mib, total_mib }) catch "?";
}

fn freebsdPreset() []const u8 {
    const f = @import("../freebsd.zig");
    const phys = f.physmem() orelse return "?";
    if (phys <= 0) return "?";
    const free = f.freePages() orelse return "?";
    const inactive = f.inactivePages() orelse 0;

    const page_size: u64 = @intCast(@max(0, f.pageSize() orelse 4096));
    const page = if (page_size == 0) 4096 else page_size;
    const total: u64 = @intCast(phys);
    const seen = @as(u64, @intCast(@max(0, free))) +| @as(u64, @intCast(@max(0, inactive)));
    // used = everything but free and inactive pages, the openbsd branch's
    // arithmetic: inactive is the reclaimable page cache.
    const reclaimable = seen *| page;
    const used = if (total > reclaimable) total - reclaimable else 0;

    const used_mib: f64 = @as(f64, @floatFromInt(used)) / (1024.0 * 1024.0);
    const total_mib: f64 = @as(f64, @floatFromInt(total)) / (1024.0 * 1024.0);

    if (total_mib >= 1024.0)
        return std.mem.print(&value_buf, "{d:.1} GiB / {d:.1} GiB", .{ used_mib / 1024.0, total_mib / 1024.0 }) catch "?";
    return std.mem.print(&value_buf, "{d:.0} MiB / {d:.0} MiB", .{ used_mib, total_mib }) catch "?";
}
