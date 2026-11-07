// swap module: SwapTotal/SwapFree from /proc/meminfo, the memory
// module's used/total presentation. one wart stays faithful: the zig
// module names its figures KB yet sizes them through a single /1024
// pass under MiB and GiB captions, so a sub-MiB swap prints its raw
// kB count as "MiB" — a V answer ships the same shape. '?' when no
// swap rides. the BSD targets read their kernel swap counters, so
// the V port answers '?' there until a V helper lands. macOS answers
// vm.swapusage (struct xsw_usage: total, avail, used — u64 each), '?'
// while dynamic_pager has made no swapfile yet.
module swap

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
		raw := sysctl_bytes('vm.swapusage', 32) or { return '?' }
		if raw.len != 32 {
			return '?'
		}
		total := le_u64(raw, 0)
		if total == 0 {
			return '?'
		}
		mut used := le_u64(raw, 16)
		if used > total {
			used = total
		}
		used_mib := f64(used) / (1024.0 * 1024.0)
		total_mib := f64(total) / (1024.0 * 1024.0)
		if total_mib >= 1024.0 {
			return '${used_mib / 1024.0:.1f} GiB / ${total_mib / 1024.0:.1f} GiB'
		}
		return '${used_mib:.0f} MiB / ${total_mib:.0f} MiB'
	}

	content := os.read_file('/proc/meminfo') or { return '?' }

	mut total := u64(0)
	mut free_kib := u64(0)
	mut found := false
	for line in content.split_into_lines() {
		if line.starts_with('SwapTotal:') {
			total = mem_u64(line, 'SwapTotal:')
			found = true
		} else if line.starts_with('SwapFree:') {
			free_kib = mem_u64(line, 'SwapFree:')
		}
	}
	if !found || total == 0 {
		return '?'
	}

	// free is capped at total so a malformed file can't invert the pair
	mut free_capped := free_kib
	if free_capped > total {
		free_capped = total
	}
	used_raw := f64(total - free_capped)
	total_raw := f64(total)

	if total_raw >= 1024.0 {
		used_gib := used_raw / 1024.0
		total_gib := total_raw / 1024.0
		// zig's "{d:.1}" is fixed-point, ".1f" keeps the zero
		return '${used_gib:.1f} GiB / ${total_gib:.1f} GiB'
	}
	return '${used_raw:.0f} MiB / ${total_raw:.0f} MiB'
}

// mem_u64 answers the figure of one "Key:   N kB" meminfo line, 0 when
// the key misses or the figure does not parse — the strict parseInt
// reaches zig's catch-null, with no panic riding.
@[direct_array_access]
fn mem_u64(line string, key string) u64 {
	if !line.starts_with(key) {
		return 0
	}
	// "SwapTotal:  32871228 kB" — the figure ends at the first whitespace
	rest := line[key.len..].trim(' \t')
	mut end := rest.len
	for i, c in rest.bytes() {
		if c == ` ` || c == `\t` {
			end = i
			break
		}
	}
	tok := rest[0..end]
	if tok.len == 0 {
		return 0
	}
	for c in tok.bytes() {
		if c < `0` || c > `9` {
			// zig's u64 parseInt rejects a sign or any junk: unreadable
			return 0
		}
	}
	v := tok.i64()
	if v < 0 {
		return 0
	}
	return u64(v)
}

// the macOS reads ride libSystem's sysctlbyname; V's C backend is
// headerless, so the prototype rides here and every answer comes back
// as raw bytes read at the header's own offsets (modules/zig/macos.zig
// carries the same ABI facts, static-asserted against the darwin
// headers).
fn C.sysctlbyname(name &char, oldp voidptr, oldlenp &uint, newp voidptr, newlen uint) i32

// sysctl_bytes answers one named node's bytes, none when the node is
// absent or outgrows `size`.
@[direct_array_access]
fn sysctl_bytes(name string, size int) ?[]u8 {
	mut buf := []u8{len: size}
	mut n := uint(size)
	if unsafe { C.sysctlbyname(&char(name.str), buf.data, &n, nil, 0) } != 0 || n > uint(size) {
		return none
	}
	return buf[..int(n)]
}

@[direct_array_access]
fn le_u32(b []u8, off int) u32 {
	return u32(b[off]) | (u32(b[off + 1]) << 8) | (u32(b[off + 2]) << 16) | (u32(b[off + 3]) << 24)
}

@[direct_array_access]
fn le_u64(b []u8, off int) u64 {
	return u64(le_u32(b, off)) | (u64(le_u32(b, off + 4)) << 32)
}
