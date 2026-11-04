# the freebsd example

divifetch-zig cross-compiles to x86_64-freebsd from a linux host: the
build (`build.conf :flags`) names that target and zig's libc paths file
(libc.txt) pointing at the sysroot in ~. the base modules gain their
freebsd answers without config changes — each module branches comptime
on the target OS the way upstream V's `$if freebsd` did, one binary per
OS target from one module tree.

what answers what on freebsd (modules/freebsd.zig carries the ABI
transcribed from the sysroot's headers):

memory: hw.physmem + vm.stats.vm.v_free_count/v_inactive_count
swap: vm.swap_total / vm.swap_reserved
mount: libc's statvfs(3) (freebsd's own field order)
uptime: kern.boottime + clock_gettime(2)
loadavg: getloadavg(3)
cpu: hw.model + hw.ncpu + dev.cpu.0.freq
battery: hw.acpi.battery.life/state (+hw.acpi.acline)
temp: dev.cpu.0.temperature (tenths of kelvin, or the "37.0C" string)
os: "FreeBSD <release>" via libc's __xuname (the libc inlines uname(3))
shell/terminal: the /proc walk rides kern.proc kinfo_proc (ki_pid,
ki_ppid, ki_comm at their header-computed offsets, struct 1088 bytes)
pid1: pid 1's ki_comm from the same kinfo read
vpn: libc getifaddrs(3) for tun*/wg*/tap*/ppp
packages: a `freebsd` backend counting /var/db/pkg

host, boot, theme, wm, displays, gpu stay linux-shaped for now: they
answer "?" on freebsd rather than guess.

one fixture patch: the sysroot's usr/lib/libc.so ldscript pins
`GROUP ( /lib/libc.so.7 ...)` to the release image's path — it now
points at the sysroot's own absolute, with the original kept as
libc.so.orig.

then, from this dir:

```
v run generator -S -B -s config.lip
v run build.vsh build
file target/divifetch-freebsd   # for FreeBSD 15.1
```

to test in the VM (the freebsd relaunch script is ~/vm/freebsd/launch.sh;
the qemu here already runs one with port 2222 forwarded and an http
mirror on the host at 10.0.2.2:8021): at its console, log in and run

    fetch -o /tmp/divifetch http://10.0.2.2:8021/divifetch-freebsd
    chmod +x /tmp/divifetch && /tmp/divifetch

(or `curl` if the fetch names it so; the binary links libc.so.7 and
libexec/ld-elf.so.1 exactly like a native build would.)
