// openbsd.zig: the OS's own yard for the module variants. only the
// comptime-openbsd branches reach this file — a linux build never parses
// it and never links anything here, and libc carries the externs on an
// openbsd target (the one place the project's no-libc rule doesn't hold:
// openbsd IS a libc system).
//
// every ABI fact is transcribed from the sysroot headers the build links
// against — usr/include/{sys/machine/uvm/...} — so a kernel that changed
// a layout answers "?" rather than lying about it.
const std = @import("std");

// ─── libc ──────────────────────────────────────────────────────────────
extern "c" fn sysctl(name: [*]const c_uint, namelen: c_uint, oldp: ?*anyopaque, oldlenp: ?*usize, newp: ?*const anyopaque, newlen: usize) c_int;
extern "c" fn clock_gettime(clk_id: c_int, tp: *Timespec) c_int;
extern "c" fn getloadavg(avg: [*]f64, nelem: c_int) c_int;
extern "c" fn ioctl(fd: c_int, request: c_ulong, argp: ?*anyopaque) c_int;
extern "c" fn open(path: [*:0]const u8, flags: c_int, mode: c_uint) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn statvfs(path: [*:0]const u8, buf: *Statvfs) c_int;
extern "c" fn uname(uts: *Utsname) c_int;
extern "c" fn getifaddrs(ifs: *?*Ifaddrs) c_int;
extern "c" fn freeifaddrs(ifs: ?*Ifaddrs) void;

// ─── sysctl MIB spellings (sys/sysctl.h, uvm/uvmexp.h) ─────────────────
pub const CTL_KERN: u32 = 1;
pub const CTL_VM: u32 = 2;
pub const CTL_HW: u32 = 6;

const KERN_BOOTTIME: u32 = 21; // struct timeval
const KERN_PROC: u32 = 66; // struct kinfo_proc entries
const KERN_PROC_PID: u32 = 1; // by process id
pub const VM_UVMEXP: u32 = 4; // struct uvmexp
pub const HW_MODEL: u32 = 2;
pub const HW_PHYSMEM: u32 = 5;
pub const HW_VENDOR: u32 = 14;
pub const HW_PRODUCT: u32 = 15;
pub const HW_CPUSPEED: u32 = 12;
pub const HW_NCPUONLINE: u32 = 25;

// raw byte read; returns buf[0..written], none when the kernel declines.
pub fn sysctlBytes(name: []const u32, buf: []u8) ?[]const u8 {
    var written: usize = buf.len;
    const rc = sysctl(name.ptr, @intCast(name.len), buf.ptr, &written, null, 0);
    if (rc != 0) return null;
    if (written > buf.len) return null;
    return buf[0..written];
}

/// NUL-terminated sysctl string, trimmed of its sentinel.
pub fn sysctlStr(name: []const u32, buf: []u8) ?[]const u8 {
    const bytes = sysctlBytes(name, buf) orelse return null;
    const end = std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len;
    if (end == 0) return null;
    return bytes[0..end];
}

/// One integer out of the sysctl tree; oldlenp tells the real width.
pub fn sysctlInt(name: []const u32) ?i64 {
    var buf: [8]u8 = undefined;
    const bytes = sysctlBytes(name, &buf) orelse return null;
    return switch (bytes.len) {
        4 => @as(i32, @bitCast(@as(u32, @truncate(std.mem.readInt(u64, &buf, .little))))),
        8 => std.mem.readInt(i64, &buf, .little),
        else => null,
    };
}

const HW_PHYSMEM64: u32 = 19; // int64; hw.physmem's int read clips >2 GiB

// ─── uname (sys/utsname.h: SYS_NMLN 256, five NUL-padded fields) ───────
pub const Utsname = extern struct {
    sysname: [256]u8,
    nodename: [256]u8,
    release: [256]u8,
    version: [256]u8,
    machine: [256]u8,
};

var uts_buf: Utsname = undefined;

/// one uname field, NUL-trimmed. `which` is one of release/node/name.
pub fn unameField(which: enum { release, nodename }, out: []u8) ?[]const u8 {
    if (uname(&uts_buf) != 0) return null;
    const field: []const u8 = switch (which) {
        .release => &uts_buf.release,
        .nodename => &uts_buf.nodename,
    };
    const end = std.mem.indexOfScalar(u8, field, 0) orelse field.len;
    if (end == 0 or end >= out.len) return null;
    @memcpy(out[0..end], field[0..end]);
    return out[0..end];
}

/// close through libc for fds the std.posix tree opened (this fork's
/// std.posix has no close; the openbsd target links libc's own).
pub fn closeFd(fd: i32) void {
    _ = close(fd);
}

// ─── uvmexp (uvm/uvmexp.h, in order, every field an i32) ───────────────
pub const Uvmexp = extern struct {
    pagesize: i32,
    pagemask: i32,
    pageshift: i32,

    npages: i32,
    free: i32,
    active: i32,
    inactive: i32,
    paging: i32,
    wired: i32,

    zeropages: i32,
    reserve_pagedaemon: i32,
    reserve_kernel: i32,
    percpucaches: i32,
    vnodepages: i32,
    vtextpages: i32,

    freemin: i32,
    freetarg: i32,
    inactarg: i32,
    wiredmax: i32,
    anonmin: i32,
    vtextmin: i32,
    vnodemin: i32,
    anonminpct: i32,
    vtextminpct: i32,
    vnodeminpct: i32,

    // swap
    nswapdev: i32,
    swpages: i32,
    swpginuse: i32,
    swpgonly: i32,
    nswget: i32,
    nanon: i32,
    unused05: i32,
    unused06: i32,

    // stat counters
    faults: i32,
    traps: i32,
    intrs: i32,
    swtch: i32,
    softs: i32,
    syscalls: i32,
    pageins: i32,
    pcphit: i32,
    pcpmiss: i32,
    pgswapin: i32,
    pgswapout: i32,
    forks: i32,
    forks_ppwait: i32,
    forks_sharevm: i32,
    pga_zerohit: i32,
    pga_zeromiss: i32,
    unused09: i32,

    // fault subcounters
    fltnoram: i32,
    fltnoanon: i32,
    fltnoamap: i32,
    fltpgwait: i32,
    fltpgrele: i32,
    fltrelck: i32,
    fltnorelck: i32,
    fltanget: i32,
    fltanretry: i32,
    fltamcopy: i32,
    fltnamap: i32,
    fltnomap: i32,
    fltlget: i32,
    fltget: i32,
    flt_anon: i32,
    flt_acow: i32,
    flt_obj: i32,
    flt_prcopy: i32,
    flt_przero: i32,
    fltup: i32,
    fltnoup: i32,

    // daemon counters
    pdwoke: i32,
    pdrevs: i32,
    pdswout: i32,
    pdfreed: i32,
    pdscans: i32,
    pdanscan: i32,
    pdobscan: i32,
    pdreact: i32,
    pdbusy: i32,
    pdpageouts: i32,
    pdpending: i32,
    pddeact: i32,
    swpskip: i32,

    fpswtch: i32,
    kmapent: i32,
};

var uvmexp_buf: [@sizeOf(Uvmexp)]u8 align(4) = undefined;

pub fn uvm() ?*const Uvmexp {
    const bytes = sysctlBytes(&.{ CTL_VM, VM_UVMEXP }, &uvmexp_buf) orelse return null;
    if (bytes.len != @sizeOf(Uvmexp)) return null;
    return @alignCast(@ptrCast(uvmexp_buf[0..bytes.len]));
}

/// what the whole machine was given: hw.physmem aliases the 64-bit node
/// on 8.0 (sysctl(2)'s HW_PHYSMEM64 spelling); the int-width old node
/// reads first for releases that still carry it.
pub fn physmem() ?i64 {
    if (sysctlInt(&.{ CTL_HW, HW_PHYSMEM64 })) |w| return w;
    return sysctlInt(&.{ CTL_HW, HW_PHYSMEM });
}

pub fn hwStr(name: u32, buf: []u8) ?[]const u8 {
    return sysctlStr(&.{ CTL_HW, name }, buf);
}

/// one hw.<name> integer (cpuspeed, ncpuonline, ...).
pub fn hwInt(name: u32) ?i64 {
    return sysctlInt(&.{ CTL_HW, name });
}

// ─── kinfo_proc (sys/sysctl.h; sizes: KI_NGROUPS 16, comm 24,
// wmesg 8, login 32, emul 8) ────────────────────────────────────────────
pub const KinfoProc = extern struct {
    p_forw: u64,
    p_back: u64,
    p_paddr: u64,
    p_addr: u64,
    p_fd: u64,
    p_stats: u64,
    p_limit: u64,
    p_vmspace: u64,
    p_sigacts: u64,
    p_sess: u64,
    p_tsess: u64,
    p_ru: u64,
    p_eflag: i32,
    p_exitsig: i32,
    p_flag: i32,
    p_pid: i32,
    p_ppid: i32,
    p_sid: i32,
    p__pgid: i32,
    p_tpgid: i32,
    p_uid: u32,
    p_ruid: u32,
    p_gid: u32,
    p_rgid: u32,
    p_groups: [16]u32,
    p_ngroups: i16,
    p_jobc: i16,
    p_tdev: u32,
    p_estcpu: u32,
    p_rtime_sec: u32,
    p_rtime_usec: u32,
    p_cpticks: i32,
    p_pctcpu: u32,
    p_swtime: u32,
    p_slptime: u32,
    p_schedflags: i32,
    p_uticks: u64,
    p_sticks: u64,
    p_iticks: u64,
    p_tracep: u64,
    p_traceflag: i32,
    p_holdcnt: i32,
    p_siglist: i32,
    p_sigmask: u32,
    p_sigignore: u32,
    p_sigcatch: u32,
    p_stat: i8,
    p_priority: u8,
    p_usrpri: u8,
    p_nice: u8,
    p_xstat: u16,
    p_spare: u16,
    p_comm: [24]u8,
    p_wmesg: [8]u8,
    p_wchan: u64,
    p_login: [32]u8,
    p_vm_rssize: i32,
    p_vm_tsize: i32,
    p_vm_dsize: i32,
    p_vm_ssize: i32,
    p_uvalid: i64,
    p_ustart_sec: u64,
    p_ustart_usec: u32,
    p_uutime_sec: u32,
    p_uutime_usec: u32,
    p_ustime_sec: u32,
    p_ustime_usec: u32,
    p_uru_maxrss: u64,
    p_uru_ixrss: u64,
    p_uru_idrss: u64,
    p_uru_isrss: u64,
    p_uru_minflt: u64,
    p_uru_majflt: u64,
    p_uru_nswap: u64,
    p_uru_inblock: u64,
    p_uru_oublock: u64,
    p_uru_msgsnd: u64,
    p_uru_msgrcv: u64,
    p_uru_nsignals: u64,
    p_uru_nvcsw: u64,
    p_uru_nivcsw: u64,
    p_uctime_sec: u32,
    p_uctime_usec: u32,
    p_psflags: u32,
    p_acflag: u32,
    p_svuid: u32,
    p_svgid: u32,
    p_emul: [8]u8,
    p_rlim_rss_cur: u64,
    p_cpuid: u64,
    p_vm_map_size: u64,
    p_tid: i32,
    p_rtableid: u32,
    p_pledge: u64,
    p_name: [24]u8,
};

var kinfo_buf: [@sizeOf(KinfoProc)]u8 align(8) = undefined;

/// one process' identity, the shape the /proc walk needs.
// the kern.proc request is six-level: the selection, its argument,
// then the struct size and the count the kernel should fill — the
// libkvm protocol sysctl(2) documents; anything shorter EINVALs.
pub fn procInfo(pid: i32) ?struct { comm: []const u8, ppid: i32 } {
    const bytes = sysctlBytes(&.{ CTL_KERN, KERN_PROC, KERN_PROC_PID, @intCast(pid), @sizeOf(KinfoProc), 1 }, &kinfo_buf) orelse return null;
    if (bytes.len != @sizeOf(KinfoProc)) return null;
    const proc: *const KinfoProc = @alignCast(@ptrCast(kinfo_buf[0..bytes.len]));

    const end = std.mem.indexOfScalar(u8, &proc.p_comm, 0) orelse proc.p_comm.len;
    if (end == 0) return null;
    return .{ .comm = proc.p_comm[0..end], .ppid = proc.p_ppid };
}

// ─── uptime ────────────────────────────────────────────────────────────
pub const Timespec = extern struct { sec: i64, nsec: i64 };

/// kern.boottime's tv_sec minus now, in whole seconds.
pub fn uptimeSeconds() ?u64 {
    var raw: [16]u8 = undefined;
    const bytes = sysctlBytes(&.{ CTL_KERN, KERN_BOOTTIME }, &raw) orelse return null;
    if (bytes.len < 8) return null;
    const boot_sec = std.mem.readInt(i64, raw[0..8], .little);
    if (boot_sec <= 0) return null;

    var now: Timespec = undefined;
    if (clock_gettime(0, &now) != 0 or now.sec <= boot_sec) return null; // CLOCK_REALTIME
    return @intCast(now.sec - boot_sec);
}

// ─── statvfs (sys/statvfs.h) — f_bsize/f_frsize u64, counts u64 ────────
pub const Statvfs = extern struct {
    f_bsize: u64,
    f_frsize: u64,
    f_blocks: u64,
    f_bfree: u64,
    f_bavail: u64,
    f_files: u64,
    f_ffree: u64,
    f_favail: u64,
    f_fsid: u64,
    f_flag: u64,
    f_namemax: u64,
};

var path_buf: [128:0]u8 = undefined;

pub fn statvfsOf(path: []const u8) ?Statvfs {
    const path_c = std.mem.printSentinel(&path_buf, "{s}", .{path}, 0) catch return null;
    var buf: Statvfs = undefined;
    if (statvfs(path_c, &buf) != 0) return null;
    return buf;
}

// ─── battery via /dev/apm (machine/apmvar.h) ───────────────────────────
pub const APM_AC_OFF: u8 = 0x00;
pub const APM_AC_ON: u8 = 0x01;
pub const APM_AC_BACKUP: u8 = 0x02;
pub const APM_AC_UNKNOWN: u8 = 0xff;
pub const APM_BATT_HIGH: u8 = 0x00;
pub const APM_BATT_LOW: u8 = 0x01;
pub const APM_BATT_CRITICAL: u8 = 0x02;
pub const APM_BATT_CHARGING: u8 = 0x03;
pub const APM_BATT_UNKNOWN: u8 = 0xff;
pub const APM_BATT_LIFE_UNKNOWN: u8 = 0xff; // apmvar.h's battery_life sentinel

// APM_IOC_GETPOWER = _IOR('A', 3, struct apm_power_info):
//   IOC_OUT(0x40000000) | (sizeof(io)=(32)&0x1fff << 16) | 'A'(0x41)<<8 | 3
const APM_IOC_GETPOWER: c_ulong = 0x40000000 | (32 << 16) | (0x41 << 8) | 3;

pub const ApmPowerInfo = extern struct {
    battery_state: u8,
    ac_state: u8,
    battery_life: u8, // percent; 0xff = unknown
    spare1: u8,
    minutes_left: u32,
    spare2: [6]u32,
};

var path_sentinel: [16:0]u8 = @splat(0);

pub fn apmInfo() ?ApmPowerInfo {
    _ = std.mem.print(&path_sentinel, "{s}", .{"/dev/apm"}) catch return null;
    const fd = open(&path_sentinel, 0, 0); // O_RDONLY
    if (fd < 0) return null;
    defer _ = close(fd);

    var info: ApmPowerInfo = undefined;
    if (ioctl(fd, APM_IOC_GETPOWER, @ptrCast(&info)) != 0) return null;
    return info;
}

// kernel's own f64 triple in one libc call.
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
