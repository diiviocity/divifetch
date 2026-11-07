// packages module — counts the installed packages of the package
// system the entry names: the entry's backends try in the order its
// :args gave, the bare form tries the full list, and the first hit
// answers "N (backend)". a backend whose database is not on this
// machine yields none, so the next candidate gets its turn — the
// former packages_* counters, merged, with apk/dpkg counting record
// signatures and emerge growing its two level tree.
module packages

import os

// the linux backends, in the zig module's table order
const linux_backends = ['apk', 'dpkg', 'emerge', 'eopkg', 'pacman', 'pkgtool', 'xbps']

// macOS: Homebrew's Cellar/Caskroom (under /opt/homebrew on Apple
// silicon, /usr/local on Intel — both tried) and MacPorts' software dir,
// one directory per installed package each.
const macos_backends = ['brew', 'brew-cask', 'port']

const apk_needle = '\nC:Q'

const dpkg_needle = '\nStatus: install ok installed'

const xbps_needle = '<string>installed</string>'

@[direct_array_access]
pub fn preset(choices []string) string {
	// the BSDs count a plain /var/db/pkg through the zig helpers; the
	// V branch answers '?' until a V helper lands.
	$if openbsd {
		return '?'
	}
	$if freebsd {
		return '?'
	}
	backends := $if macos { macos_backends } $else { linux_backends }

	if choices.len == 0 {
		// the bare form tries the full list in the same order: the
		// machine it runs on answers itself
		for name in backends {
			count := backend_count(name) or { continue }
			return '${count} (${name})'
		}
		return '?'
	}
	for choice in choices {
		for name in backends {
			if name != choice {
				continue
			}
			count := backend_count(name) or { continue }
			return '${count} (${name})'
		}
	}
	return '?'
}

// backend_count answers one backend's package count, none when its
// database is not around — a clean zero still counts, as the zig
// counters did.
@[direct_array_access]
fn backend_count(name string) ?u64 {
	if name == 'brew' || name == 'brew-cask' {
		leaf := if name == 'brew' { 'Cellar' } else { 'Caskroom' }
		for prefix in ['/opt/homebrew', '/usr/local'] {
			count := non_dot_entries('${prefix}/${leaf}') or { continue }
			if count != 0 {
				return count
			}
		}
		return none
	}
	if name == 'port' {
		count := non_dot_entries('/opt/local/var/macports/software') or { return none }
		if count == 0 {
			return none
		}
		return count
	}
	if name == 'apk' {
		text := os.read_file('/lib/apk/db/installed') or { return none }
		// apk streams the "\nC:Q" record signature; the first record
		// carries no leading newline, so the count seeds at 1
		return u64(1 + text.count(apk_needle))
	}
	if name == 'dpkg' {
		text := os.read_file('/var/lib/dpkg/status') or { return none }
		// dpkg counts "install ok installed" status lines
		return u64(text.count(dpkg_needle))
	}
	if name == 'emerge' {
		// emerge grows a category/pkg tree under /var/db/pkg (two levels)
		categories := os.ls('/var/db/pkg') or { return none }
		mut count := 0
		for cat in categories {
			if cat.len == 0 || cat[0] == `.` {
				continue
			}
			pkg_dirs := os.ls('/var/db/pkg/${cat}') or { continue }
			for pkg in pkg_dirs {
				if pkg.len > 0 && pkg[0] != `.` {
					count++
				}
			}
		}
		if count == 0 {
			return none
		}
		return u64(count)
	}
	if name == 'eopkg' {
		return non_dot_entries('/var/lib/eopkg/package')
	}
	if name == 'pacman' {
		// pacman's local db is one directory per package; counting
		// non-dot entries avoids a stat per package.
		return non_dot_entries('/var/lib/pacman/local')
	}
	if name == 'pkgtool' {
		// pkgtool keeps one file per package in /var/log/packages
		return non_dot_entries('/var/log/packages')
	}
	if name == 'xbps' {
		// xbps finds the pkgdb-<system> file inside /var/db/xbps
		entries := os.ls('/var/db/xbps') or { return none }
		mut db_path := ''
		for entry in entries {
			if entry.starts_with('pkgdb-') {
				db_path = '/var/db/xbps/${entry}'
				break
			}
		}
		if db_path.len == 0 {
			return none
		}
		text := os.read_file(db_path) or { return none }
		return u64(text.count(xbps_needle))
	}
	return none
}

// non_dot_entries counts entries without a leading dot; none marks a
// directory that will not open — kept apart from a clean zero, as the
// C and zig versions keep it.
@[direct_array_access]
fn non_dot_entries(path string) ?u64 {
	entries := os.ls(path) or { return none }
	mut count := 0
	for entry in entries {
		if entry.len > 0 && entry[0] != `.` {
			count++
		}
	}
	return u64(count)
}
