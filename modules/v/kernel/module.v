// kernel module: release string via uname(2), the way the zig module
// answers it. V's own os.uname() wraps the libc call cross-platform, so
// linux and the BSDs share one answer — no platform split to carry.
module kernel

import os

@[direct_array_access]
pub fn preset() string {
	// os.uname() fills Uname directly from libc; V treats a blank answer
	// with the '?' convention the rest of the fetch's modules keep.
	release := os.uname().release
	if release.len == 0 {
		return '?'
	}
	return release
}
