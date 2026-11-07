// temp module: the first thermal sensor under /sys/class/hwmon,
// printed "<n>°C (chip)" with the chip's name file as the label — no
// chip name rides bare. the degree rounds half-up (millidegrees + 500,
// truncated), the zig @divTrunc shape. the freebsd branch answers
// dev.cpu.0.temperature through freebsd.zig helpers; the V port
// answers '?' there until a V helper lands. macOS reads the SMC's CPU
// core sensors through the darwin helper — fastfetch's cpu_apple.c +
// smc_temps.c: the key set by chip generation, readings outside
// 10..120 dropped, the rest averaged — printed "<n>°C (CPU)".
module temp

import os

@[direct_array_access]
pub fn preset() string {
	$if freebsd {
		return '?'
	}
	$if macos {
		return macos_temp()
	}

	entries := os.ls('/sys/class/hwmon') or { return '?' }
	for entry in entries {
		if !entry.starts_with('hwmon') {
			continue
		}
		// chip label off the "name" file (coretemp, amdgpu, ...)
		mut chip := ''
		name_raw := os.read_file('/sys/class/hwmon/${entry}/name') or { '' }
		if name_raw.len > 0 {
			chip = first_line(name_raw).trim(' \t')
		}

		// the first tempN_input file of this chip, millidegrees Celsius
		files := os.ls('/sys/class/hwmon/${entry}') or { continue }
		for file in files {
			if !file.starts_with('temp') || !file.ends_with('_input') {
				continue
			}
			raw := os.read_file('/sys/class/hwmon/${entry}/${file}') or { continue }
			tok := first_line(raw).trim(' \t')
			if tok.len == 0 {
				continue
			}
			// strict digits, the zig parseInt shape: a junk file leaves
			// the next sensor file its turn
			mut digits := true
			for c in tok.bytes() {
				if c < `0` || c > `9` {
					digits = false
					break
				}
			}
			if !digits {
				continue
			}
			milli := tok.i64()
			if milli < 0 {
				continue
			}
			// nearest degree: (milli + 500) trunc-div 1000
			celsius := (milli + 500) / 1000
			if chip.len != 0 {
				return '${celsius}°C (${chip})'
			}
			return '${celsius}°C'
		}
	}
	return '?'
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
