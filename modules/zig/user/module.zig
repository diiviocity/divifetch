// user module: $USER, falling back to $LOGNAME. Always set on normal
// setups; "?" keeps the module honest for stripped environments.
const std = @import("std");
const util = @import("../util.zig");

var value_buf: [64]u8 = undefined;

pub fn preset(environ: *const std.process.Environ.Map) []const u8 {
    const user = util.envAny(environ, &.{ "USER", "LOGNAME" }) orelse return "?";
    return util.snapshot(&value_buf, user);
}
