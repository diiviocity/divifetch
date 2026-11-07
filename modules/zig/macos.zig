// macos.zig: the OS's own yard for the module variants. only the
// comptime-macos branches reach this file — a linux build never parses
// it. macOS has no stable syscall ABI (the kernel's numbers belong to
// libSystem, not to programs), so everything here rides libSystem's own
// exports: zig links the libSystem.tbd stub it ships, no SDK needed,
// and the binary loads /usr/lib/libSystem.B.dylib like every native
// one does.
//
// every ABI fact is transcribed from the darwin headers zig bundles
// (lib/libc/include/any-darwin-any) and was static-asserted against
// them for both x86_64 and arm64 — a kernel that changed a layout
// answers "?" rather than lying about it.
const std = @import("std");
const builtin = @import("builtin");

// ─── libSystem ─────────────────────────────────────────────────────────
extern "c" fn sysctl(name: [*]const c_int, namelen: c_uint, oldp: ?*anyopaque, oldlenp: ?*usize, newp: ?*const anyopaque, newlen: usize) c_int;
extern "c" fn sysctlbyname(name: [*:0]const u8, oldp: ?*anyopaque, oldlenp: ?*usize, newp: ?*const anyopaque, newlen: usize) c_int;
extern "c" fn clock_gettime(clk_id: c_int, tp: *Timespec) c_int;
extern "c" fn getloadavg(avg: [*]f64, nelem: c_int) c_int;
extern "c" fn getifaddrs(ifs: *?*Ifaddrs) c_int;
extern "c" fn freeifaddrs(ifs: ?*Ifaddrs) void;
extern "c" fn uname(buf: *Utsname) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn proc_listallpids(buf: ?*anyopaque, bufsize: c_int) c_int;
extern "c" fn proc_name(pid: c_int, buf: [*]u8, bufsize: u32) c_int;
extern "c" fn mach_host_self() c_uint;
extern "c" fn host_page_size(host: c_uint, out: *usize) c_int;
extern "c" fn host_statistics64(host: c_uint, flavor: c_int, info: *anyopaque, count: *c_uint) c_int;
extern "c" fn dlopen(path: [*:0]const u8, mode: c_int) ?*anyopaque;
extern "c" fn dlsym(handle: ?*anyopaque, symbol: [*:0]const u8) ?*anyopaque;

// sys/mount.h: statfs is __DARWIN_INODE64 — x86_64 keeps the 32-bit-inode
// symbol under the bare name and exports the 64-bit layout below as
// statfs$INODE64; arm64 only ever had the 64-bit one, bare (std.c's own
// fstat/stat switch the same way).
extern "c" fn @"statfs$INODE64"(path: [*:0]const u8, buf: *Statfs) c_int;
extern "c" fn statfs(path: [*:0]const u8, buf: *Statfs) c_int;
const statfs_c = switch (builtin.cpu.arch) {
    .x86_64 => @"statfs$INODE64",
    else => statfs,
};

// ─── sysctl ────────────────────────────────────────────────────────────
const CTL_KERN: c_int = 1;
const KERN_PROC: c_int = 14;
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

/// one integer out of a named node; oldlenp tells the real width
/// (hw.memsize and hw.cpufrequency are 8 bytes, hw.ncpu is 4).
pub fn nameInt(name: [*:0]const u8) ?i64 {
    var buf: [8]u8 = undefined;
    const bytes = nameBytes(name, &buf) orelse return null;
    return switch (bytes.len) {
        4 => std.mem.readInt(i32, buf[0..4], .little),
        8 => std.mem.readInt(i64, &buf, .little),
        else => null,
    };
}

/// a named sysctl string (hw.model, kern.osproductversion, ...), NUL-trimmed.
pub fn nameStr(name: [*:0]const u8, buf: []u8) ?[]const u8 {
    const bytes = nameBytes(name, buf) orelse return null;
    const end = std.mem.findScalar(u8, bytes, 0) orelse bytes.len;
    if (end == 0) return null;
    return bytes[0..end];
}

// ─── uname (sys/utsname.h: _SYS_NAMELEN 256, five fields) ──────────────
pub const Utsname = extern struct {
    sysname: [256]u8,
    nodename: [256]u8,
    release: [256]u8,
    version: [256]u8,
    machine: [256]u8,
};

var uts_buf: Utsname = undefined;

/// one uname field, NUL-trimmed. `which` is one of release/nodename.
pub fn unameField(which: enum { release, nodename }, out: []u8) ?[]const u8 {
    if (uname(&uts_buf) != 0) return null;
    const field: []const u8 = switch (which) {
        .release => &uts_buf.release,
        .nodename => &uts_buf.nodename,
    };
    const end = std.mem.findScalar(u8, field, 0) orelse field.len;
    if (end == 0 or end >= out.len) return null;
    @memcpy(out[0..end], field[0..end]);
    return out[0..end];
}

// ─── os release ────────────────────────────────────────────────────────
/// kern.osproductversion (10.13.4+): "15.1", the version the About
/// window shows — not the darwin release uname answers.
///
/// the kernel shims this node by the SDK version the binary records:
/// a binary claiming a pre-11 SDK (or none — some link paths write no
/// version load command) reads "10.16" on every release since Big Sur.
/// 10.16 never shipped, so that answer falls back to the major the
/// darwin release implies (uname is not shimmed): "14" off 23.6.0.
pub fn productVersion(buf: []u8) ?[]const u8 {
    const v = nameStr("kern.osproductversion", buf) orelse return null;
    if (std.mem.eql(u8, v, "10.16")) return darwinMajor(buf);
    // Tahoe answers "16.x" to binaries linked against an older SDK —
    // the 26 it really is takes the place of that 1 (fastfetch #1809).
    if (std.mem.startsWith(u8, v, "16.")) buf[0] = '2';
    return v;
}

/// the macOS major a darwin release belongs to: darwin 20..24 are
/// macOS 11..15, and from darwin 25 the year-named releases run one
/// ahead (25 is Tahoe, 26). only the major survives — a darwin minor
/// spans several point releases.
fn darwinMajor(buf: []u8) ?[]const u8 {
    var rel: [32]u8 = undefined;
    const release = unameField(.release, &rel) orelse return null;
    const dot = std.mem.findScalar(u8, release, '.') orelse release.len;
    const darwin = std.fmt.parseInt(u32, release[0..dot], 10) catch return null;
    if (darwin < 20) return null;
    const major: u32 = if (darwin >= 25) darwin + 1 else darwin - 9;
    return std.mem.print(buf, "{d}", .{major}) catch null;
}

/// the marketing name of a macOS major version — fastfetch's table
/// (os_apple.m). Apple jumped from 15 to 26 (the year-named releases);
/// 10.x names key off the minor instead.
pub fn codename(version: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, version, '.');
    const major = std.fmt.parseInt(u32, it.next() orelse return null, 10) catch return null;
    if (major == 10) {
        const minor = std.fmt.parseInt(u32, it.next() orelse return null, 10) catch return null;
        return switch (minor) {
            12 => "Sierra",
            13 => "High Sierra",
            14 => "Mojave",
            15 => "Catalina",
            16 => "Big Sur", // what Big Sur tells binaries built for 10.x
            else => null,
        };
    }
    return switch (major) {
        27 => "Golden Gate",
        26, 16 => "Tahoe",
        11 => "Big Sur",
        12 => "Monterey",
        13 => "Ventura",
        14 => "Sonoma",
        15 => "Sequoia",
        else => null,
    };
}

// ─── kinfo_proc (sys/sysctl.h + sys/proc.h, LP64): kp_proc is the 296-byte
// extern_proc, kp_eproc follows; asserted against the headers on both
// arches. the kern.proc.pid request returns exactly one, for any pid —
// ps(1)'s own route, no same-user check like proc_pidinfo's. ───────────
const kinfo_size: usize = 648;
const kinfo_ppid_off: usize = 560; // kp_eproc.e_ppid
const kinfo_comm_off: usize = 243; // kp_proc.p_comm[MAXCOMLEN+1]
const kinfo_comm_len: usize = 17;

var kinfo_buf: [kinfo_size]u8 align(8) = undefined;

/// one process' identity, the shape the /proc walk needs.
pub fn procInfo(pid: i32) ?struct { comm: []const u8, ppid: i32 } {
    const bytes = sysctlBytes(&.{ CTL_KERN, KERN_PROC, KERN_PROC_PID, pid }, &kinfo_buf) orelse return null;
    // a vanished pid answers rc 0 with zero bytes written
    if (bytes.len != kinfo_size) return null;
    const ppid = std.mem.readInt(i32, kinfo_buf[kinfo_ppid_off..][0..4], .little);
    const raw_comm = kinfo_buf[kinfo_comm_off..][0..kinfo_comm_len];
    const end = std.mem.findScalar(u8, raw_comm, 0) orelse raw_comm.len;
    if (end == 0) return null;
    return .{ .comm = raw_comm[0..end], .ppid = ppid };
}

/// every pid the caller may see, through libproc. proc_name answers the
/// same-user processes (all a window manager ever is) and fails on the rest.
var pid_buf: [8192]i32 = undefined;

pub fn allPids() []const i32 {
    const n = proc_listallpids(&pid_buf, @intCast(@sizeOf(@TypeOf(pid_buf))));
    if (n <= 0) return pid_buf[0..0];
    return pid_buf[0..@min(@as(usize, @intCast(n)), pid_buf.len)];
}

/// a process' name (p_comm's longer pbi_name sibling, up to 2*MAXCOMLEN).
pub fn procName(pid: i32, buf: []u8) ?[]const u8 {
    const n = proc_name(pid, buf.ptr, @intCast(buf.len));
    if (n <= 0) return null;
    return buf[0..@min(@as(usize, @intCast(n)), buf.len)];
}

// ─── memory (mach/vm_statistics.h) ─────────────────────────────────────
pub fn memsize() ?i64 {
    return nameInt("hw.memsize");
}

/// the vm_statistics64 counters the used figure needs, at their rev0
/// offsets (free_count 0, speculative_count 92, external_page_count 136). the struct grew (416 bytes in the bundled SDK); asking
/// with the rev0 HOST_VM_INFO64_COUNT of 38 is what every kernel since
/// 10.6 answers, and fills exactly these.
pub const VmStats = struct {
    free: u32,
    speculative: u32,
    external: u32,
    page_size: u64,
};

const HOST_VM_INFO64: c_int = 4;
const HOST_VM_INFO64_REV0_COUNT: c_uint = 38; // 152 bytes / sizeof(integer_t)

pub fn vmStats() ?VmStats {
    const host = mach_host_self();
    var raw: [152]u8 align(8) = undefined;
    var count: c_uint = HOST_VM_INFO64_REV0_COUNT;
    if (host_statistics64(host, HOST_VM_INFO64, &raw, &count) != 0) return null; // KERN_SUCCESS
    if (count < HOST_VM_INFO64_REV0_COUNT) return null;

    // vm_stat(1)'s own page unit: the kernel's page size, which on arm64
    // is 16K even when a Rosetta process' sysconf says 4K.
    var page: usize = 0;
    if (host_page_size(host, &page) != 0 or page == 0) page = 4096;

    const r = struct {
        fn u(b: *const [152]u8, off: usize) u32 {
            return std.mem.readInt(u32, b[off..][0..4], .little);
        }
    };
    return .{
        .free = r.u(&raw, 0),
        .speculative = r.u(&raw, 92),
        .external = r.u(&raw, 136),
        .page_size = page,
    };
}

// ─── swap (vm.swapusage: struct xsw_usage, 32 bytes) ───────────────────
pub const SwapUsage = struct { total: u64, used: u64 };

pub fn swapUsage() ?SwapUsage {
    var raw: [32]u8 align(8) = undefined;
    const bytes = nameBytes("vm.swapusage", &raw) orelse return null;
    if (bytes.len != 32) return null;
    return .{
        .total = std.mem.readInt(u64, raw[0..8], .little), // xsu_total
        .used = std.mem.readInt(u64, raw[16..24], .little), // xsu_used
    };
}

// ─── cpu bits ──────────────────────────────────────────────────────────
/// "Intel(R) Core(TM) i7-8700B CPU @ 3.20GHz" or "Apple M2 Pro".
pub fn cpuModel(buf: []u8) ?[]const u8 {
    return nameStr("machdep.cpu.brand_string", buf);
}

pub fn ncpu() ?i64 {
    return nameInt("hw.ncpu");
}

/// hw.cpufrequency, in Hz: Intel Macs only, Apple silicon publishes none.
pub fn cpuFreqHz() ?i64 {
    return nameInt("hw.cpufrequency");
}

/// "MacBookPro18,3", "Mac14,2", "iMacPro1,1" (the OSX-KVM default).
pub fn hwModel(buf: []u8) ?[]const u8 {
    return nameStr("hw.model", buf);
}

// ─── uptime ────────────────────────────────────────────────────────────
pub const Timespec = extern struct { sec: i64, nsec: i64 };

/// kern.boottime's tv_sec (a 16-byte timeval) minus now, in whole seconds.
pub fn uptimeSeconds() ?u64 {
    var raw: [16]u8 align(8) = undefined;
    const bytes = nameBytes("kern.boottime", &raw) orelse return null;
    if (bytes.len < 8) return null;
    const boot_sec = std.mem.readInt(i64, raw[0..8], .little);
    if (boot_sec <= 0) return null;

    var now: Timespec = undefined;
    if (clock_gettime(0, &now) != 0 or now.sec <= boot_sec) return null; // _CLOCK_REALTIME
    return @intCast(now.sec - boot_sec);
}

// the kernel's own f64 triple in one libc call.
pub fn loadavg(out: *[3]f64) bool {
    return getloadavg(out, 3) == 3;
}

// ─── statfs (sys/mount.h, the 64-bit-inode layout: 2168 bytes; only the
// leading counters are read, the names stay opaque) ───────────────────
pub const Statfs = extern struct {
    f_bsize: u32,
    f_iosize: i32,
    f_blocks: u64,
    f_bfree: u64,
    f_bavail: u64,
    f_files: u64,
    f_ffree: u64,
    f_fsid: [2]i32,
    f_owner: u32,
    f_type: u32,
    f_flags: u32,
    f_fssubtype: u32,
    f_fstypename: [16]u8,
    f_mntonname: [1024]u8,
    f_mntfromname: [1024]u8,
    f_flags_ext: u32,
    f_reserved: [7]u32,
};

comptime {
    std.debug.assert(@sizeOf(Statfs) == 2168);
}

var path_buf: [128:0]u8 = undefined;
var statfs_buf: Statfs = undefined;

pub fn statfsOf(path: []const u8) ?*const Statfs {
    const path_c = std.mem.printSentinel(&path_buf, "{s}", .{path}, 0) catch return null;
    if (statfs_c(path_c, &statfs_buf) != 0) return null;
    return &statfs_buf;
}

// ─── ifaddrs (ifaddrs.h, 56 bytes) — interfaces for the vpn module ─────
pub const Ifaddrs = extern struct {
    ifa_next: ?*Ifaddrs,
    ifa_name: ?[*:0]u8,
    ifa_flags: u32,
    ifa_addr: ?*const Sockaddr,
    ifa_netmask: ?*anyopaque,
    ifa_dstaddr: ?*anyopaque,
    ifa_data: ?*anyopaque,
};

/// the BSD sockaddr head: a length byte, then the family byte.
pub const Sockaddr = extern struct { sa_len: u8, sa_family: u8 };

const IFF_UP: u32 = 0x1;
const AF_INET: u8 = 2;

/// macOS keeps utun0..utunN up at all times (iCloud Private Relay,
/// Back to My Mac, the network extensions) with nothing but IPv6
/// link-local on them, so a tunnel name alone means nothing here: a
/// VPN is a tunnel-shaped interface that's up and carries an IPv4
/// address, which every VPN client (WireGuard, OpenVPN, IKEv2/IPsec,
/// Tailscale) assigns and the system tunnels never do.
pub fn tunnelIface(buf: []u8) ?[]const u8 {
    var ifs: ?*Ifaddrs = null;
    if (getifaddrs(&ifs) != 0 or ifs == null) return null;
    defer freeifaddrs(ifs);

    var cur: ?*Ifaddrs = ifs;
    while (cur) |ifa| : (cur = ifa.ifa_next) {
        const name = ifa.ifa_name orelse continue;
        const addr = ifa.ifa_addr orelse continue;
        if (ifa.ifa_flags & IFF_UP == 0 or addr.sa_family != AF_INET) continue;
        const n = std.mem.span(name);
        const is_tunnel =
            std.mem.startsWith(u8, n, "utun") or
            std.mem.startsWith(u8, n, "ipsec") or
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

// ─── battery: IOKit's power-source API, reached through dlopen ─────────
// zig ships no framework stubs, so the binary can't link IOKit — but
// every macOS has it in the dyld shared cache, and dlopen/dlsym are
// libSystem's. the same keys pmset(1) prints, without spawning it.
pub const Battery = struct { percent: u8, status: []const u8 };

const CFRef = ?*const anyopaque;
const kCFStringEncodingUTF8: u32 = 0x08000100;
const kCFNumberSInt32Type: c_int = 3;
const RTLD_LAZY: c_int = 0x1;

const Fns = struct {
    copy_info: *const fn () callconv(.c) CFRef,
    copy_list: *const fn (CFRef) callconv(.c) CFRef,
    description: *const fn (CFRef, CFRef) callconv(.c) CFRef,
    array_count: *const fn (CFRef) callconv(.c) isize,
    array_at: *const fn (CFRef, isize) callconv(.c) CFRef,
    dict_get: *const fn (CFRef, CFRef) callconv(.c) CFRef,
    string_create: *const fn (CFRef, [*:0]const u8, u32) callconv(.c) CFRef,
    number_get: *const fn (CFRef, c_int, *anyopaque) callconv(.c) u8,
    boolean_get: *const fn (CFRef) callconv(.c) u8,
    equal: *const fn (CFRef, CFRef) callconv(.c) u8,
    release: *const fn (CFRef) callconv(.c) void,
};

fn sym(comptime T: type, handle: ?*anyopaque, name: [*:0]const u8) ?T {
    const p = dlsym(handle, name) orelse return null;
    return @ptrCast(@alignCast(p));
}

fn loadFns() ?Fns {
    const iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) orelse return null;
    const cf = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_LAZY) orelse return null;
    return .{
        .copy_info = sym(@FieldType(Fns, "copy_info"), iokit, "IOPSCopyPowerSourcesInfo") orelse return null,
        .copy_list = sym(@FieldType(Fns, "copy_list"), iokit, "IOPSCopyPowerSourcesList") orelse return null,
        .description = sym(@FieldType(Fns, "description"), iokit, "IOPSGetPowerSourceDescription") orelse return null,
        .array_count = sym(@FieldType(Fns, "array_count"), cf, "CFArrayGetCount") orelse return null,
        .array_at = sym(@FieldType(Fns, "array_at"), cf, "CFArrayGetValueAtIndex") orelse return null,
        .dict_get = sym(@FieldType(Fns, "dict_get"), cf, "CFDictionaryGetValue") orelse return null,
        .string_create = sym(@FieldType(Fns, "string_create"), cf, "CFStringCreateWithCString") orelse return null,
        .number_get = sym(@FieldType(Fns, "number_get"), cf, "CFNumberGetValue") orelse return null,
        .boolean_get = sym(@FieldType(Fns, "boolean_get"), cf, "CFBooleanGetValue") orelse return null,
        .equal = sym(@FieldType(Fns, "equal"), cf, "CFEqual") orelse return null,
        .release = sym(@FieldType(Fns, "release"), cf, "CFRelease") orelse return null,
    };
}

/// the first internal battery's charge and the linux status words
/// (Charging / Discharging / Full / Not charging). null: no battery,
/// or IOKit isn't answering.
pub fn battery() ?Battery {
    const f = loadFns() orelse return null;
    const info = f.copy_info() orelse return null;
    defer f.release(info);
    const list = f.copy_list(info) orelse return null;
    defer f.release(list);

    const key = struct {
        fn make(fns: Fns, s: [*:0]const u8) CFRef {
            return fns.string_create(null, s, kCFStringEncodingUTF8);
        }
    };
    const k_type = key.make(f, "Type") orelse return null;
    defer f.release(k_type);
    const k_internal = key.make(f, "InternalBattery") orelse return null;
    defer f.release(k_internal);
    const k_cur = key.make(f, "Current Capacity") orelse return null;
    defer f.release(k_cur);
    const k_max = key.make(f, "Max Capacity") orelse return null;
    defer f.release(k_max);
    const k_charging = key.make(f, "Is Charging") orelse return null;
    defer f.release(k_charging);
    const k_charged = key.make(f, "Is Charged") orelse return null;
    defer f.release(k_charged);
    const k_state = key.make(f, "Power Source State") orelse return null;
    defer f.release(k_state);
    const k_ac = key.make(f, "AC Power") orelse return null;
    defer f.release(k_ac);

    const n = f.array_count(list);
    var i: isize = 0;
    while (i < n) : (i += 1) {
        const ps = f.array_at(list, i) orelse continue;
        const desc = f.description(info, ps) orelse continue; // borrowed: no release
        const kind = f.dict_get(desc, k_type) orelse continue;
        if (f.equal(kind, k_internal) == 0) continue;

        var cur: i32 = 0;
        var max: i32 = 100;
        const cur_ref = f.dict_get(desc, k_cur) orelse continue;
        if (f.number_get(cur_ref, kCFNumberSInt32Type, &cur) == 0) continue;
        if (f.dict_get(desc, k_max)) |max_ref| {
            if (f.number_get(max_ref, kCFNumberSInt32Type, &max) == 0 or max <= 0) max = 100;
        }
        const pct_raw = @divTrunc(@as(i64, @max(cur, 0)) * 100 + @divTrunc(max, 2), max);
        const percent: u8 = @intCast(@min(pct_raw, 100));

        const flag = struct {
            fn get(fns: Fns, d: CFRef, k: CFRef) bool {
                const v = fns.dict_get(d, k) orelse return false;
                return fns.boolean_get(v) != 0;
            }
        };
        const on_ac = if (f.dict_get(desc, k_state)) |s| f.equal(s, k_ac) != 0 else false;
        const status: []const u8 = if (flag.get(f, desc, k_charging))
            "Charging"
        else if (!on_ac)
            "Discharging"
        else if (flag.get(f, desc, k_charged) or percent >= 100)
            "Full"
        else
            "Not charging"; // optimized charging holds at 80% on AC
        return .{ .percent = percent, .status = status };
    }
    return null;
}

// ─── misc ──────────────────────────────────────────────────────────────
// close through libSystem for fds std.posix opened (this fork's
// std.posix has no close).
pub fn closeFd(fd: i32) void {
    _ = close(fd);
}
