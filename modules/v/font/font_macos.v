// font's macOS half (Terminal.app, iTerm2): compiled for macOS targets
// only, so the darwin helper never reaches a linux link.
module font

import darwin
import os

// font_with_size prints fastfetch's "Name (12pt)"; a fractional size
// keeps one decimal.
fn font_with_size(name string, size f64) string {
	if size <= 0 {
		return name
	}
	whole := i64(size)
	if f64(whole) == size {
		return '${name} (${whole}pt)'
	}
	return '${name} (${size:.1f}pt)'
}

// apple_terminal_font reads the default profile's archived NSFont: the
// archive's $top.root object holds NSSize and an NSName reference into
// $objects. A profile without a Font key (Terminal's built-in default)
// answers none.
fn apple_terminal_font() ?string {
	app := 'com.apple.Terminal'
	name_ref := darwin.pref('Default Window Settings', app)
	defer {
		darwin.release(name_ref)
	}
	profile := darwin.to_string(name_ref) or { return none }
	settings := darwin.pref('Window Settings', app)
	defer {
		darwin.release(settings)
	}
	font_data := darwin.dict_get(darwin.dict_get(settings, profile), 'Font')
	archive := darwin.plist_from_data(font_data)
	if archive == unsafe { nil } {
		return none
	}
	defer {
		darwin.release(archive)
	}
	objects := darwin.dict_get(archive, '\$objects')
	count := darwin.array_count(objects)
	top := darwin.dict_get(archive, '\$top')
	root_idx := darwin.uid_value(darwin.dict_get(top, 'root')) or { return none }
	if i64(root_idx) >= count {
		return none
	}
	root := darwin.array_at(objects, i64(root_idx))
	name_idx := darwin.uid_value(darwin.dict_get(root, 'NSName')) or { return none }
	if i64(name_idx) >= count {
		return none
	}
	name := darwin.to_string(darwin.array_at(objects, i64(name_idx))) or { return none }
	size := darwin.number_f64(darwin.dict_get(root, 'NSSize')) or { 0.0 }
	return font_with_size(name, size)
}

// iterm2_font finds the running profile's bookmark (fastfetch's
// detectIterm2); "Monaco 12" splits at its last space into name + size.
fn iterm2_font() ?string {
	profile := os.getenv_opt('ITERM_PROFILE') or { return none }
	bookmarks := darwin.pref('New Bookmarks', 'com.googlecode.iterm2')
	defer {
		darwin.release(bookmarks)
	}
	for i in 0 .. darwin.array_count(bookmarks) {
		bookmark := darwin.array_at(bookmarks, i)
		if (darwin.dict_string(bookmark, 'Name') or { '' }) != profile {
			continue
		}
		spec := darwin.dict_string(bookmark, 'Normal Font') or { return none }
		cut := spec.last_index(' ') or { return spec }
		size := spec[cut + 1..].f64()
		if size <= 0 {
			return spec
		}
		return font_with_size(spec[..cut], size)
	}
	return none
}
