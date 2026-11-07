// os module: /etc/os-release's PRETTY_NAME, falling back to NAME=, and
// finally the bare word the boot started on — 'unknown' — the way the zig
// module walks its keys. os-release is one KEY=value line per fact.
// macOS keeps no os-release: kern.osproductversion answers the About
// window's version and the major names it, "macOS Sequoia 15.1".
module distro

import os

const keys = ['PRETTY_NAME=', 'NAME=']

@[direct_array_access]
pub fn preset() string {
	$if macos {
		mut version := sysctl_str('kern.osproductversion')
		if version.len == 0 {
			return 'macOS'
		}
		// the kernel shims the node by the SDK version the binary
		// records: a pre-11 SDK (or none) reads "10.16" on every release
		// since Big Sur. 10.16 never shipped, so the darwin release
		// (uname, unshimmed) names the major instead — 20..24 are 11..15,
		// from 25 the year-named ones run one ahead (25 is Tahoe, 26).
		// only the major survives: a darwin minor spans point releases.
		if version == '10.16' {
			darwin := os.uname().release.all_before('.').int()
			if darwin < 20 {
				return 'macOS'
			}
			version = if darwin >= 25 { '${darwin + 1}' } else { '${darwin - 9}' }
		}
		// Tahoe answers "16.x" to binaries linked against an older SDK;
		// the 26 it really is takes that 1's place (fastfetch #1809).
		if version.starts_with('16.') {
			version = '2' + version[1..]
		}
		name := codename(version)
		if name.len != 0 {
			return 'macOS ${name} ${version}'
		}
		return 'macOS ${version}'
	}
	text := os.read_file('/etc/os-release') or { return 'unknown' }
	for key in keys {
		for line in text.split_into_lines() {
			if !line.starts_with(key) {
				continue
			}
			mut quoted := line[key.len..].trim_space()
			// the value usually rides in quotes; strip them, keep spaces.
			if quoted.starts_with('"') && quoted.ends_with('"') && quoted.len >= 2 {
				quoted = quoted[1..quoted.len - 1]
			}
			if quoted.len > 0 {
				return quoted
			}
		}
	}
	return 'unknown'
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

// sysctl_str answers a named string node, NUL-trimmed; '' when absent.
@[direct_array_access]
fn sysctl_str(name string) string {
	raw := sysctl_bytes(name, 256) or { return '' }
	mut end := 0
	for end < raw.len && raw[end] != 0 {
		end++
	}
	return raw[..end].bytestr()
}

// codename spells a macOS version's marketing name — fastfetch's table
// (os_apple.m): 10.x keys off the minor, the rest off the major.
@[direct_array_access]
fn codename(version string) string {
	parts := version.split('.')
	major := parts[0].int()
	if major == 10 && parts.len > 1 {
		return match parts[1].int() {
			12 { 'Sierra' }
			13 { 'High Sierra' }
			14 { 'Mojave' }
			15 { 'Catalina' }
			16 { 'Big Sur' }
			else { '' }
		}
	}
	return match major {
		27 { 'Golden Gate' }
		26, 16 { 'Tahoe' }
		15 { 'Sequoia' }
		14 { 'Sonoma' }
		13 { 'Ventura' }
		12 { 'Monterey' }
		11 { 'Big Sur' }
		else { '' }
	}
}
