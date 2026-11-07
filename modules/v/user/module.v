// user module: $USER, falling back to $LOGNAME. always set on normal
// setups; '?' keeps the module honest for stripped environments. a V
// module reads the environment itself — os.getenv_opt answers none
// without any runtime context riding the signature.
module user

import os

@[direct_array_access]
pub fn preset() string {
	for name in ['USER', 'LOGNAME'] {
		val := os.getenv_opt(name) or { continue }
		if val.len > 0 {
			return val
		}
	}
	return '?'
}
