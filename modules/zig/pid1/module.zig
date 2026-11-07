// init module: pid 1's comm — one read instead of one spawned child
// (the BSDs through their kern.proc kinfo shapes: openbsd's p_comm in
// the openbsd layout, freebsd's ki_comm at its own offsets).
const std = @import("std");
const util = @import("../util.zig");

var value_buf: [32]u8 = undefined;

pub fn preset() []const u8 {
    const tag = @import("builtin").os.tag;
    if (tag == .openbsd or tag == .freebsd or tag == .macos) {
        // macOS answers launchd from its own kinfo_proc layout.
        const helper = if (tag == .openbsd)
            @import("../openbsd.zig")
        else if (tag == .freebsd)
            @import("../freebsd.zig")
        else
            @import("../macos.zig");
        const info = helper.procInfo(1) orelse return "?";
        if (info.comm.len > value_buf.len) return "?";
        @memcpy(value_buf[0..info.comm.len], info.comm);
        return value_buf[0..info.comm.len];
    }
    const comm = util.readFirstLine("/proc/1/comm", &value_buf) orelse return "?";
    const n = std.mem.findScalar(u8, value_buf[0..comm.len], 0) orelse comm.len;
    return value_buf[0..n];
}
