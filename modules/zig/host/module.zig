// host module: machine model from DMI (product_name, with
// board_name as fallback); openbsd reads hw.product, hw.vendor
// backing it up; macOS answers hw.model ("MacBookPro18,3"). Zero spawn.
const std = @import("std");
const util = @import("../util.zig");

var value_buf: [96]u8 = undefined;
var product_buf: [96]u8 = undefined;
var board_buf: [96]u8 = undefined;

pub fn preset() []const u8 {
    if (@import("builtin").os.tag == .macos) {
        const m = @import("../macos.zig");
        const model = m.hwModel(&product_buf) orelse return "?";
        const trimmed = std.mem.trim(u8, model, " \t");
        if (trimmed.len == 0) return "?";
        return util.snapshot(&value_buf, trimmed);
    }
    if (@import("builtin").os.tag == .openbsd) {
        const obs = @import("../openbsd.zig");
        // hw.product is DMI's product_name; hw.vendor backs it up on
        // machines that don't tell a product.
        for ([_]u32{ obs.HW_PRODUCT, obs.HW_VENDOR }) |name| {
            var obs_buf: [128]u8 = undefined;
            const value = obs.hwStr(name, &obs_buf) orelse continue;
            const trimmed = std.mem.trim(u8, value, " \t");
            if (trimmed.len == 0) continue;
            if (trimmed.len > value_buf.len) continue;
            @memcpy(value_buf[0..trimmed.len], trimmed);
            return value_buf[0..trimmed.len];
        }
        return "?";
    }
    var dmi_value: []const u8 = "";

    const product_path = "/sys/devices/virtual/dmi/id/product_name";
    if (util.readFirstLine(product_path, &product_buf)) |p| {
        if (p.len != 0) dmi_value = util.snapshot(&value_buf, std.mem.trim(u8, product_buf[0..p.len], " \t"));
    }

    if (dmi_value.len == 0) {
        const board_path = "/sys/devices/virtual/dmi/id/board_name";
        if (util.readFirstLine(board_path, &board_buf)) |b| {
            if (b.len != 0) dmi_value = util.snapshot(&value_buf, std.mem.trim(u8, board_buf[0..b.len], " \t"));
        }
    }

    if (dmi_value.len == 0) return "?";
    return dmi_value;
}
