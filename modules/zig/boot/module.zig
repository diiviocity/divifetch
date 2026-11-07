// boot module: UEFI vs BIOS, via the presence of efivars.
// Only ENOENT is a clean "BIOS" answer; other errors stay "?".
// macOS has one firmware per architecture and nothing to probe: Intel
// Macs boot Apple's EFI, Apple silicon boots iBoot.
const std = @import("std");

pub fn preset() []const u8 {
    if (@import("builtin").os.tag == .macos) {
        return if (@import("builtin").cpu.arch == .aarch64) "iBoot" else "UEFI";
    }
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
