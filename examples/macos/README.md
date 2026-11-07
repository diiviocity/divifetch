# the macos example

divifetch-zig cross-compiles to macOS from a linux host with no
sysroot at all: zig ships the darwin libc headers and a libSystem.tbd
stub, so `build.conf :flags` only names the target. the binary links
/usr/lib/libSystem.B.dylib like every native one (macOS has no static
libc, and its syscall numbers belong to libSystem, not to programs —
so every module answers through libSystem's exports). the base modules
gain their macOS answers without config changes, each branching
comptime on the target OS: one binary per OS target, one module tree.

what answers what on macOS (modules/zig/macos.zig carries the ABI,
static-asserted against the bundled darwin headers on x86_64 and arm64):

distro: "macOS <codename> <version>" from kern.osproductversion
    (fastfetch's codename table). the kernel answers that node by the
    SDK version the binary records: Tahoe's "16.x" reads 26, and the
    "10.16" a pre-11 (or unrecorded) SDK gets falls back to the major
    the darwin release implies — "macOS Sonoma 14" off 23.6.0
host: hw.model ("MacBookPro18,3", "Mac14,2")
kernel/hostname: uname(3) (the darwin release, "24.1.0")
memory: hw.memsize + host_statistics64, fastfetch's arithmetic —
    used = total - (free - speculative + file-backed) pages
swap: vm.swapusage ('?' until dynamic_pager has made a swapfile)
mount: statfs(2), the 64-bit-inode layout (statfs$INODE64 on x86_64).
    APFS answers its counters for the whole container, so "/" (the
    sealed system volume) reports the disk's fill
uptime: kern.boottime + clock_gettime(2)
loadavg: getloadavg(3)
cpu: machdep.cpu.brand_string + hw.ncpu + hw.cpufrequency (Intel
    only: Apple silicon publishes no frequency)
battery: IOKit's power sources (pmset(1)'s keys), reached through
    dlopen — zig can't link frameworks without an SDK, but every Mac
    has IOKit in its dyld shared cache
boot: comptime per arch — iBoot on Apple silicon, UEFI on Intel
shell/terminal: the /proc walk rides kern.proc.pid kinfo_proc
    (p_comm at 243, e_ppid at 560, 648 bytes); Terminal.app and
    iTerm2 report their version through TERM_PROGRAM_VERSION
pid1: launchd, from the same kinfo read
wm: "Quartz Compositor", with a tiling manager beside it when one
    runs — "Quartz Compositor (yabai)" — libproc's pid list scanned
    for fastfetch's set (rectangle, yabai, aerospace, amethyst, glazewm)
vpn: getifaddrs(3); macOS keeps utun0..N up at all times with only
    IPv6 link-local on them, so a tunnel counts once it carries IPv4
packages: `brew` (Cellar), `brew-cask` (Caskroom) under /opt/homebrew
    or /usr/local, and `port` (MacPorts' software dir)

temp, theme, monitor and gpu stay linux-shaped: they answer "?" on
macOS rather than guess (temperature needs the SMC or the private HID
sensor API; displays and GPUs need IOKit's registry or CoreGraphics).

then, from this dir:

```
v run generator -S -B -s config.lip
v run build.vsh build
file target/divifetch-macos   # Mach-O 64-bit arm64
```

build.conf targets Apple silicon from macOS 11 up; `-target
x86_64-macos.10.13` builds for Intel Macs (and the OSX-KVM guest in
~/vm/macos). keep the `.N` floor: zig 0.17 stamps a bare `-macos`
target with a 15.0 minimum, which dyld refuses on anything older. on a
Mac itself, drop the `-target` and build natively.

## the V backend

the V modules carry the same macOS reads (sysctl, statfs, kinfo_proc,
host_statistics64, getifaddrs, libproc) — everything above except
battery, which answers "?" there. V's C backend is headerless, so the
modules read darwin structs as raw bytes at their header offsets rather
than declaring them (a V-declared `struct C.statfs` would be sized to
the linux layout and overrun). the default V compile is freestanding,
which macOS can't be: an all-V config builds on a Mac with a hosted
conf, `:flags "-prod"`.
