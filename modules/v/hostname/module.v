// hostname module: nodename from uname(2). os.uname() rides libc's call
// on every target the fetch compiles for, so this one answer holds linux
// and the BSDs alike.
module hostname

import os

@[direct_array_access]
pub fn preset() string {
	name := os.uname().nodename
	if name.len == 0 {
		return '?'
	}
	return name
}
