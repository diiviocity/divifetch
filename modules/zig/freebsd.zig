// freebsd.zig: the OS's own yard for the module variants. only the
// comptime-freebsd branches reach this file — a linux build never parses
// it and never links anything here, and libc carries the externs on a
// freebsd target (the one place the project's no-libc rule doesn't
// hold: freebsd IS a libc system).
//
// every ABI fact is transcribed from the sysroot headers the build links
// against — usr/include/{sys,net,machine,x86/...} — so a kernel that
// changed a layout answers "?" rather than lying about it.
const std = @import("std");

// ─── libc ──────────────────────────────────────────────────────────────
extern "c" fn sysctl(name: [*]const c_int, namelen: c_uint, oldp: ?*anyopaque, oldlenp: ?*usize, newp: ?*const anyopaque, newlen: usize) c_int;
extern "c" fn sysctlbyname(name: [*:0]const u8, oldp: ?*anyopaque, oldlenp: ?*usize, newp: ?*const anyopaque, newlen: usize) c_int;
extern "c" fn clock_gettime(clk_id: c_int, tp: *Timespec) c_int;
extern "c" fn getloadavg(avg: [*]f64, nelem: c_int) c_int;
extern "c" fn statvfs(path: [*:0]const u8, buf: *Statvfs) c_int;
extern "c" fn getifaddrs(ifs: *?*Ifaddrs) c_int;
extern "c" fn freeifaddrs(ifs: ?*Ifaddrs) void;
extern "c" fn close(fd: c_int) c_int;
// freebsd's libc keeps no uname symbol: sys/utsname.h inlines it onto
// __xuname(SYS_NMLN=256, buf), five 256-byte NUL-padded fields.
extern "c" fn __xuname(nmlen: c_int, uts: *Utsname) c_int;

// ─── sysctl: kern.proc needs the numeric tree; everything that has a
// name rides sysctlbyname (freebsd numbers its vm/hw trees differently
// per release, names don't move). ─────────────────────────────────────
const CTL_KERN: c_int = 1;
const KERN_PROC: c_int = 14; // sys/sysctl.h: freebsd kept the old number
const KERN_PROC_PID: c_int = 1;

pub fn sysctlBytes(name: []const c_int, buf: []u8) ?[]const u8 {
    var written: usize = buf.len;
    const rc = sysctl(name.ptr, @intCast(name.len), buf.ptr, &written, null, 0);
    if (rc != 0) return null;
    if (written > buf.len) return null;
    return buf[0..written];
}

pub fn nameBytes(name: [*:0]const u8, buf: []u8) ?[]const u8 {
    var written: usize = buf.len;
    const rc = sysctlbyname(name, buf.ptr, &written, null, 0);
    if (rc != 0) return null;
    if (written > buf.len) return null;
    return buf[0..written];
}

/// one integer out of a named node; oldlenp tells the real width.
pub fn nameInt(name: [*:0]const u8) ?i64 {
    var buf: [8]u8 = undefined;
    const bytes = nameBytes(name, &buf) orelse return null;
    return switch (bytes.len) {
        4 => @as(i32, @bitCast(@as(u32, @truncate(std.mem.readInt(u64, &buf, .little))))),
        8 => std.mem.readInt(i64, &buf, .little),
        else => null,
    };
}

/// a named sysctl string (hw.model, ...), NUL-trimmed.
pub fn nameStr(name: [*:0]const u8, buf: []u8) ?[]const u8 {
    const bytes = nameBytes(name, buf) orelse return null;
    const end = std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len;
    if (end == 0) return null;
    return bytes[0..end];
}

// ─── uname (sys/utsname.h inlines uname(3) onto __xuname) ──────────────
pub const Utsname = extern struct {
    sysname: [256]u8,
    nodename: [256]u8,
    release: [256]u8,
    version: [256]u8,
    machine: [256]u8,
};

var uts_buf: Utsname = undefined;

/// one uname field, NUL-trimmed. `which` is one of release/node.
pub fn unameField(which: enum { release, nodename }, out: []u8) ?[]const u8 {
    if (__xuname(256, &uts_buf) != 0) return null;
    const field: []const u8 = switch (which) {
        .release => &uts_buf.release,
        .nodename => &uts_buf.nodename,
    };
    const end = std.mem.indexOfScalar(u8, field, 0) orelse field.len;
    if (end == 0 or end >= out.len) return null;
    @memcpy(out[0..end], field[0..end]);
    return out[0..end];
}

// ─── kinfo_proc (sys/user.h) — offsets computed from the header's own
// field order (pid_t/uid_t/gid_t 4, sigset_t 16, fixpt_t 4, segsz_t 8,
// timeval 16, priority 4, rusage 144; KI_NSPARE_INT 2, KI_NSPARE_LONG
// 12, KI_NSPARE_PTR 4, comm 20 after the ki_* name run). the struct is
// 1088 bytes; the kern.proc request returns exactly one. ────────────────
const kinfo_size: usize = 1088;
const kinfo_pid_off: usize = 72; // int ki_pid
const kinfo_ppid_off: usize = 76; // int ki_ppid
const kinfo_comm_off: usize = 447; // char ki_comm[COMMLEN+1]

var kinfo_buf: [1200]u8 align(8) = undefined;

/// one process' identity, the shape the /proc walk needs.
pub fn procInfo(pid: i32) ?struct { comm: []const u8, ppid: i32 } {
    const bytes = sysctlBytes(&.{ CTL_KERN, KERN_PROC, KERN_PROC_PID, pid }, &kinfo_buf) orelse return null;
    if (bytes.len < kinfo_ppid_off + 4 or bytes.len > kinfo_size) return null;
    const b = kinfo_buf;

    const ppid: i32 = @bitCast(std.mem.readInt(u32, b[kinfo_ppid_off..][0..4], .little));
    const raw_comm = b[kinfo_comm_off..][0..20];
    const end = std.mem.indexOfScalar(u8, raw_comm, 0) orelse raw_comm.len;
    if (end == 0) return null;
    return .{ .comm = raw_comm[0..end], .ppid = ppid };
}

// ─── battery over hw.acpi.* (sysctl(2) through dev/acpica: state is a
// bitmask — 1 discharging, 2 charging, 4 critical; 7 carries them all
// when the battery's absent; life < 0 means no battery to report) ──────
pub fn batteryLife() ?i64 {
    return nameInt("hw.acpi.battery.life");
}

pub fn batteryState() ?i64 {
    return nameInt("hw.acpi.battery.state");
}

pub fn acline() ?i64 {
    return nameInt("hw.acpi.acline");
}

// ─── memory page counters (vm.stats.vm.*, named) ───────────────────────
pub fn physmem() ?i64 {
    return nameInt("hw.physmem");
}

pub fn freePages() ?i64 {
    return nameInt("vm.stats.vm.v_free_count");
}

pub fn inactivePages() ?i64 {
    return nameInt("vm.stats.vm.v_inactive_count");
}

pub fn pageSize() ?i64 {
    return nameInt("hw.pagesize");
}

// ─── swap counters (vm.swap_*: bytes on both) ──────────────────────────
pub fn swapTotal() ?i64 {
    return nameInt("vm.swap_total");
}

pub fn swapReserved() ?i64 {
    return nameInt("vm.swap_reserved");
}

// ─── cpu bits ──────────────────────────────────────────────────────────
pub fn cpuModel(buf: []u8) ?[]const u8 {
    return nameStr("hw.model", buf);
}

pub fn ncpu() ?i64 {
    return nameInt("hw.ncpu");
}

pub fn cpuFreqMhz() ?i64 {
    return nameInt("dev.cpu.0.freq");
}

/// first core's temperature; dev.cpu.0.temperature answers an i32 in tenths
/// of kelvin on acpi builds, a "37.0C" string on others — both spellings.
pub fn cpuTemperature(out: []u8) ?[]const u8 {
    var raw: [64]u8 = undefined;
    var written: usize = raw.len;
    if (sysctlbyname("dev.cpu.0.temperature", &raw, &written, null, 0) != 0) return null;
    if (written == 4) {
        const tenths: i32 = @bitCast(std.mem.readInt(u32, raw[0..4], .little));
        const celsius: i64 = @divTrunc(@as(i64, tenths) - 2732 + 5, 10);
        if (celsius < -40 or celsius > 250) return null;
        return std.mem.print(out, "{d}°C", .{celsius}) catch null;
    }
    // "37.0C" — take the numeric run
    const s = raw[0..@min(written, raw.len)];
    var start: usize = 0;
    while (start < s.len and (s[start] < '0' or s[start] > '9')) start += 1;
    var endp = start;
    while (endp < s.len and ((s[endp] >= '0' and s[endp] <= '9') or s[endp] == '.')) endp += 1;
    if (start >= endp) return null;
    const value = std.fmt.parseFloat(f64, s[start..endp]) catch return null;
    return std.mem.print(out, "{d:.0}°C", .{value}) catch null;
}

// ─── uptime ────────────────────────────────────────────────────────────
pub const Timespec = extern struct { sec: i64, nsec: i64 };

/// kern.boottime's tv_sec minus now, in whole seconds.
pub fn uptimeSeconds() ?u64 {
    var raw: [16]u8 = undefined;
    const bytes = nameBytes("kern.boottime", &raw) orelse return null;
    if (bytes.len < 8) return null;
    const boot_sec = std.mem.readInt(i64, raw[0..8], .little);
    if (boot_sec <= 0) return null;

    var now: Timespec = undefined;
    if (clock_gettime(0, &now) != 0 or now.sec <= boot_sec) return null; // CLOCK_REALTIME
    return @intCast(now.sec - boot_sec);
}

// ─── statvfs (sys/statvfs.h — freebsd's own field order: counts first,
// the longs behind) ─────────────────────────────────────────────────────
pub const Statvfs = extern struct {
    f_bavail: u64,
    f_bfree: u64,
    f_blocks: u64,
    f_favail: u64,
    f_ffree: u64,
    f_files: u64,
    f_bsize: u64,
    f_flag: u64,
    f_frsize: u64,
    f_fsid: u64,
    f_namemax: u64,
};

var path_buf: [128:0]u8 = undefined;

pub fn statvfsOf(path: []const u8) ?Statvfs {
    const path_c = std.mem.printSentinel(&path_buf, "{s}", .{path}, 0) catch return null;
    var buf: Statvfs = undefined;
    if (statvfs(path_c, &buf) != 0) return null;
    return buf;
}

// the kernel's own f64 triple in one libc call.
pub fn loadavg(out: *[3]f64) bool {
    return getloadavg(out, 3) == 3;
}

// ─── ifaddrs (ifaddrs.h) — interfaces for the vpn module ───────────────
pub const Ifaddrs = extern struct {
    ifa_next: ?*Ifaddrs,
    ifa_name: ?[*:0]u8,
    ifa_flags: u32,
    ifa_addr: ?*anyopaque,
    ifa_netmask: ?*anyopaque,
    ifa_dstaddr: ?*anyopaque,
    ifa_data: ?*anyopaque,
};

pub fn tunnelIface(buf: []u8) ?[]const u8 {
    var ifs: ?*Ifaddrs = null;
    if (getifaddrs(&ifs) != 0 or ifs == null) return null;
    defer freeifaddrs(ifs);

    var cur: ?*Ifaddrs = ifs;
    while (cur) |ifa| : (cur = ifa.ifa_next) {
        const name = ifa.ifa_name orelse continue;
        const n = std.mem.span(name);
        const is_tunnel =
            std.mem.startsWith(u8, n, "tun") or
            std.mem.startsWith(u8, n, "wg") or
            std.mem.startsWith(u8, n, "tap") or
            std.mem.startsWith(u8, n, "ppp");
        if (!is_tunnel) continue;
        if (n.len >= buf.len) continue;
        @memcpy(buf[0..n.len], n);
        return buf[0..n.len];
    }
    return null;
}

// ─── misc ──────────────────────────────────────────────────────────────
// close through libc for fds std.posix opened (this fork's std.posix
// has no close; the freebsd target links libc's own).
pub fn closeFd(fd: i32) void {
    _ = close(fd);
}
