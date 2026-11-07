// font module — the running terminal's configured font, per-terminal
// parsing stolen from fastfetch's detection/terminalfont (see
// ~/git/fastfetch). Zero spawn. Identity comes from the shared terminal
// module detector (env hints + PID /proc/<pid>/comm, TERM_PROGRAM,
// process walk, $TERM). Ported from modules/zig/font/module.zig — the
// parsers below mirror its file order and write quirks alongside ("Key+"
// iniValue shapes, in-key separators, space-separated fallback chains),
// so a call that yields '?' on the zig side yields '?' here too.
//
// Per terminal:
//   kitty        .config/kitty/kitty.conf: font_family (default monospace)
//   alacritty    alacritty.toml/yml: quoted family =
//   foot         foot.ini: font=, Xft pattern, comma fallback list
//                (first entry), trailing "-<size>/str" suffixes stripped
//   ghostty      ghostty/config: font-family=
//   konsole      konsolerc DefaultProfile -> profile Font= (truncated at
//                the first comma); built-in profile default -> monospace
//   deepin       deepin config.conf via [basic.interface.font] section,
//                value= lines; default "Noto Sans Mono"
//   qterminal    qterminal.ini: fontFamily= / fontSize= (joined)
//   lxterminal   lxterminal.conf: fontname =
//   sakura, termite, weston, kmscon, cosmic-term, xfce4-terminal: the
//                plain-file/line parsers as in fastfetch
//   terminator   config with use_system_font handling (system font alias)
//   xterm        .Xresources/.Xdefaults faceName; default "fixed"
//   st           -f cmdline override via /proc/<pid>/cmdline, else
//                binary string scrape of the st executable (fastfetch
//                ffBinaryExtractStrings, first string containing "size=")
//   urxvt        URxvt.font: Xft or XLFD field parsing
//   wezterm      .wezterm.lua first string in wezterm.font(...)
//   Terminal.app com.apple.Terminal prefs: the default profile's "Font",
//                an NSKeyedArchiver'd NSFont (NSName + NSSize) — read
//                through CoreFoundation, not fastfetch's osascript
//   iTerm2       com.googlecode.iterm2 prefs: the $ITERM_PROFILE
//                bookmark's "Normal Font" ("Name Size")
//
// Consciously NOT stolen (would drag dependencies): the GNOME gconf ring
// (gnome-terminal/tilix/mate/kgx/ptyxis — fastfetch dlopens libgio) and
// warp (yyjson). Those stay '?'.
//
// No shared helper module: the small parsers (firstQuoted, iniValue,
// xftFamily, xlfdFamily, configBase) live as private fns here, obeying
// the zig util.zig semantics.
module font

import os
import terminal

// Config root: XDG_CONFIG_HOME when non-empty, else $HOME/.config.
@[direct_array_access]
fn config_base() ?string {
	xdg := os.getenv_opt('XDG_CONFIG_HOME') or { '' }
	if xdg.len != 0 {
		return xdg
	}
	home := os.getenv_opt('HOME') or { return none }
	return '${home}/.config'
}

@[direct_array_access]
fn first_quoted(haystack string) string {
	start := haystack.index_u8(`"`)
	if start < 0 {
		return ''
	}
	rest := haystack[start + 1..]
	end := rest.index_u8(`"`)
	if end < 0 {
		return ''
	}
	return rest[0..end]
}

// Value reader for `key<sep>value` ini-ish lines, allowing spaces around
// the separator. Returns the trimmed value at first hit. (Ported as the
// zig parser, key shapes and all — keys ending in the separator or in a
// space only match the exact literal shapes they spelled.)
@[direct_array_access]
fn ini_value(content string, key string, sep u8) string {
	for line_raw in content.split('\n') {
		line := line_raw.trim_left(' \t')
		if !line.starts_with(key) {
			continue
		}
		after := line[key.len..]
		if after.len == 0 {
			continue
		}
		if after[0] != sep {
			t := after.trim_left(' \t')
			if t.len == 0 || t[0] != sep {
				continue
			}
			return t[1..].trim(' \t\r')
		}
		return after[1..].trim(' \t\r')
	}
	return ''
}

// Xft "Family[size][:options]" -> family, with the trailing "-<size>"
// and everything after ":" removed (foot's font=, st's patterns).
@[direct_array_access]
fn xft_family(pattern string) string {
	mut text := pattern
	ci := text.index_u8(`:`)
	if ci >= 0 {
		text = text[0..ci]
	}
	text = text.trim(' \t')

	// trailing -<digits>[.<digits>] is a size, not part of the family
	di := text.last_index_u8(`-`)
	if di >= 0 {
		tail := text[di + 1..]
		if tail.len > 0 && tail[0].is_digit() {
			mut i := 0
			for i < tail.len && (tail[i].is_digit() || tail[i] == u8(`.`)) {
				i++
			}
			if i == tail.len {
				text = text[0..di].trim_right(' \t')
			}
		}
	}
	return text
}

// XLFD "-vendor-family-weight-slant-setwidth-addstyle-pixelsize..."
// -> the family (field 2 after the leading dash).
@[direct_array_access]
fn xlfd_family(pattern string) string {
	if pattern.len == 0 || pattern[0] != u8(`-`) {
		return ''
	}
	if pattern[1..].index_u8(`-`) < 0 {
		return ''
	}
	mut field := 0
	for f in pattern[1..].split('-') {
		if field == 1 {
			return f.trim(' *')
		}
		field++
	}
	return ''
}

// ---------------------------------------------------------------------
// per-terminal parsers (order mirrors the zig file)

@[direct_array_access]
fn parse_kitty(base string) ?string {
	conf := os.read_file('${base}/kitty/kitty.conf') or {
		// kitty with no font_family uses fontconfig's monospace alias —
		// fastfetch models this as the real default.
		return 'monospace'
	}
	for line in conf.split('\n') {
		if !line.starts_with('font_family') {
			continue
		}
		val := line['font_family'.len..].trim(' \t')
		if val.len == 0 || val[0] == u8(`#`) {
			continue
		}
		return val
	}
	// kitty with no font_family uses fontconfig's monospace alias —
	// fastfetch models this as the real default.
	return 'monospace'
}

@[direct_array_access]
fn parse_alacritty(base string) ?string {
	for file in ['alacritty/alacritty.toml', 'alacritty/alacritty.yml'] {
		conf := os.read_file('${base}/${file}') or { continue }
		for line in conf.split('\n') {
			eq := line.index_u8(`=`)
			if eq < 0 {
				continue
			}
			key := line[0..eq].trim(' \t')
			if key != 'family' {
				continue
			}
			family := first_quoted(line[eq + 1..]).trim(' \t')
			if family.len != 0 {
				return family
			}
		}
	}
	return none
}

@[direct_array_access]
fn parse_foot(base string) ?string {
	conf := os.read_file('${base}/foot/foot.ini') or {
		// foot's built-in default
		return 'monospace'
	}
	for line in conf.split('\n') {
		eq := line.index_u8(`=`)
		if eq < 0 {
			continue
		}
		key := line[0..eq].trim(' \t')
		if key != 'font' {
			continue
		}
		mut val := line[eq + 1..].trim(' \t')
		if val.len == 0 {
			break
		}
		// foot splits fallback fonts on commas: first entry only
		ci := val.index_u8(`,`)
		if ci >= 0 {
			val = val[0..ci]
		}
		family := xft_family(val)
		if family.len != 0 {
			return family
		}
		break
	}
	// foot's built-in default
	return 'monospace'
}

@[direct_array_access]
fn parse_ghostty(base string) ?string {
	conf := os.read_file('${base}/ghostty/config') or { return none }
	for line in conf.split('\n') {
		eq := line.index_u8(`=`)
		if eq < 0 {
			continue
		}
		key := line[0..eq].trim(' \t')
		if key != 'font-family' {
			continue
		}
		val := line[eq + 1..].trim(' \t')
		if val.len != 0 {
			return val
		}
	}
	return none
}

@[direct_array_access]
fn parse_konsole() ?string {
	base := config_base() or { return none }

	mut share_root := ''
	xdg := os.getenv_opt('XDG_DATA_HOME') or { '' }
	if xdg.len != 0 {
		share_root = xdg
	} else {
		home := os.getenv_opt('HOME') or { return none }
		share_root = '${home}/.local/share'
	}

	// Preferred: konsolerk's DefaultProfile.
	// An unreadable/missing konsolerc falls through to the data-dir
	// scan, exactly like the zig block.
	conf := os.read_file('${base}/konsole/konsolerc') or { '' }
	if conf.len != 0 {
		for line in conf.split('\n') {
			if !line.starts_with('DefaultProfile=') {
				continue
			}
			profile := line['DefaultProfile='.len..].trim_right(' \t\r')
			if profile.len == 0 {
				// "Built-in profile is used": konsole's default font
				return 'monospace'
			}
			pf := os.read_file('${share_root}/konsole/${profile}') or { return none }
			for pline in pf.split('\n') {
				if !pline.starts_with('Font=') {
					continue
				}
				val := pline['Font='.len..].trim_right(' \t\r')
				ci := val.index_u8(`,`)
				comma := if ci >= 0 { ci } else { val.len }
				if comma == 0 {
					break
				}
				return val[0..comma]
			}
			return none
		}
	}

	// Fallback: first profile file in the data dir.
	names := os.ls('${share_root}/konsole') or { return none }
	for name in names {
		if !name.ends_with('.profile') {
			continue
		}
		pf := os.read_file('${share_root}/konsole/${name}') or { continue }
		for pline in pf.split('\n') {
			if !pline.starts_with('Font=') {
				continue
			}
			val := pline['Font='.len..].trim_right(' \t\r')
			ci := val.index_u8(`,`)
			comma := if ci >= 0 { ci } else { val.len }
			if comma == 0 {
				break
			}
			return val[0..comma]
		}
	}
	return 'monospace' // built-in default profile
}

@[direct_array_access]
fn parse_deepin(base string) ?string {
	conf := os.read_file('${base}/deepin/deepin-terminal/config.conf') or { return none }

	mut family := ''
	mut size := ''
	lines := conf.split('\n')
	mut idx := 0
	for idx < lines.len {
		terminated := lines[idx].trim_right(' \t\r')
		if family.len == 0 && terminated == '[basic.interface.font]' {
			idx++
			content := if idx < lines.len { lines[idx] } else { '' }
			family = ini_value(content, 'value', u8(`=`))
		} else if size.len == 0 && terminated == '[basic.interface.font_size]' {
			idx++
			content := if idx < lines.len { lines[idx] } else { '' }
			size = ini_value(content, 'value', u8(`=`))
		}
		idx++
		if family.len != 0 && size.len != 0 {
			break
		}
	}
	if family.len == 0 {
		return 'Noto Sans Mono' // fastfetch default
	}
	return family
}

@[direct_array_access]
fn parse_qterminal(base string) ?string {
	conf := os.read_file('${base}/qterminal.org/qterminal.ini') or {
		return 'monospace' // fastfetch default
	}

	mut family := ini_value(conf, 'fontFamily=', u8(`=`))
	size := ini_value(conf, 'fontSize=', u8(`=`))
	if family.len == 0 {
		return 'monospace'
	}
	if size.len != 0 {
		return '${family} ${size}'
	}
	return family
}

@[direct_array_access]
fn parse_simple(base string, subpath string, key string) ?string {
	// sakura/sakura.conf "font=", termite/config "font =",
	// lxterminal/lxterminal.conf "fontname ="
	conf := os.read_file('${base}/${subpath}') or { return none }
	val := ini_value(conf, key, u8(` `))
	if val.len == 0 {
		return none
	}
	return val
}

@[direct_array_access]
fn parse_weston(base string) ?string {
	conf := os.read_file('${base}/weston.ini') or { return none }
	mut family := ini_value(conf, 'font=', u8(`=`))
	size := ini_value(conf, 'font-size=', u8(`=`))
	if family.len == 0 {
		family = 'DejaVu Sans Mono' // fastfetch default
	}
	if size.len != 0 {
		return '${family} ${size}'
	}
	return family
}

@[direct_array_access]
fn parse_kmscon(base string) ?string {
	conf := os.read_file('${base}/kmscon/kmscon.conf') or { return none }
	mut family := ini_value(conf, 'font-name=', u8(`=`))
	size := ini_value(conf, 'font-size=', u8(`=`))
	if family.len == 0 {
		family = 'Hack Nerd Font' // fastfetch default
	}
	if size.len != 0 {
		return '${family} ${size}'
	}
	return family
}

@[direct_array_access]
fn parse_cosmic(base string) ?string {
	// $CONFIG/cosmic/com.system76.CosmicTerm/v1/font_name (+font_size)
	mut family := ''
	if raw := os.read_file('${base}/cosmic/com.system76.CosmicTerm/v1/font_name') {
		family = raw.trim(' \t\r').trim('"')
	}
	if family.len == 0 {
		return 'Noto Sans Mono' // fastfetch default
	}
	return family
}

@[direct_array_access]
fn parse_xfce(base string) ?string {
	// xfce4-terminal.xml (xfconf): attribute-substring extraction per line;
	// then the older terminalrc. System font answers via the monospace
	// alias (xfconf's XfSettings would need xfconf — not stolen).
	xml := os.read_file('${base}/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml') or {
		return xfce_legacy(base)
	}
	mut use_system := false
	for line in xml.split('\n') {
		if !line.contains('<property name="font-use-system"') {
			continue
		}
		use_system = line.contains('value="true"')
	}

	for line in xml.split('\n') {
		pi := line.index('<property name="font-name"') or { continue }
		from := line[pi..]
		vsi := from.index('value="') or { continue }
		rest := from[vsi + 'value="'.len..]
		ei := rest.index_u8(`"`)
		if ei < 1 {
			continue
		}
		if use_system {
			return 'monospace'
		}
		return rest[0..ei]
	}
	// legacy terminalrc
	return xfce_legacy(base)
}

@[direct_array_access]
fn xfce_legacy(base string) ?string {
	rc := os.read_file('${base}/xfce4/terminal/terminalrc') or { return none }
	family := ini_value(rc, 'FontName ', u8(` `))
	if family.len != 0 {
		return family
	}
	return none
}

@[direct_array_access]
fn parse_terminator(base string) ?string {
	conf := os.read_file('${base}/terminator/config') or { return none }
	use_system := ini_value(conf, 'use_system_font', u8(`=`))
	family := ini_value(conf, 'font', u8(`=`))
	// fastfetch: use_system_font=True means the GSettings monospace;
	// we can't read dconf without glib, so alias the system font.
	if use_system.to_lower_ascii() == 'true' {
		return 'monospace'
	}
	if family.len != 0 {
		return family
	}
	return 'Mono' // fastfetch default
}

@[direct_array_access]
fn parse_xterm() ?string {
	home := os.getenv_opt('HOME') or { return none }
	for file in ['.Xresources', '.Xdefaults'] {
		conf := os.read_file('${home}/${file}') or { continue }
		for line in conf.split('\n') {
			if !line.contains('xterm*faceName') && !line.contains('xterm.vt100.faceName') {
				continue
			}
			ci := line.index_u8(`:`)
			if ci < 0 {
				continue
			}
			val := line[ci + 1..].trim(' \t')
			if val.len != 0 {
				return val
			}
		}
	}
	return 'fixed' // xterm's own default
}

@[direct_array_access]
fn parse_urxvt() ?string {
	home := os.getenv_opt('HOME') or { return none }
	for file in ['.Xresources', '.Xdefaults'] {
		conf := os.read_file('${home}/${file}') or { continue }
		for line in conf.split('\n') {
			if !line.contains('URxvt.font') {
				continue
			}
			ci := line.index_u8(`:`)
			if ci < 0 {
				continue
			}
			mut val := line[ci + 1..].trim(' \t')
			if val.len == 0 {
				continue
			}
			// entries: commas are fallback chains — first only
			vi := val.index_u8(`,`)
			if vi >= 0 {
				val = val[0..vi]
			}
			val = val.trim(' \t')
			if val.len != 0 && val[0] == u8(`-`) {
				family := xlfd_family(val)
				if family.len != 0 {
					return family
				}
				continue
			}
			if val.starts_with('xft:') {
				val = val['xft:'.len..]
			}
			family := xft_family(val)
			if family.len != 0 {
				return family
			}
		}
	}
	return none // fastfetch errors out here; we stay "?" honest
}

@[direct_array_access]
fn parse_wezterm(base string) ?string {
	// .wezterm.lua lives in $HOME (or XDG_CONFIG_HOME for some setups)
	mut paths := []string{cap: 2}
	home := os.getenv_opt('HOME') or { '' }
	if home.len != 0 {
		paths << '${home}/.wezterm.lua'
	}
	paths << '${base}/wezterm/wezterm.lua'
	for lpath in paths {
		conf := os.read_file(lpath) or { continue }
		at := conf.index('wezterm.font(') or { continue }
		family := first_quoted(conf[at + 'wezterm.font('.len..])
		if family.len != 0 {
			return family
		}
	}
	return none
}

/// st hardcodes its font in config.h: it either runs with `-f <xft>` (an
/// argv override readable from /proc/<pid>/cmdline) or the pattern lives
/// inside the binary — fastfetch scrapes the first NUL-string containing
/// "size=" from the executable itself.
@[direct_array_access]
fn st_font(info terminal.Info) ?string {
	if info.pid <= 0 {
		return none
	}

	// 1) argv override: whole /proc/<pid>/cmdline, "\0-f\0" sequence.
	raw := os.read_bytes('/proc/${info.pid}/cmdline') or { return none }
	mut i := 0
	for i + 3 < raw.len {
		if raw[i] == 0 && raw[i + 1] == u8(`-`) && raw[i + 2] == u8(`f`) && raw[i + 3] == 0 {
			mut j := i + 4
			for j < raw.len && raw[j] != 0 {
				j++
			}
			family := xft_family(bytes_str(raw[i + 4..j]))
			if family.len != 0 {
				return family
			}
		}
		i++
	}

	// 2) scrape the binary. The zig file scans through a fixed 16K
	// window; V side reads the whole executable — same strings in the
	// same order, the first "size=" string wins either way.
	exe := os.readlink('/proc/${info.pid}/exe') or { return none }
	blob := os.read_bytes(exe) or { return none }

	mut buf := []u8{cap: 256}
	for c in blob {
		if c == 0 || c < 32 {
			if buf.len != 0 {
				hay := bytes_str(buf)
				if hay.contains('size=') {
					family := xft_family(hay)
					if family.len != 0 {
						return family
					}
				}
				buf.clear()
			}
		} else if buf.len < 256 {
			buf << c
		}
	}
	if buf.len != 0 {
		hay := bytes_str(buf)
		if hay.contains('size=') {
			family := xft_family(hay)
			if family.len != 0 {
				return family
			}
		}
	}
	return none
}

// bytes_str copies a []u8 slice into a string ( []u8 -> string), the V
// equivalent of zig's byte-buffer slices.
@[direct_array_access]
fn bytes_str(raw []u8) string {
	unsafe {
		return raw.bytestr()
	}
}

/// Family for the detected terminal; none = unknown/unset ('?' then,
/// like the fastfetch dispatch reaching its else branch).
@[direct_array_access]
fn font_of(info terminal.Info, base string) ?string {
	$if macos {
		if info.name == 'Terminal' {
			return apple_terminal_font()
		}
		if info.name == 'iTerm2' || info.name.starts_with('iTermServer') {
			return iterm2_font()
		}
	}
	if info.name == 'kitty' {
		return parse_kitty(base)
	}
	if info.name == 'alacritty' {
		return parse_alacritty(base)
	}
	if info.name == 'foot' {
		return parse_foot(base)
	}
	if info.name == 'ghostty' {
		return parse_ghostty(base)
	}
	if info.name == 'konsole' || info.name == 'yakuake' {
		return parse_konsole()
	}
	if info.name == 'deepin-terminal' {
		return parse_deepin(base)
	}
	if info.name == 'qterminal' {
		return parse_qterminal(base)
	}
	if info.name == 'lxterminal' {
		return parse_simple(base, 'lxterminal/lxterminal.conf', 'fontname ')
	}
	if info.name == 'sakura' {
		return parse_simple(base, 'sakura/sakura.conf', 'font ')
	}
	if info.name == 'termite' {
		return parse_simple(base, 'termite/config', 'font ')
	}
	if info.name == 'weston-terminal' {
		return parse_weston(base)
	}
	if info.name == 'kmscon' {
		return parse_kmscon(base)
	}
	if info.name == 'cosmic-term' {
		return parse_cosmic(base)
	}
	if info.name == 'xfce4-terminal' {
		return parse_xfce(base)
	}
	if info.name == 'terminator' {
		return parse_terminator(base)
	}
	if info.name == 'xterm' {
		return parse_xterm()
	}
	if info.name == 'urxvt' || info.name == 'rxvt' {
		return parse_urxvt()
	}
	if info.name == 'wezterm' {
		return parse_wezterm(base)
	}
	if info.name == 'st' {
		return st_font(info)
	}
	return none
}

@[direct_array_access]
pub fn preset() string {
	info := terminal.detect()
	if info.name.len == 0 {
		return '?'
	}

	base := config_base() or { return '?' }
	return font_of(info, base) or { '?' }
}
