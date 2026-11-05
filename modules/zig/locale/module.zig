// locale module: $LC_ALL, falling back to $LANG.
const std = @import("std");
const util = @import("../util.zig");

var value_buf: [48]u8 = undefined;

pub fn preset(environ: *const std.process.Environ.Map) []const u8 {
    const locale = util.envAny(environ, &.{ "LC_ALL", "LANG" }) orelse return "?";
    return util.snapshot(&value_buf, locale);
}
