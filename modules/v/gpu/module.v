// gpu module: GPUs via /sys/class/drm card devices, the zig module's
// read. zero spawn: each card's vendor id and the DRIVER= line of its
// uevent, with a product_name override when a driver exposes one (some
// amdgpu setups do). a full vendor:device -> marketing-name table stays
// out — divifetch doesn't embed databases. up to three cards, "; "-
// joined. no drm tree (the BSDs) answers '?', as the zig one does.
// macOS walks IOKit's IOAccelerator entries through the darwin helper,
// fastfetch's gpu_apple.c: the entry's "model" (its parent's for GPUs
// that keep it there) and Apple silicon's "gpu-core-count".
module gpu

import os
import strconv

struct Vendor {
	id   u16
	name string
}

const vendors = [
	Vendor{
		id:   0x1002
		name: 'AMD'
	},
	Vendor{
		id:   0x1022
		name: 'AMD'
	},
	Vendor{
		id:   0x10de
		name: 'NVIDIA'
	},
	Vendor{
		id:   0x8086
		name: 'Intel'
	},
	Vendor{
		id:   0x1af4
		name: 'virtio'
	},
	Vendor{
		id:   0x15ad
		name: 'VMware'
	},
	Vendor{
		id:   0x1b36
		name: 'QEMU'
	},
]

@[direct_array_access]
pub fn preset() string {
	$if macos {
		return macos_gpus()
	}
	entries := os.ls('/sys/class/drm') or { return '?' }
	mut parts := []string{}
	for entry in entries {
		// card devices only, not "card0-DP-1" connectors
		if !entry.starts_with('card') || entry.contains('-') {
			continue
		}
		dev := '/sys/class/drm/${entry}/device'

		// vendor id: "0x8086" — base 0 reads the prefix, zig's parseInt(u16, _, 0)
		vraw := first_line(os.read_file('${dev}/vendor') or { continue })
		vid := strconv.parse_uint(vraw, 0, 16) or { continue }
		vname := vendor_name(u16(vid))
		if vname.len == 0 {
			continue
		}

		// driver name via the DRIVER= line of the device uevent
		mut dname := ''
		if uevent := os.read_file('${dev}/uevent') {
			for line in uevent.split('\n') {
				if line.starts_with('DRIVER=') {
					dname = line['DRIVER='.len..].trim_right(' \t\r')
					break
				}
			}
		}

		// product_name override, when the driver exposes one
		mut pname := ''
		if product := os.read_file('${dev}/product_name') {
			pname = first_line(product).trim(' \t')
		}

		tail := if pname.len != 0 { pname } else { dname }
		parts << if tail.len != 0 { '${vname} (${tail})' } else { vname }
		if parts.len >= 3 {
			break
		}
	}
	if parts.len == 0 {
		return '?'
	}
	return parts.join('; ')
}

@[direct_array_access]
fn vendor_name(id u16) string {
	for v in vendors {
		if v.id == id {
			return v.name
		}
	}
	return ''
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
