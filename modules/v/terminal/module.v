// terminal module: env hints + PID leaking first, then a walk up the
// process tree skipping shells, falls back to $TERM/$TERM_PROGRAM,
// appends a version when found. Ported from modules/zig/terminal.
//
// detect() is exported: the font module reuses the same identity
// detection instead of duplicating it (fastfetch shares
// detection/terminalshell across terminal and terminalfont too).
//
// The small helper fns (strict pid parse, /proc/<pid>/stat, version
// capture) live here instead of a shared module: V side collates them
// per module file, following the zig util.zig semantics.
module terminal

import os

pub struct Info {
pub:
	name string // raw process name (comm)
	pid  int    // the terminal's own pid when it could be pinned (0 otherwise)
}

struct Hint {
	env  string
	name string
}

const hints = [
	Hint{ env: 'KITTY_PID', name: 'kitty' },
	Hint{ env: 'ALACRITTY_SOCKET', name: 'alacritty' },
	Hint{ env: 'WEZTERM_PANE', name: 'wezterm' },
	Hint{ env: 'GHOSTTY_RESOURCES_DIR', name: 'ghostty' },
	Hint{ env: 'FOOT_SERVER_SOCKET', name: 'foot' },
	Hint{ env: 'KONSOLE_VERSION', name: 'konsole' },
	Hint{ env: 'XTERM_VERSION', name: 'xterm' },
]

const skipped = ['sh', 'ash', 'bash', 'zsh', 'ksh', 'mksh', 'csh', 'tcsh', 'fish', 'dash', 'nu',
	'elvish', 'pwsh', 'sudo', 'su', 'login', 'make', 'sshd', 'sshd-session', 
	// build tooling: the bake-time walk must see THROUGH v's
	// subcommand processes to the terminal the build ran inside
	'v', 'build', 
	// the fetch's own binaries: running divifetch inside a chained
	// twin's shell walks past them to the terminal it lives in
	'divifetch', 'divifetch-run', 
	// tool hosts: opencode runs commands through its own worker chain
	// between the user's shell and the fetch; the climb passes it to
	// reach the terminal the human actually sits in
	'opencode', 'generator']

struct Pretty {
	proc string
	name string
}

const pretty_map = [
	Pretty{ proc: 'gnome-terminal', name: 'GNOME Terminal' },
	Pretty{ proc: 'konsole', name: 'Konsole' },
	Pretty{ proc: 'xfce4-terminal', name: 'Xfce Terminal' },
	Pretty{ proc: 'alacritty', name: 'Alacritty' },
	Pretty{ proc: 'kitty', name: 'kitty' },
	Pretty{ proc: 'foot', name: 'foot' },
	Pretty{ proc: 'wezterm-gui', name: 'WezTerm' },
	Pretty{ proc: 'wezterm', name: 'WezTerm' },
	Pretty{ proc: 'ghostty', name: 'Ghostty' },
	Pretty{ proc: 'st', name: 'st' },
	Pretty{ proc: 'urxvt', name: 'urxvt' },
	Pretty{ proc: 'terminator', name: 'Terminator' },
	Pretty{ proc: 'tilix', name: 'Tilix' },
	Pretty{ proc: 'xterm', name: 'XTerm' },
	Pretty{ proc: 'ratty', name: 'Ratty' },
	// macOS: Terminal.app's process is plain "Terminal"; iTerm2 runs its
	// shells under an "iTermServer-<version>" helper.
	Pretty{ proc: 'Terminal', name: 'Apple Terminal' },
	Pretty{ proc: 'iTermServer', name: 'iTerm2' },
	Pretty{ proc: 'iTerm2', name: 'iTerm2' },
]

@[direct_array_access]
fn in_list(name string, list []string) bool {
	return name in list // exact match, like zig util.inList
}

// parse_pid mirrors the zig std.fmt.parseInt(pid_t, trimmed, 10) call:
// the whole trimmed string must be sign + digits, else nothing. V's
// built-in .int() is lenient (trailing junk silently cut), so the
// strictness lives here.
@[direct_array_access]
fn parse_pid(raw string) ?int {
	s := raw.trim(' \t')
	if s.len == 0 || s == '-' || s == '+' {
		return none
	}
	mut start := 0
	if s[0] == u8(`-`) || s[0] == u8(`+`) {
		start = 1
	}
	for j := start; j < s.len; j++ {
		if !s[j].is_digit() {
			return none
		}
	}
	return s.int()
}

// proc_stat parses /proc/<pid>/stat: comm (inside the parentheses) and
// ppid. Returns none when unreadable, like the zig util helper.
@[direct_array_access]
fn proc_stat(pid int) ?ProcStat {
	$if linux {
		raw := os.read_file('/proc/${pid}/stat') or { return none }
		first := first_line_of(raw)
		if first.len == 0 {
			return none
		}
		lp := first.index_u8(`(`)
		if lp < 0 {
			return none
		}
		rp := first.last_index_u8(`)`)
		if rp < 0 || lp >= rp {
			return none
		}
		// After the process name: " S <ppid> ..."
		rest := first[rp + 1..].trim_left(' ')
		if rest.len < 2 {
			return none // rest[0] is the state character
		}
		fields := rest[1..].trim_left(' ')
		pe := fields.index_u8(` `)
		ppid := if pe >= 0 { fields[0..pe].int() } else { fields.int() }
		return ProcStat{
			comm: first[lp + 1..rp]
			ppid: ppid
		}
	}
	$if openbsd {
		// the BSDs ride the zig modules' helpers; the V branch answers '?' until a V helper lands.
		return none
	}
	$if freebsd {
		return none
	}
	$if macos {
		return macos_proc(pid)
	}
	return none
}

struct ProcStat {
	comm string
	ppid int
}

// first_line_of cuts `s` off after the first newline (zig util.firstLine).
@[direct_array_access]
fn first_line_of(s string) string {
	nl := s.index_u8(`\n`)
	line := if nl >= 0 { s[0..nl] } else { s }
	return line.trim_right('\r')
}

// extract_version walks a version string to the first run of digits and
// dots, e.g. "zsh 5.9 (x86_64-pc-linux-gnu)" -> "5.9" (zig util).
@[direct_array_access]
fn extract_version(s string) string {
	mut start := 0
	for start < s.len && !s[start].is_digit() {
		start++
	}
	mut e := start
	for e < s.len && (s[e].is_digit() || s[e] == u8(`.`)) {
		e++
	}
	return s[start..e]
}

// version_of runs `<exe> --version` / `<exe> -v` and extracts the digits.
// os.exec merges stdout+stderr exactly like the zig capture; a spawn
// failure surfaces as exit_code < 0 (with a non-version message), so it
// counts empty like the zig spawn-fallback buffer.
@[direct_array_access]
fn version_of(exe string, use_version_arg bool) string {
	flag := if use_version_arg { '--version' } else { '-v' }
	res := os.exec([exe, flag])
	if res.exit_code < 0 {
		return ''
	}
	return extract_version(first_line_of(res.output))
}

// env-first identity: TERM_PROGRAM values are display names ("WezTerm",
// "ghostty") mapped to the raw identities the font parsers key off.
// Case-insensitive via to_lower_ascii (std.ascii had no
// indexIgnoreCase in 0.17 either).
@[direct_array_access]
fn from_term_program() ?string {
	raw := os.getenv_opt('TERM_PROGRAM') or { return none }
	if raw.len == 0 {
		return none
	}
	program := raw.to_lower_ascii()
	needles := ['wezterm', 'ghostty', 'foot', 'kitty', 'alacritty', 'konsole']
	for m in needles {
		if program.contains(m) {
			return m
		}
	}
	// the macOS apps spell their own: "Apple_Terminal", "iTerm.app"
	if program.contains('apple_terminal') {
		return 'Terminal'
	}
	if program.contains('iterm') {
		return 'iTerm2'
	}
	return none // unknown provider: don't let it poison the walk
}

// pretty maps a raw comm into the display name (prefix match, zig order).
@[direct_array_access]
fn pretty(comm string) ?string {
	for p in pretty_map {
		if comm.starts_with(p.proc) {
			return p.name
		}
	}
	return none
}

/// Detection shared by terminal, terminalfont (via font) — and anything
/// else that needs to know what terminal the shell lives in.
@[direct_array_access]
pub fn detect() Info {
	mut name := ''
	mut pid := 0

	// Explicit source-env inheritance: DIVIFETCH_TERMINAL_PID pins the
	// exact terminal (build wrappers / shells can set it so a bake sees
	// the caller's real terminal, even through tooling chains).
	if pid_val := os.getenv_opt('DIVIFETCH_TERMINAL_PID') {
		if p := parse_pid(pid_val) {
			if p > 0 {
				if stat := proc_stat(p) {
					if stat.comm.len != 0 {
						return Info{ name: stat.comm, pid: p }
					}
				}
			}
		}
	}

	for hint in hints {
		val := os.getenv_opt(hint.env) or { continue }

		// Fastfetch's PID shortcut: when the env value IS a pid, the
		// walker can be skipped entirely and identity read from that
		// pid's /proc/<pid>/stat comm (more truthful than the hint).
		mut stayed_hint := false
		if p := parse_pid(val) {
			if stat := proc_stat(p) {
				name = stat.comm
				pid = p
			}
			stayed_hint = true
		}
		if !stayed_hint {
			name = hint.name
		}
		break
	}

	if name.len == 0 {
		if tp := from_term_program() {
			name = tp
		}
	}

	if name.len == 0 {
		mut cur := os.getppid()
		mut depth := 0
		for cur > 1 && depth < 32 {
			stat := proc_stat(cur) or { break }
			if !in_list(stat.comm, skipped) {
				name = stat.comm
				pid = cur
				break
			}
			cur = stat.ppid
			depth++
		}
	}

	if name.len == 0 {
		// "$TERM = xterm-kitty" style last chance
		term := os.getenv_opt('TERM') or { '' }
		if term.len != 0 {
			known := ['kitty', 'alacritty', 'foot', 'ghostty', 'st', 'xterm']
			for k in known {
				if term.contains(k) {
					name = k
					break
				}
			}
		}
	}

	return Info{ name: name, pid: pid }
}

@[direct_array_access]
pub fn preset() string {
	name := detect().name
	if name.len == 0 {
		return '?'
	}

	exe := if name.starts_with('wezterm-gui') { 'wezterm' } else { name }

	mut ver := version_of(exe, false)
	if ver.len == 0 {
		ver = version_of(exe, true)
	}
	// app-bundle terminals (Terminal.app, iTerm2) have no CLI to ask;
	// they export their version beside TERM_PROGRAM instead — trusted
	// only when TERM_PROGRAM names this same terminal (tmux sets the
	// pair too, for itself).
	if ver.len == 0 {
		if tp := from_term_program() {
			if tp == name {
				ver = extract_version(os.getenv('TERM_PROGRAM_VERSION'))
			}
		}
	}
	mut display := name
	if p := pretty(name) {
		display = p
	}

	if ver.len != 0 {
		return '${display} ${ver}'
	}
	return display
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
