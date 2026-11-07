// pid1 module: pid 1's comm — one read instead of one spawned child.
// the trailing newline cut plus the first NUL keeps a padded record
// clean, the zig module's answer shape. the BSD targets read kern.proc
// kinfo records per kernel through the zig helpers; the V port answers
// '?' there until a V helper lands. macOS answers launchd from its own
// kinfo_proc layout.
module pid1

import os

@[direct_array_access]
pub fn preset() string {
	$if openbsd {
		return '?'
	}
	$if freebsd {
		return '?'
	}
	$if macos {
		p := macos_proc(1) or { return '?' }
		return p.comm
	}

	content := os.read_file('/proc/1/comm') or { return '?' }
	if content.len == 0 {
		return '?'
	}
	pure := first_line(content)
	zero := pure.index_u8(u8(0))
	if zero >= 0 {
		return pure[0..zero]
	}
	return pure
}

// first_line cuts the head line of a text payload without the line
// ending — the zig util's readFirstLine, on a payload already read.
@[direct_array_access]
fn first_line(s string) string {
	nl := s.index_u8(`\n`)
	mut line := if nl >= 0 { s[0..nl] } else { s }
	for line.len > 0 && line[line.len - 1] == `\r` {
		line = line[0..line.len - 1]
	}
	return line
}

struct ProcStat {
	comm string
	ppid int
}

// kinfo_proc on macOS (sys/sysctl.h + sys/proc.h, LP64): 648 bytes,
// kp_proc.p_comm[17] at 243, kp_eproc.e_ppid at 560 — the offsets
// modules/zig/macos.zig static-asserts. kern.proc.pid answers any pid,
// ps(1)'s own route; builtin carries the sysctl(3) prototype.
@[direct_array_access]
fn macos_proc(pid int) ?ProcStat {
	mib := [i32(1), 14, 1, i32(pid)]! // CTL_KERN, KERN_PROC, KERN_PROC_PID
	mut buf := []u8{len: 648}
	mut n := uint(648)
	if unsafe { C.sysctl(&mib[0], 4, buf.data, &n, nil, 0) } != 0 || n != 648 {
		return none
	}
	ppid := int(u32(buf[560]) | (u32(buf[561]) << 8) | (u32(buf[562]) << 16) | (u32(buf[563]) << 24))
	mut end := 243
	for end < 243 + 17 && buf[end] != 0 {
		end++
	}
	if end == 243 {
		return none
	}
	return ProcStat{
		comm: buf[243..end].bytestr()
		ppid: ppid
	}
}
