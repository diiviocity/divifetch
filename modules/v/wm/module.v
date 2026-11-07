// wm module: desktop environment variables first, then a scan of
// /proc/*/comm for a window manager process. the ranked env names want
// a value, the specials want presence only — KDE/GNOME sessions set
// their keys with no value that matters. the proc scan matches
// case-insensitively and maps a few comms onto their display names,
// KWin/Mutter-style. no procfs reads the natural '?', env still first.
// macOS scans libproc's pid list for the tiling managers that ride the
// WindowServer and answers its compositor — "Quartz Compositor (yabai)",
// fastfetch's WM-plus-plugin shape.
module wm

import os

const env_vars = ['XDG_CURRENT_DESKTOP', 'XDG_SESSION_DESKTOP', 'CURRENT_DESKTOP', 'SESSION_DESKTOP',
	'DESKTOP_SESSION']

// presence-only env tests (the value does not matter)
const special_envs = [
	['KDE_FULL_SESSION', 'KDE'],
	['KDE_SESSION_UID', 'KDE'],
	['KDE_SESSION_VERSION', 'KDE'],
	['GNOME_DESKTOP_SESSION_ID', 'GNOME'],
	['MATE_DESKTOP_SESSION_ID', 'MATE'],
	['TDE_FULL_SESSION', 'Trinity'],
	['HYPRLAND_CMD', 'Hyprland'],
	['SWAYSOCK', 'Sway'],
]

// the window managers the proc scan accepts
const known_wms = ['sway', 'hyprland', 'wayfire', 'river', 'dwm', 'i3', 'bspwm', 'herbstluftwm',
	'awesome', 'xmonad', 'openbox', 'fluxbox', 'icewm', 'jwm', 'mutter', 'kwin_wayland', 'kwin_x11',
	'kwin', 'muffin', 'marco', 'metacity', 'xfwm4', 'compiz', 'enlightenment', 'lxqt-session',
	'plasmashell']

@[direct_array_access]
pub fn preset() string {
	for name in env_vars {
		value := os.getenv(name)
		if value.len > 0 {
			return value
		}
	}

	// presence-only env tests: a set-but-empty value still counts, so
	// the environ map answers set-vs-unset where getenv cannot
	envmap := os.environ()
	for pair in special_envs {
		if pair[0] in envmap {
			return pair[1]
		}
	}

	$if macos {
		return macos_scan()
	}

	// last resort: look for a running window manager process. only
	// numeric (pid) entries count
	procs := os.ls('/proc') or { return '?' }
	for entry in procs {
		if entry.len == 0 || entry[0] < `1` || entry[0] > `9` {
			continue
		}
		comm_raw := os.read_file('/proc/${entry}/comm') or { continue }
		comm := first_line(comm_raw)
		if comm.len == 0 {
			continue
		}
		if in_known_wms(comm) {
			return wm_name(comm)
		}
	}

	return '?'
}

@[direct_array_access]
fn in_known_wms(comm string) bool {
	lower := comm.to_lower_ascii()
	for item in known_wms {
		if item == lower {
			return true
		}
	}
	return false
}

// wm_name maps a few comm spellings onto their display names, the zig
// module's special cases; everything else passes as read.
@[direct_array_access]
fn wm_name(comm string) string {
	lower := comm.to_lower_ascii()
	match lower {
		'kwin_wayland', 'kwin_x11', 'kwin' {
			return 'KWin'
		}
		'mutter' {
			return 'Mutter'
		}
		'muffin' {
			return 'Muffin'
		}
		'xfwm4' {
			return 'Xfwm4'
		}
		'plasmashell' {
			return 'KDE Plasma'
		}
		else {
			return comm
		}
	}
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

fn C.proc_listallpids(buffer voidptr, buffersize i32) i32
fn C.proc_name(pid i32, buffer voidptr, buffersize u32) i32

// fastfetch's maintained list (wm_apple.m), process name -> display
const macos_wms = [
	['rectangle', 'Rectangle'],
	['yabai', 'yabai'],
	['aerospace', 'AeroSpace'],
	['amethyst', 'Amethyst'],
	['glazewm', 'GlazeWM'],
]

// macos_scan: the managers are the user's own processes, which
// proc_name answers (it fails on other users' — skipped).
@[direct_array_access]
fn macos_scan() string {
	mut pids := []i32{len: 8192}
	n := C.proc_listallpids(pids.data, i32(pids.len * 4))
	mut name_buf := []u8{len: 64}
	for i in 0 .. if n > 0 && n <= pids.len { n } else { 0 } {
		pid := pids[i]
		if pid <= 0 {
			continue
		}
		got := C.proc_name(pid, name_buf.data, u32(name_buf.len))
		if got <= 0 {
			continue
		}
		lower := name_buf[..got].bytestr().to_lower_ascii()
		for pair in macos_wms {
			if lower == pair[0] {
				return 'Quartz Compositor (${pair[1]})'
			}
		}
	}
	return 'Quartz Compositor'
}
