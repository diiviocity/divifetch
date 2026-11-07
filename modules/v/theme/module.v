// theme module: GTK theme / icon theme / font, parsed from
// $XDG_CONFIG_HOME (or $HOME/.config) gtk-3.0 then gtk-4.0 settings.ini
// — the zig module's read. each key keeps the first file that names it;
// the found ones join " / ". zero spawn; '?' when neither file yields
// anything.
module theme

import os

@[direct_array_access]
pub fn preset() string {
	// config root: XDG_CONFIG_HOME when non-empty, else $HOME/.config
	mut base := os.getenv('XDG_CONFIG_HOME')
	if base.len == 0 {
		home := os.getenv_opt('HOME') or { return '?' }
		base = '${home}/.config'
	}

	mut theme := ''
	mut icons := ''
	mut font := ''
	for version in ['gtk-3.0', 'gtk-4.0'] {
		if theme.len != 0 && icons.len != 0 && font.len != 0 {
			break
		}
		content := os.read_file('${base}/${version}/settings.ini') or { continue }
		for line in content.split('\n') {
			eq := line.index_u8(`=`)
			if eq < 0 {
				continue
			}
			key := line[0..eq].trim(' \t')
			val := line[eq + 1..].trim(' \t')
			if val.len == 0 {
				continue
			}
			if theme.len == 0 && key == 'gtk-theme-name' {
				theme = val
			} else if icons.len == 0 && key == 'gtk-icon-theme-name' {
				icons = val
			} else if font.len == 0 && key == 'gtk-font-name' {
				font = val
			}
		}
	}

	mut fields := []string{}
	for field in [theme, icons, font] {
		if field.len != 0 {
			fields << field
		}
	}
	if fields.len == 0 {
		return '?'
	}
	return fields.join(' / ')
}
