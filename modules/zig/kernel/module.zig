// Kernel module: release string via uname(2) (the BSDs through their
// own libc uname helpers in ../openbsd.zig / ../freebsd.zig).
const std = @import("std");

var value_buf: [65]u8 = undefined;

pub fn preset() []const u8 {
    if (@import("builtin").os.tag == .openbsd) {
        const obs = @import("../openbsd.zig");
        return obs.unameField(.release, &value_buf) orelse "?";
    }
    if (@import("builtin").os.tag == .freebsd) {
        const f = @import("../freebsd.zig");
        return f.unameField(.release, &value_buf) orelse "?";
    }
    const uts = std.posix.uname(); // lives on this function's stack
    const buf = uts.release; // [64:0]u8: NUL sentinel guaranteed
    const n = std.mem.findScalar(u8, &buf, 0) orelse buf.len;
    @memcpy(value_buf[0..n], buf[0..n]); // copy out to module scope first
    return value_buf[0..n];
}
