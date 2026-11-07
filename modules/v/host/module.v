// host module: the machine model from DMI — product_name, with
// board_name as its fallback, both one trimmed line off sysfs. zero
// spawn. the openbsd branch answers hw.product/hw.vendor through the
// zig sysctl helper; a bare freebsd falls through the same DMI path
// and answers '?' where sysfs is absent, which the linux path does.
// macOS answers hw.model ("MacBookPro18,3").
module host

import os

@[direct_array_access]
pub fn preset() string {
	// the openbsd side rides openbsd.zig's hwStr helpers; the V port
	// answers '?' until a V helper lands.
	$if openbsd {
		return '?'
	}
	$if macos {
		model := sysctl_str('hw.model').trim(' \t')
		return if model.len != 0 { model } else { '?' }
	}

	product := dmi_value('/sys/devices/virtual/dmi/id/product_name')
	if product.len != 0 {
		return product
	}
	board := dmi_value('/sys/devices/virtual/dmi/id/board_name')
	if board.len != 0 {
		return board
	}
	return '?'
}

// dmi_value reads one trimmed DMI line; an unread or empty file stays
// '', so the fallback takes its turn like the zig readFirstLine + trim.
@[direct_array_access]
fn dmi_value(path string) string {
	line := first_line(os.read_file(path) or { return '' })
	return line.trim(' \t')
}

// first_line cuts the head line of a text payload without the line
// ending — the zig util's readFirstLine, on a payload already read.
@[direct_array_access]
fn first_line(s string) string {
	nl := s.index_u8(`\n`)
	mut line := if nl >= 0 { s[0..nl] } else { s }
	for line.len > 0 && line[line.len - 1] == `\r` {
		line = line[0..line.len - 1]
	}
	return line
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
