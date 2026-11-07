// locale module: $LC_ALL, falling back to $LANG.
module locale

import os

@[direct_array_access]
pub fn preset() string {
	for name in ['LC_ALL', 'LANG'] {
		val := os.getenv_opt(name) or { continue }
		if val.len > 0 {
			return val
		}
	}
	return '?'
}
