// monitor module: connected DRM outputs and their preferred mode, from
// /sys/class/drm/<conn>/modes — up to four outputs, "; "-joined.
// connector nodes look like "card0-eDP-1", so bare cardN devices carry
// no dash, no res, and never count. zero spawn. the kind spells as
// monitor: display is a blip machine builtin (see the const the
// generator carries), so its forms never reach the entry walk.
module monitor

import os

@[direct_array_access]
pub fn preset() string {
	entries := os.ls('/sys/class/drm') or { return '?' }
	mut parts := []string{}
	for entry in entries {
		if parts.len >= 4 {
			break
		}
		if !entry.starts_with('card') {
			continue
		}
		if entry.index_u8(`-`) <= 0 {
			continue
		}
		// the enabled file reads "enabled" onto one line when connected
		enabled := os.read_file('/sys/class/drm/${entry}/enabled') or { continue }
		if first_line(enabled).trim(' \t') != 'enabled' {
			continue
		}

		modes := os.read_file('/sys/class/drm/${entry}/modes') or { continue }
		if modes.len == 0 {
			continue
		}
		// each mode line is "<WxH> <refresh> ...", line one preferred
		head := first_line(modes).trim(' \t\r')
		sp := head.index_u8(` `)
		res := if sp >= 0 { head[0..sp] } else { head }
		if res.len == 0 {
			continue
		}
		parts << res
	}
	if parts.len == 0 {
		return '?'
	}
	return parts.join('; ')
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
