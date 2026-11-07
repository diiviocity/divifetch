// cpu module: model name, core/thread count and cpu0's current
// frequency, all from /proc/cpuinfo plus cpufreq sysfs — the linux
// shape the zig module answers. the model's own static "@ 2.50GHz"
// gets cut so the live figure below is not doubled up. zero spawn.
// macOS answers machdep.cpu.brand_string + hw.ncpu + hw.cpufrequency
// (Intel only: Apple silicon publishes no frequency).
module cpu

import os

@[direct_array_access]
pub fn preset() string {
	// the BSDs answer hw.model/hw.ncpu/cpu speed through the zig
	// modules' sysctl helpers; the V branch answers '?' until a V
	// helper lands.
	$if openbsd {
		return '?'
	}
	$if freebsd {
		return '?'
	}
	$if macos {
		return macos_preset()
	}

	content := os.read_file('/proc/cpuinfo') or { return '?' }
	mut model := ''
	mut cores := 0
	for line in content.split_into_lines() {
		colon := line.index_u8(`:`)
		if colon < 0 {
			continue
		}
		key := line[0..colon].trim(' \t')
		val := line[colon + 1..].trim(' \t')
		if val.len == 0 {
			continue
		}
		if key == 'processor' {
			cores++
		} else if model.len == 0 && (key == 'model name' || key == 'Hardware') {
			// "model name\t: Intel Core i5-12400" (x86) or "Hardware:" (arm)
			model = val
		}
	}
	if model.len == 0 {
		return '?'
	}

	// "Intel(R) Core(TM) i5-7200U CPU @ 2.50GHz" — cut the model's own
	// static speed
	if at := model.index(' @ ') {
		model = model[0..at].trim(' \t')
	}

	// current frequency of the first core, if cpufreq exposes one
	khz := cpu0_freq_khz()
	if khz > 0 {
		ghz := f64(khz) / 1_000_000.0
		// zig's "{d:.2}" is fixed-point: ".2f" keeps the trailing zero
		two := '${ghz:.2f}'
		if cores != 0 {
			return '${model} (${cores}) @ ${two}GHz'
		}
		return '${model} @ ${two}GHz'
	}
	if cores != 0 {
		return '${model} (${cores})'
	}
	return model
}

// cpu0_freq_khz reads the sysfs kHz figure of the first core, -1 when
// the file or the parse says no — the strict-digit read zig's
// parseInt(u64) preserved.
@[direct_array_access]
fn cpu0_freq_khz() i64 {
	raw := os.read_file('/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq') or {
		return -1
	}
	tok := first_line(raw).trim(' \t')
	if tok.len == 0 {
		return -1
	}
	for c in tok.bytes() {
		if c < `0` || c > `9` {
			return -1
		}
	}
	return tok.i64()
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

// sysctl_int answers a named integer node at its own width (4 or 8
// bytes, little-endian on both macOS arches); -1 when absent.
@[direct_array_access]
fn sysctl_int(name string) i64 {
	raw := sysctl_bytes(name, 8) or { return -1 }
	if raw.len == 4 {
		return i64(i32(le_u32(raw, 0)))
	}
	if raw.len == 8 {
		return i64(le_u64(raw, 0))
	}
	return -1
}

@[direct_array_access]
fn le_u32(b []u8, off int) u32 {
	return u32(b[off]) | (u32(b[off + 1]) << 8) | (u32(b[off + 2]) << 16) | (u32(b[off + 3]) << 24)
}

@[direct_array_access]
fn le_u64(b []u8, off int) u64 {
	return u64(le_u32(b, off)) | (u64(le_u32(b, off + 4)) << 32)
}

@[direct_array_access]
fn macos_preset() string {
	mut model := sysctl_str('machdep.cpu.brand_string')
	if at := model.index(' @ ') {
		model = model[0..at]
	}
	model = model.trim(' \t')
	if model.len == 0 {
		return '?'
	}
	cores := sysctl_int('hw.ncpu')
	hz := sysctl_int('hw.cpufrequency')
	if hz > 0 {
		ghz := f64(hz) / 1_000_000_000.0
		two := '${ghz:.2f}'
		if cores > 0 {
			return '${model} (${cores}) @ ${two}GHz'
		}
		return '${model} @ ${two}GHz'
	}
	if cores > 0 {
		return '${model} (${cores})'
	}
	return model
}
