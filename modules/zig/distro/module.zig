// distro module: distribution name from /etc/os-release (the BSDs answer
// "<BSD> <release>" from the libc uname, since std.c's utsname stays
// void for them: freebsd's libc inlines uname onto __xuname).
// Mirrors the old C modules: fill a static buffer, return a slice of it.
// Pure posix file reads — no io threading needed.
const std = @import("std");


var value_buf: [256]u8 = undefined;

const keys = [_][]const u8{ "PRETTY_NAME=", "NAME=" };

pub fn preset() []const u8 {
    if (@import("builtin").os.tag == .openbsd) {
        // no os-release on openbsd; uname's release answers: "OpenBSD 8.0".
        const obs = @import("../openbsd.zig");
        var rel_buf: [32]u8 = undefined;
        const release = obs.unameField(.release, &rel_buf) orelse return "OpenBSD";
        return std.mem.print(&value_buf, "OpenBSD {s}", .{release}) catch "OpenBSD";
    }
    if (@import("builtin").os.tag == .freebsd) {
        // same shape: libc's __xuname answers "FreeBSD 15.1".
        const f = @import("../freebsd.zig");
        var rel_buf: [32]u8 = undefined;
        const release = f.unameField(.release, &rel_buf) orelse return "FreeBSD";
        return std.mem.print(&value_buf, "FreeBSD {s}", .{release}) catch "FreeBSD";
    }
    if (@import("builtin").os.tag == .macos) {
        // no os-release either; kern.osproductversion answers the About
        // window's version, the major names it: "macOS Sequoia 15.1".
        const m = @import("../macos.zig");
        var ver_buf: [32]u8 = undefined;
        const version = m.productVersion(&ver_buf) orelse return "macOS";
        if (m.codename(version)) |name|
            return std.mem.print(&value_buf, "macOS {s} {s}", .{ name, version }) catch "macOS";
        return std.mem.print(&value_buf, "macOS {s}", .{version}) catch "macOS";
    }
    const fd = std.posix.openat(std.posix.AT.FDCWD, "/etc/os-release", .{ .ACCMODE = .RDONLY }, 0) catch
        return "unknown";
    defer _ = std.os.linux.close(fd);

    var raw: [8192]u8 = undefined;
    const len = readAll(fd, &raw);

    var lines = std.mem.splitScalar(u8, raw[0..len], '\n');
    while (lines.next()) |line| {
        for (keys) |key| {
            if (std.mem.startsWith(u8, line, key)) {
                const quoted = line[key.len..];
                const value = if (quoted.len >= 2 and quoted[0] == '"' and quoted[quoted.len - 1] == '"')
                    quoted[1 .. quoted.len - 1]
                else
                    quoted;
                @memcpy(value_buf[0..value.len], value);
                return value_buf[0..value.len];
            }
        }
    }
    return "unknown";
}

fn readAll(fd: std.posix.fd_t, buf: []u8) usize {
    var total: usize = 0;
    while (total < buf.len) {
        const n = std.posix.read(fd, buf[total..]) catch break;
        if (n == 0) break;
        total += n;
    }
    return total;
}
