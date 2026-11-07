// shell module: walks up the process tree to the nearest shell, falls
// back to $SHELL, then execs the shell to append its version. the walk
// parses /proc/<pid>/stat itself, self-contained — the version check
// stays the only spawn. the BSD targets ride kern.proc through the zig
// helpers; the V port answers '?' there until a V helper lands. macOS
// walks kern.proc kinfo records instead of /proc.
module shell

import os

// the shells the walk accepts
const known_shells = ['sh', 'ash', 'bash', 'zsh', 'ksh', 'mksh', 'csh', 'tcsh', 'fish', 'dash',
	'nu', 'elvish', 'pwsh']

@[direct_array_access]
pub fn preset() string {
	$if openbsd {
		return '?'
	}
	$if freebsd {
		return '?'
	}

	mut pid := os.getppid()
	mut comm := ''
	mut depth := 0
	for pid > 1 && depth < 16 {
		stat := proc_stat(pid) or { break }
		if known_shells.contains(stat.comm) {
			comm = stat.comm
			break
		}
		pid = stat.ppid
		depth++
	}

	if comm.len == 0 {
		// $SHELL's basename plays the comm when no shell rides the tree
		env_shell := os.getenv('SHELL')
		if env_shell.len == 0 {
			return '?'
		}
		comm = basename(env_shell)
	}

	// the version check execs the shell binary directly (bare name,
	// PATH resolves it) — no /bin/sh -c, like the zig argv capture
	res := os.exec([comm, '--version'])
	if res.exit_code == -1 {
		// v exec answers a junk 'exec("…") failed' message when the
		// spawn never took off; the zig helper kept an empty slice there
		return comm
	}
	// "zsh 5.9 (x86_64-pc-linux-gnu)" -> "5.9": the first digits run
	ver := extract_version(first_line(res.output))
	if ver.len != 0 {
		return '${comm} ${ver}'
	}
	return comm
}

struct ProcStat {
	comm string
	ppid int
}

// proc_stat parses /proc/<pid>/stat: the comm between the parens (the
// last ')' bounds it — a comm can carry parens itself) and the ppid
// after it.
@[direct_array_access]
fn proc_stat(pid int) ?ProcStat {
	$if macos {
		return macos_proc(pid)
	}
	raw := os.read_file('/proc/${pid}/stat') or { return none }
	line := first_line(raw)
	if line.len == 0 {
		return none
	}
	lp := line.index_u8(`(`)
	if lp < 0 {
		return none
	}
	rp := line.last_index_u8(`)`)
	if rp < 0 || lp >= rp {
		return none
	}
	comm := line[lp + 1..rp]
	// after the process name: " S <ppid> ..." — rest[0] is the state
	// character, the next token is the ppid
	fields := line[rp + 1..].trim_left(' ')
	if fields.len < 2 {
		return none
	}
	rest := fields[1..].trim_left(' ')
	mut end := rest.index_u8(` `)
	if end < 0 {
		end = rest.len
	}
	ppid := rest[0..end].i64()
	if ppid < 0 {
		return none
	}
	return ProcStat{
		comm: comm
		ppid: int(ppid)
	}
}

// basename answers the part after a path's last '/', $SHELL style.
@[direct_array_access]
fn basename(path string) string {
	slash := path.last_index_u8(`/`)
	if slash >= 0 {
		return path[slash + 1..]
	}
	return path
}

// extract_version walks to the first digit run and holds while digits
// or dots answer, the zig util verbatim.
@[direct_array_access]
fn extract_version(s string) string {
	mut start := 0
	for start < s.len && !(s[start] >= `0` && s[start] <= `9`) {
		start++
	}
	mut end := start
	for end < s.len && ((s[end] >= `0` && s[end] <= `9`) || s[end] == `.`) {
		end++
	}
	return s[start..end]
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
