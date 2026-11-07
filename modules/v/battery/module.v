// battery module: capacity + status of the first BAT* power supply, the
// linux read the zig module walks. the first BAT* that answers both files
// wins; '?' when none does. macOS asks IOKit's power sources through the
// darwin helper — modules/zig/macos.zig's battery(), same words.
module battery

import os

@[direct_array_access]
pub fn preset() string {
	$if macos {
		return macos_battery()
	}
	supplies := os.ls('/sys/class/power_supply') or { return '?' }
	for entry in supplies {
		if !entry.starts_with('BAT') {
			continue
		}
		cap_path := '/sys/class/power_supply/${entry}/capacity'
		cap := os.read_file(cap_path) or { continue }
		capped := cap.trim_space()
		if capped.len == 0 {
			continue
		}
		status_path := '/sys/class/power_supply/${entry}/status'
		// a status file may read empty on stubborn firmwares; 'Unknown'
		// keeps the line keyed, like the zig module answers.
		status := os.read_file(status_path) or { return '${capped}% (Unknown)' }
		spelled := status.trim_space()
		return '${capped}% (${spelled})'
	}
	return '?'
}
