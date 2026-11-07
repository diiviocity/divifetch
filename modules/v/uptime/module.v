// uptime module: total uptime from /proc/uptime, formatted d/h/m — the
// shape the zig module prints. /proc reads as size-0 files over here too:
// os.read_file slurps whatever the sysfs pages say, backslashes aside.
// macOS answers kern.boottime's tv_sec against clock_gettime(2).
module uptime

import os

@[direct_array_access]
pub fn preset() string {
	$if macos {
		return spell(macos_seconds() or { return '?' })
	}
	line := os.read_file('/proc/uptime') or { return '?' }
	if line.len == 0 {
		return '?'
	}
	// /proc/uptime is "<seconds> <idle_seconds>".
	sp := line.index_u8(` `)
	token := if sp >= 0 { line[0..sp].trim_space() } else { line.trim_space() }
	seconds := token.f64()
	if seconds <= 0.0 {
		return '?'
	}
	return spell(u64(seconds))
}

// spell formats whole seconds d/h/m, the zig module's three shapes.
@[direct_array_access]
fn spell(seconds u64) string {
	mut s := seconds
	d := s / 86400
	s %= 86400
	h := s / 3600
	s %= 3600
	m := s / 60
	s %= 60
	if d != 0 {
		return '${d}d ${h}h ${m}m'
	}
	if h != 0 {
		return '${h}h ${m}m'
	}
	return '${m}m ${s}s'
}

// the macOS reads ride libSystem's sysctlbyname; V's C backend is
// headerless, so the prototype rides here and every answer comes back
// as raw bytes read at the header's own offsets (modules/zig/macos.zig
// carries the same ABI facts, static-asserted against the darwin
// headers).
fn C.sysctlbyname(name &char, oldp voidptr, oldlenp &uint, newp voidptr, newlen uint) i32

// sysctl_bytes answers one named node's bytes, none when the node is
// absent or outgrows `size`.
@[direct_array_access]
fn sysctl_bytes(name string, size int) ?[]u8 {
	mut buf := []u8{len: size}
	mut n := uint(size)
	if unsafe { C.sysctlbyname(&char(name.str), buf.data, &n, nil, 0) } != 0 || n > uint(size) {
		return none
	}
	return buf[..int(n)]
}

@[direct_array_access]
fn le_u32(b []u8, off int) u32 {
	return u32(b[off]) | (u32(b[off + 1]) << 8) | (u32(b[off + 2]) << 16) | (u32(b[off + 3]) << 24)
}

@[direct_array_access]
fn le_u64(b []u8, off int) u64 {
	return u64(le_u32(b, off)) | (u64(le_u32(b, off + 4)) << 32)
}

// macos_seconds answers kern.boottime (a 16-byte timeval, tv_sec first)
// subtracted from the realtime clock (_CLOCK_REALTIME is 0 on darwin).
@[direct_array_access]
fn macos_seconds() ?u64 {
	raw := sysctl_bytes('kern.boottime', 16) or { return none }
	if raw.len < 8 {
		return none
	}
	boot := i64(le_u64(raw, 0))
	mut now := []u8{len: 16}
	if C.clock_gettime(0, now.data) != 0 {
		return none
	}
	sec := i64(le_u64(now, 0))
	if boot <= 0 || sec <= boot {
		return none
	}
	return u64(sec - boot)
}
