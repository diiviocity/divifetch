// battery's macOS half: compiled for macOS targets only, so the darwin
// helper never reaches a linux link.
module battery

import darwin

fn macos_battery() string {
	bat := darwin.battery() or { return '?' }
	return '${bat.percent}% (${bat.status})'
}
