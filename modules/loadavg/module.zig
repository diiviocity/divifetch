// loadavg module: the first three fields of /proc/loadavg (the BSDs
// through getloadavg(3), the kernel's own f64 triple).
const std = @import("std");
const util = @import("../util.zig");

var value_buf: [32]u8 = undefined;
var line_buf: [64]u8 = undefined;

pub fn preset() []const u8 {
    if (@import("builtin").os.tag == .openbsd) {
        const obs = @import("../openbsd.zig");
        var avg: [3]f64 = undefined;
        if (!obs.loadavg(&avg)) return "?";
        return std.mem.print(&value_buf, "{d:.2} {d:.2} {d:.2}", .{ avg[0], avg[1], avg[2] }) catch "?";
    }
    if (@import("builtin").os.tag == .freebsd) {
        const f = @import("../freebsd.zig");
        var avg: [3]f64 = undefined;
        if (!f.loadavg(&avg)) return "?";
        return std.mem.print(&value_buf, "{d:.2} {d:.2} {d:.2}", .{ avg[0], avg[1], avg[2] }) catch "?";
    }
    const line = util.readFirstLine("/proc/loadavg", &line_buf) orelse return "?";

    var pos: usize = 0;
    var token: usize = 0;
    var it = std.mem.splitScalar(u8, line, ' ');
    while (it.next()) |field| {
        if (field.len == 0) continue;
        if (token == 3) break;
        if (token != 0) {
            if (pos >= value_buf.len) break;
            value_buf[pos] = ' ';
            pos += 1;
        }
        const n = @min(field.len, value_buf.len - pos);
        @memcpy(value_buf[pos..][0..n], field[0..n]);
        pos += n;
        token += 1;
    }

    if (token < 3) return "?";
    return value_buf[0..pos];
}
