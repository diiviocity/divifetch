// hostname module: nodename from uname(2) (the BSDs' libc uname, with
// freebsd's libc inlining it onto __xuname).
const std = @import("std");

var value_buf: [64]u8 = undefined;

pub fn preset() []const u8 {
    if (@import("builtin").os.tag == .openbsd) {
        const obs = @import("../openbsd.zig");
        return obs.unameField(.nodename, &value_buf) orelse "?";
    }
    if (@import("builtin").os.tag == .freebsd) {
        const f = @import("../freebsd.zig");
        return f.unameField(.nodename, &value_buf) orelse "?";
    }
    if (@import("builtin").os.tag == .macos) {
        const m = @import("../macos.zig");
        return m.unameField(.nodename, &value_buf) orelse "?";
    }
    const uts = std.posix.uname();
    const buf = uts.nodename; // [64:0]u8, NUL sentinel guaranteed
    const n = std.mem.findScalar(u8, &buf, 0) orelse buf.len;
    if (n == 0) return "?";
    @memcpy(value_buf[0..n], buf[0..n]);
    return value_buf[0..n];
}
