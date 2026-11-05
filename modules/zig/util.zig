// util.zig — small, dependency-free helpers shared by all modules.
// Mirrors the old module.h conventions: caller-or-module-owned static
// buffers, no allocator, pure reads, safe failures ("?") instead of aborts.
// Single-threaded by design: the fetch prints once, top to bottom.
//
// Zig 0.17: process I/O functions take an `io` (std.Io) and the
// environment lookups take the environ map built by start.zig.
const std = @import("std");
const is_openbsd = @import("builtin").os.tag == .openbsd;
const is_freebsd = @import("builtin").os.tag == .freebsd;

/// Reads a whole file (smaller than `buf`) into `buf`.
/// Returns null if the file cannot be opened or read at all.
pub fn readWholeFile(path: []const u8, buf: []u8) ?[]const u8 {
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0) catch return null;
    defer closeFdAny(fd);

    var total: usize = 0;
    while (total < buf.len) {
        const n = std.posix.read(fd, buf[total..]) catch break;
        if (n == 0) break;
        total += n;
    }
    closeFdAny(fd);
    return buf[0..total];
}

/// Reads just the first line of a text file, without the line ending.
/// `buf` only needs to hold that line.
pub fn readFirstLine(path: []const u8, buf: []u8) ?[]const u8 {
    // /proc and /sys report file size 0, so reading must run to EOF.
    const content = readWholeFile(path, buf) orelse return null;
    if (content.len == 0) return null;
    const nl = std.mem.findScalar(u8, content, '\n') orelse content.len;
    return std.mem.trimEnd(u8, content[0..nl], "\r");
}

/// First non-empty value of the given environment variables.
pub fn envAny(environ: *const std.process.Environ.Map, names: []const []const u8) ?[]const u8 {
    for (names) |name| {
        const value = environ.get(name) orelse continue;
        if (value.len != 0) return value;
    }
    return null;
}

/// Base name after the last '/' of a path.
pub fn pathBaseName(path: []const u8) []const u8 {
    if (std.mem.findScalarLast(u8, path, '/')) |i| return path[i + 1 ..];
    return path;
}

/// Runs `cmd` via /bin/sh and captures stdout until EOF (popen equivalent).
/// stderr stays attached to the terminal; callers pass "2>&1" in the command
/// string when they want it merged, like the C versions did.
/// Retained for legacy `command` config entries that may carry arbitrary
/// shell syntax; version checks use runCaptureArgv instead.
/// Returns a slice of `buf`; empty slice on failure.
pub fn runCapture(io: std.Io, cmd: []const u8, buf: []u8) []const u8 {
    var child = std.process.spawn(io, .{
        .argv = &.{ "/bin/sh", "-c", cmd },
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .inherit,
    }) catch return buf[0..0];

    const fd = child.stdout.?.handle;
    var total: usize = 0;
    while (total < buf.len) {
        const n = std.posix.read(fd, buf[total..]) catch break;
        if (n == 0) break;
        total += n;
    }
    _ = child.wait(io) catch {};
    return buf[0..total];
}

/// Runs `argv` directly (fork+exec) and captures stdout, then stderr, into
/// `buf`. No /bin/sh wrapper, no "-c" string: std.process.spawn's default
/// exe mode (.detect) resolves a bare argv[0] ("zsh", "opencode", ...) the
/// same way /bin/sh does, so callers pass the raw program name as before.
/// stderr is drained to EOF *after* stdout (sequential, not interleaved),
/// a deliberate deviation from the old `"%s --version 2>&1"` a single merged
/// pipe provided: version strings are tiny (well under the pipe buffer), so
/// the swap never risks a full-pipe deadlock, and ordering only matters for
/// programs that write to both streams. Unknown program names fail at spawn
/// and yield an empty slice, just like a failed shell invocation did.
/// Returns a slice of `buf`; empty slice on failure.
pub fn runCaptureArgv(io: std.Io, argv: []const []const u8, buf: []u8) []const u8 {
    var child = std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    }) catch return buf[0..0];

    const stdout_fd = child.stdout.?.handle;
    var total: usize = 0;
    while (total < buf.len) {
        const n = std.posix.read(stdout_fd, buf[total..]) catch break;
        if (n == 0) break;
        total += n;
    }

    // Drain stderr into whatever buffer room is left, appending after the
    // stdout payload (see ordering note above).
    const stderr_fd = child.stderr.?.handle;
    while (total < buf.len) {
        const n = std.posix.read(stderr_fd, buf[total..]) catch break;
        if (n == 0) break;
        total += n;
    }

    // wait reaps the child and closes both pipe descriptors.
    _ = child.wait(io) catch {};
    return buf[0..total];
}

/// Cuts `s` off after the first newline of a captured line.
pub fn firstLine(s: []const u8) []const u8 {
    const nl = std.mem.findScalar(u8, s, '\n') orelse s.len;
    return std.mem.trimEnd(u8, s[0..nl], "\r");
}

/// Strips trailing newline characters from captured output, C-style.
pub fn trimTrailingNewlines(s: []const u8) []const u8 {
    return std.mem.trimEnd(u8, s, "\r\n");
}

/// Walks a version string to the first run of digits and dots, e.g.
/// "zsh 5.9 (x86_64-pc-linux-gnu)" -> "5.9".
pub fn extractVersion(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and !std.ascii.isDigit(s[start])) start += 1;
    var end = start;
    while (end < s.len and (std.ascii.isDigit(s[end]) or s[end] == '.')) end += 1;
    return s[start..end];
}

/// close for the fds the file-readers opened: the linux build rides its
/// own close syscall, openbsd gets libc's (this fork's std.posix has no
/// close to lean on).
fn closeFdAny(fd: std.posix.fd_t) void {
    if (is_openbsd) {
        @import("./openbsd.zig").closeFd(fd);
        return;
    }
    if (is_freebsd) {
        @import("./freebsd.zig").closeFd(fd);
        return;
    }
    _ = std.os.linux.close(fd);
}

/// True if `name` equals one of the listed names.
pub fn inList(name: []const u8, list: []const []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, name, item)) return true;
    }
    return false;
}

/// Same as inList but case-insensitive (the C modules used strcasecmp).
pub fn inListIgnoreCase(name: []const u8, list: []const []const u8) bool {
    for (list) |item| {
        if (std.ascii.eqlIgnoreCase(name, item)) return true;
    }
    return false;
}

/// Parses /proc/<pid>/stat: returns comm (inside the parentheses) and ppid.
/// comm points into a module-local buffer, valid until the next procStat call.
pub fn procStat(pid: std.posix.pid_t) ?struct { comm: []const u8, ppid: std.posix.pid_t } {
    if (is_openbsd or is_freebsd) {
        // the BSDs have no procfs; kern.proc.pid,<pid> answers instead,
        // with each kernel's own kinfo_proc shape.
        const helper = if (is_openbsd) @import("./openbsd.zig") else @import("./freebsd.zig");
        const info = helper.procInfo(pid) orelse return null;
        return .{ .comm = info.comm, .ppid = info.ppid };
    }
    var raw_buf: [512]u8 = undefined;
    var path_buf: [32]u8 = undefined;
    const path = std.mem.print(&path_buf, "/proc/{d}/stat", .{pid}) catch return null;
    const raw = readFirstLine(path, &raw_buf) orelse return null;

    const lp = std.mem.findScalar(u8, raw, '(') orelse return null;
    const rp = std.mem.findScalarLast(u8, raw, ')') orelse return null;
    if (lp >= rp) return null;

    // After the process name: " S <ppid> ..."
    const rest = std.mem.trimStart(u8, raw[rp + 1 ..], " ");
    if (rest.len < 2) return null; // rest[0] is the state character
    const fields = std.mem.trimStart(u8, rest[1..], " ");
    const end = std.mem.findScalar(u8, fields, ' ') orelse fields.len;
    const ppid = std.fmt.parseInt(std.posix.pid_t, fields[0..end], 10) catch return null;

    return .{ .comm = raw[lp + 1 .. rp], .ppid = ppid };
}

/// Counts non-overlapping occurrences of `needle` while streaming `file`
/// through `chunk` (works for files of any size, like the C byte-loops).
/// `start_count` seeds the result. null if the file can't be opened.
pub fn countMatchesFile(path: []const u8, needle: []const u8, chunk: []u8, start_count: usize) ?usize {
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0) catch return null;
    defer closeFdAny(fd);

    var count = start_count;
    var match: usize = 0;
    while (true) {
        const n = std.posix.read(fd, chunk) catch break;
        if (n == 0) break;
        for (chunk[0..n]) |c| {
            if (c == needle[match]) {
                match += 1;
                if (match == needle.len) {
                    count += 1;
                    match = 0;
                }
            } else {
                match = if (c == needle[0]) 1 else 0;
            }
        }
    }
    return count;
}

/// Counts entries whose name does not start with '.' in a directory.
/// null if the directory can't be opened (the C versions treat that
/// differently from a count of zero, so keep the distinction).
pub fn countNonDotEntries(io: std.Io, path: []const u8) ?usize {
    var dir = std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true }) catch return null;
    defer dir.close(io);

    var count: usize = 0;
    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.name.len > 0 and entry.name[0] != '.') count += 1;
    }
    return count;
}

/// Copies `src` into `dst` (must be large enough) and returns the copy's
/// slice. Used to extend slices that point at reused buffers.
pub fn snapshot(dst: []u8, src: []const u8) []const u8 {
    const n = @min(src.len, dst.len);
    @memcpy(dst[0..n], src[0..n]);
    return dst[0..n];
}
