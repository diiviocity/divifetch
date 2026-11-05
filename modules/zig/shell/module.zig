// shell module: walks up the process tree to the nearest shell,
// falls back to $SHELL, then appends the shell's version.
const std = @import("std");
const util = @import("../util.zig");

const shells = [_][]const u8{ "sh", "ash", "bash", "zsh", "ksh", "mksh", "csh", "tcsh", "fish", "dash", "nu", "elvish", "pwsh" };

var value_buf: [256]u8 = undefined;
var comm_buf: [64]u8 = undefined;
var out_buf: [256]u8 = undefined;

pub fn preset(io: std.Io, environ: *const std.process.Environ.Map) []const u8 {
    var pid = std.posix.getppid();
    var comm: []const u8 = "";
    var depth: usize = 0;
    while (pid > 1 and depth < 16) : (depth += 1) {
        const stat = util.procStat(pid) orelse break;
        if (util.inList(stat.comm, &shells)) {
            comm = stat.comm;
            break;
        }
        pid = stat.ppid;
    }

    if (comm.len == 0) {
        const env_shell = util.envAny(environ, &.{"SHELL"}) orelse return "?";
        comm = util.pathBaseName(env_shell);
    }

    // procStat's buffer gets reused on the next call — keep our own copy.
    comm = util.snapshot(&comm_buf, comm);

    // Version check execs the shell binary directly (bare name; PATH is how
    // the old "{s} --version 2>&1" line found it too) — no /bin/sh -c.
    const ver = util.extractVersion(util.firstLine(util.runCaptureArgv(io, &.{ comm, "--version" }, &out_buf)));

    if (ver.len != 0) return std.mem.print(&value_buf, "{s} {s}", .{ comm, ver }) catch "?";
    return util.snapshot(&value_buf, comm);
}
