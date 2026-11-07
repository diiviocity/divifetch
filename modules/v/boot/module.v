// boot module: UEFI vs BIOS, via the presence of efivars. the zig
// module keeps "BIOS" for a clean ENOENT and answers '?' off every
// other error; V's os.is_dir answers a bare bool, so an unread efivars
// (EACCES exotica) rides BIOS here instead of polling the errno.
// macOS has one firmware per architecture and nothing to probe: Intel
// Macs boot Apple's EFI, Apple silicon boots iBoot.
module boot

import os

@[direct_array_access]
pub fn preset() string {
	$if macos {
		$if arm64 {
			return 'iBoot'
		}
		return 'UEFI'
	}
	if os.is_dir('/sys/firmware/efi/efivars') {
		return 'UEFI'
	}
	return 'BIOS'
}
