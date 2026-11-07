// mount module: statfs(2) on the entry's path, printed used / total in
// human units, computed from f_bfree like the zig module (bavail keeps
// out, df-style). vlib carries no statfs wrapper, so the kernel ABI
// struct and the libc prototype are declared here directly — zero
// deps, zero spawn.
module mount

// the x86_64 kernel's struct statfs layout: the BSD targets call libc's
// statvfs with each tree's own field order instead, so the linux build
// keeps the ABI struct to itself.
struct C.statfs {
	f_type    i64
	f_bsize   i64
	f_blocks  u64
	f_bfree   u64
	f_bavail  u64
	f_files   i64
	f_ffree   i64
	f_fsid    [2]i32
	f_namelen i64
	f_frsize  i64
	f_flags   i64
	f_spare   [4]i64
}

fn C.statfs(path &char, buf &C.statfs) int

struct FsStat {
	f_bsize  u64
	f_frsize u64
	f_blocks u64
	f_bfree  u64
}

// BfStatfsRaw matches the linux struct statfs layout; freestanding and -syscalls
// linux and freebsd builds resolve it through builtin's bf_statfs instead of libc (the
// freebsd runtime converts its own statfs into this layout).
$if (freestanding || syscalls) && (linux || freebsd) {
	struct BfStatfsRaw {
		f_type    i64
		f_bsize   i64
		f_blocks  u64
		f_bfree   u64
		f_bavail  u64
		f_files   i64
		f_ffree   i64
		f_fsid    [2]i32
		f_namelen i64
		f_frsize  i64
		f_flags   i64
		f_spare   [4]i64
	}
}

@[direct_array_access]
fn fs_stat(path string) ?FsStat {
	$if (freestanding || syscalls) && (linux || freebsd) {
		mut buf := BfStatfsRaw{}
		rc := unsafe { bf_statfs(path, &u8(voidptr(&buf))) }
		if rc != 0 {
			return none
		}
		return FsStat{
			f_bsize:  u64(buf.f_bsize)
			f_frsize: u64(buf.f_frsize)
			f_blocks: buf.f_blocks
			f_bfree:  buf.f_bfree
		}
	} $else $if macos {
		// darwin's statfs is its own 2168-byte layout (64-bit inodes; V
		// links statfs$INODE64 on x86_64): the headerless backend would
		// size the linux struct above, so a raw buffer takes the write
		// and the counters read at their offsets — f_bsize u32 at 0,
		// f_blocks u64 at 8, f_bfree u64 at 16. no f_frsize there.
		// freestanding builds bind statfs from libSystem too; that bare
		// symbol is the 64-bit-inode call only on arm64, so a freestanding
		// x86_64 build (which can't name statfs$INODE64) stays out.
		$if (freestanding || syscalls) && !arm64 {
			return none
		}
		mut raw := []u8{len: 2168}
		if C.statfs(&char(path.str), unsafe { &C.statfs(raw.data) }) != 0 {
			return none
		}
		return FsStat{
			f_bsize:  u64(le_u32(raw, 0))
			f_frsize: 0
			f_blocks: le_u64(raw, 8)
			f_bfree:  le_u64(raw, 16)
		}
	} $else $if freestanding || syscalls {
		// no bf_statfs on the other freestanding targets yet; `$else` keeps the
		// libc call below out of their link
		return none
	} $else {
		mut buf := C.statfs{}
		rc := C.statfs(&char(path.str), &buf)
		if rc != 0 {
			return none
		}
		return FsStat{
			f_bsize:  u64(buf.f_bsize)
			f_frsize: u64(buf.f_frsize)
			f_blocks: buf.f_blocks
			f_bfree:  buf.f_bfree
		}
	}
}

// human_size walks 1024-steps up to TiB with one decimal, the zig
// module's unit ladder verbatim.
@[direct_array_access]
fn human_size(bytes u64) string {
	units := [' B', ' KiB', ' MiB', ' GiB', ' TiB']
	mut size := f64(bytes)
	mut unit := 0
	for size >= 1024.0 && unit < units.len - 1 {
		size /= 1024.0
		unit++
	}
	return '${size:.1f}${units[unit]}'
}

@[direct_array_access]
pub fn preset(path string) string {
	// the BSDs statvfs through the zig openbsd/freebsd helpers; the hosted V
	// branch answers '?' until a V helper lands (freestanding freebsd has one).
	$if openbsd {
		return '?'
	}
	$if freebsd && !freestanding && !syscalls {
		return '?'
	}

	fs := fs_stat(path) or { return '?' }

	// f_blocks counts f_frsize units; f_bsize rides when a tree reports
	// no fragment size
	block_size := if fs.f_frsize != 0 { fs.f_frsize } else { fs.f_bsize }
	total := fs.f_blocks * block_size
	free_bytes := fs.f_bfree * block_size
	// a tree reporting bfree above its block count stays at zero
	used := if total > free_bytes { total - free_bytes } else { u64(0) }

	return '${human_size(used)} / ${human_size(total)}'
}

@[direct_array_access]
fn le_u32(b []u8, off int) u32 {
	return u32(b[off]) | (u32(b[off + 1]) << 8) | (u32(b[off + 2]) << 16) | (u32(b[off + 3]) << 24)
}

@[direct_array_access]
fn le_u64(b []u8, off int) u64 {
	return u64(le_u32(b, off)) | (u64(le_u32(b, off + 4)) << 32)
}
