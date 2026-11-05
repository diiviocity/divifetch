// boot module: UEFI vs BIOS, via the presence of efivars.
// Only ENOENT is a clean "BIOS" answer; other errors stay "?".
const std = @import("std");

pub fn preset() []const u8 {
    const fd = std.posix.openat(
        std.posix.AT.FDCWD,
        "/sys/firmware/efi/efivars",
        .{ .ACCMODE = .RDONLY, .DIRECTORY = true },
        0,
    ) catch |err| switch (err) {
        error.FileNotFound => return "BIOS",
        else => return "?",
    };
    defer _ = std.os.linux.close(fd);
    return "UEFI";
}
