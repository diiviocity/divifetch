// mount module: statfs(2) on a path, prints used / total sizes.
// Takes its argument like the C version did (config passed the mountpoint).
// std has no statfs wrapper in 0.15, so the kernel ABI struct and syscall
// are declared here directly (this Linux-only project's way of depending
// on nothing).
const std = @import("std");
const linux = std.os.linux;
const util = @import("../util.zig");

/// The x86_64 kernel's `struct statfs` layout (the BSD targets use
/// libc's statvfs(3) with each tree's own field order; the linux path
/// never links any of it).
const Statfs = extern struct {
    f_type: i64,
    f_bsize: i64,
    f_blocks: u64,
    f_bfree: u64,
    f_bavail: u64,
    f_files: i64,
    f_ffree: i64,
    f_fsid: [2]i32,
    f_namelen: i64,
    f_frsize: i64,
    f_flags: i64,
    f_spare: [4]i64,
};

var value_buf: [80]u8 = undefined;
var size_buf_used: [48]u8 = undefined;
var size_buf_total: [48]u8 = undefined;
var path_buf: [128:0]u8 = undefined;

fn statfs(path: []const u8) ?Statfs {
    const path_c = std.mem.printSentinel(&path_buf, "{s}", .{path}, 0) catch return null;
    var buf: Statfs = undefined;
    const rc = linux.syscall2(.statfs, @intFromPtr(path_c.ptr), @intFromPtr(&buf));
    if (@as(isize, @bitCast(rc)) != 0) return null;
    return buf;
}

fn humanSize(bytes: u64, out: []u8) []const u8 {
    const units = [_][]const u8{ " B", " KiB", " MiB", " GiB", " TiB" };
    var size: f64 = @floatFromInt(bytes);
    var unit: usize = 0;
    while (size >= 1024.0 and unit < units.len - 1) : (unit += 1) size /= 1024.0;
    return std.mem.print(out, "{d:.1}{s}", .{ size, units[unit] }) catch "?";
}

pub fn preset(path: []const u8) []const u8 {
    if (@import("builtin").os.tag == .openbsd) {
        const obs = @import("../openbsd.zig");
        const stat = obs.statvfsOf(path) orelse return "?";
        const block_size: u64 = if (stat.f_frsize != 0) stat.f_frsize else stat.f_bsize;
        const total = stat.f_blocks * block_size;
        const free = stat.f_bfree * block_size;
        const used = if (total > free) total - free else 0;

        const used_str = humanSize(used, &size_buf_used);
        const total_str = humanSize(total, &size_buf_total);
        return std.mem.print(&value_buf, "{s} / {s}", .{ used_str, total_str }) catch "?";
    }
    if (@import("builtin").os.tag == .freebsd) {
        const f = @import("../freebsd.zig");
        const stat = f.statvfsOf(path) orelse return "?";
        const block_size: u64 = if (stat.f_frsize != 0) stat.f_frsize else stat.f_bsize;
        const total = stat.f_blocks * block_size;
        const free = stat.f_bfree * block_size;
        const used = if (total > free) total - free else 0;

        const used_str = humanSize(used, &size_buf_used);
        const total_str = humanSize(total, &size_buf_total);
        return std.mem.print(&value_buf, "{s} / {s}", .{ used_str, total_str }) catch "?";
    }
    const stat = statfs(path) orelse return "?";

    const block_size: u64 = @intCast(if (stat.f_frsize != 0) stat.f_frsize else stat.f_bsize);
    const total = stat.f_blocks * block_size;
    const free = stat.f_bfree * block_size;
    const used = if (total > free) total - free else 0;

    const used_str = humanSize(used, &size_buf_used);
    const total_str = humanSize(total, &size_buf_total);
    return std.mem.print(&value_buf, "{s} / {s}", .{ used_str, total_str }) catch "?";
}
