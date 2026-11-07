// loadavg module: the first three fields of /proc/loadavg — the
// kernel's own load triple. the BSD targets read getloadavg(3) through
// the zig helpers (the kernel's f64 answer); the V port answers '?'
// there until a V helper lands. macOS answers getloadavg(3) from
// libSystem directly.
module loadavg

import os

@[direct_array_access]
pub fn preset() string {
	$if openbsd {
		return '?'
	}
	$if freebsd {
		return '?'
	}
	$if macos {
		mut avg := [3]f64{}
		if C.getloadavg(&avg[0], 3) != 3 {
			return '?'
		}
		return '${avg[0]:.2f} ${avg[1]:.2f} ${avg[2]:.2f}'
	}

	line := os.read_file('/proc/loadavg') or { return '?' }
	// "1.03 0.53 0.44 2/1867 417502" — the running/total and last pid
	// ride after the three averages
	mut fields := []string{}
	for part in line.split(' ') {
		if part.len == 0 {
			continue
		}
		fields << part
		if fields.len == 3 {
			break
		}
	}
	if fields.len < 3 {
		return '?'
	}
	return fields.join(' ')
}

fn C.getloadavg(loadavg &f64, nelem i32) i32
