// memory module: parses /proc/meminfo and prints used / total.
// MemAvailable outranks the old kernels' rebuilt estimate — free +
// buffers + cached + s_reclaimable, Shmem taken out, values saturated,
// the zig module's arithmetic — and the pair prints in MiB until a
// GiB's worth rides in. the BSD targets answer their kernels' page
// counters; the V port answers '?' there until a V helper lands. macOS
// answers hw.memsize + host_statistics64, fastfetch's arithmetic.
module memory

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
		return macos_preset()
	}

	content := os.read_file('/proc/meminfo') or { return '?' }

	mut total := u64(0)
	mut available := u64(0)
	mut free_kib := u64(0)
	mut buffers := u64(0)
	mut cached := u64(0)
	mut shmem := u64(0)
	mut s_reclaimable := u64(0)
	mut found := false
	for line in content.split_into_lines() {
		if line.starts_with('MemTotal:') {
			total = mem_u64(line, 'MemTotal:')
			found = true
		} else if line.starts_with('MemAvailable:') {
			available = mem_u64(line, 'MemAvailable:')
		} else if line.starts_with('MemFree:') {
			free_kib = mem_u64(line, 'MemFree:')
		} else if line.starts_with('Buffers:') {
			buffers = mem_u64(line, 'Buffers:')
		} else if line.starts_with('Cached:') {
			cached = mem_u64(line, 'Cached:')
		} else if line.starts_with('Shmem:') {
			shmem = mem_u64(line, 'Shmem:')
		} else if line.starts_with('SReclaimable:') {
			s_reclaimable = mem_u64(line, 'SReclaimable:')
		}
	}
	if !found {
		return '?'
	}

	// old kernels lack MemAvailable: rebuild it the way the C module
	// did, with saturation so a malformed file can't wrap around
	if available == 0 || available >= total {
		mut rebuilt := free_kib + buffers + cached + s_reclaimable
		if rebuilt >= shmem {
			rebuilt -= shmem
		} else {
			rebuilt = 0
		}
		if rebuilt > total {
			rebuilt = total
		}
		available = rebuilt
	}

	used_mib := f64(total - available) / 1024.0
	total_mib := f64(total) / 1024.0
	if total_mib >= 1024.0 {
		used_gib := used_mib / 1024.0
		total_gib := total_mib / 1024.0
		// zig's "{d:.1}" is fixed-point, ".1f" keeps the zero
		return '${used_gib:.1f} GiB / ${total_gib:.1f} GiB'
	}
	return '${used_mib:.0f} MiB / ${total_mib:.0f} MiB'
}

// mem_u64 answers the figure of one "Key:   N kB" meminfo line, 0 when
// the key misses or the figure does not parse — the strict parseInt
// reaches zig's catch-null, with no panic riding.
@[direct_array_access]
fn mem_u64(line string, key string) u64 {
	if !line.starts_with(key) {
		return 0
	}
	// "MemTotal:  32871228 kB" — the figure ends at the first whitespace
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

fn C.mach_host_self() u32
fn C.host_page_size(host u32, out &uint) i32
fn C.host_statistics64(host u32, flavor i32, info voidptr, count &u32) i32

// macos_preset: the truly free pages (free less the speculative
// read-ahead vm_stat counts apart) plus the file-backed cache are what's
// not used (fastfetch memory_apple.c). vm_statistics64 grew over the
// years; the rev0 count of 38 ints (152 bytes) is what every kernel
// answers: free_count at 0, speculative_count at 92, external at 136.
@[direct_array_access]
fn macos_preset() string {
	total_raw := sysctl_bytes('hw.memsize', 8) or { return '?' }
	if total_raw.len != 8 {
		return '?'
	}
	total := le_u64(total_raw, 0)
	if total == 0 {
		return '?'
	}
	host := C.mach_host_self()
	mut vm := []u8{len: 152}
	mut count := u32(38)
	if C.host_statistics64(host, 4, vm.data, &count) != 0 || count < 38 { // HOST_VM_INFO64
		return '?'
	}
	// the kernel's page size (16K on arm64), vm_stat(1)'s own unit
	mut page := uint(0)
	if C.host_page_size(host, &page) != 0 || page == 0 {
		page = 4096
	}
	free_count := u64(le_u32(vm, 0))
	speculative := u64(le_u32(vm, 92))
	external := u64(le_u32(vm, 136))
	free_pages := if free_count > speculative { free_count - speculative } else { u64(0) }
	spare := (free_pages + external) * u64(page)
	used := if total > spare { total - spare } else { u64(0) }

	used_mib := f64(used) / (1024.0 * 1024.0)
	total_mib := f64(total) / (1024.0 * 1024.0)
	if total_mib >= 1024.0 {
		return '${used_mib / 1024.0:.1f} GiB / ${total_mib / 1024.0:.1f} GiB'
	}
	return '${used_mib:.0f} MiB / ${total_mib:.0f} MiB'
}
