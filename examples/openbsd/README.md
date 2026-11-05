# the openbsd example

divifetch-zig cross-compiles to x86_64-openbsd from a linux host: the
build (`build.conf :flags`) names that target and zig's libc paths file
(libc.txt) pointing at the sysroot in ~. the base modules gain their
openbsd answers without config changes — each module branches
comptime on the target OS the way upstream V's `$if openbsd` did, one
binary per OS target from one module tree.

what answers what on openbsd (modules/zig/openbsd.zig carries the ABI
transcribed from the sysroot's headers):

memory/swap: hw.physmem + vm.uvmexp page counters
mount: libc's statvfs(3)
uptime: kern.boottime + clock_gettime(2)
loadavg: getloadavg(3)
cpu: hw.model + hw.ncpuonline + hw.cpuspeed
battery: the apm device (APM_IOC_GETPOWER)
host: hw.product with hw.vendor backing it up
os: "OpenBSD <release>" from uname
shell/terminal: the /proc walk rides kern.proc.pid,<pid> kinfo structs
pid1: pid 1's p_comm from the same kinfo read
vpn: libc getifaddrs(3) for tun*/wg*/tap*/ppp
packages: an `openbsd` backend counting /var/db/pkg
mount, locale, user, hostname, kernel: shown in this config

boot, temp, theme, wm, displays, gpu stay linux-shaped for now: they
answer "?" on openbsd rather than guess.

then, from this dir:

```
v run generator -S -B -s config.lip
v run build.vsh build
file target/divifetch-openbsd   # for OpenBSD
```

the binary needs an openbsd system to run (the project's qemu VM in
~/vm/openbsd works: push it over http://10.0.2.2 from the host and run
it as root).
