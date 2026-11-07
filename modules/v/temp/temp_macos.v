// temp's macOS half: compiled for macOS targets only, so the darwin
// helper's frameworks and sysctlbyname never reach a linux link.
module temp

import darwin

// SMC CPU core keys per chip generation (fastfetch smc_temps.c, after
// exelban/stats' values.swift); Intel Macs read the diode/proximity set.
// When none of a table's keys exist, macos_temp probes the Tp<n>a/b,
// Te<n>a/b names a newer M1 firmware uses.
const smc_cpu_x64 = ['TC0D', 'TC0E', 'TC0F', 'TC0P']
const smc_cpu_m1 = ['Tp09', 'Tp0T', 'Tp01', 'Tp05', 'Tp0D', 'Tp0H', 'Tp0L', 'Tp0P', 'Tp0X', 'Tp0b']
const smc_cpu_m2 = ['Tp1h', 'Tp1t', 'Tp1p', 'Tp1l', 'Tp01', 'Tp05', 'Tp09', 'Tp0D', 'Tp0X', 'Tp0b',
	'Tp0f', 'Tp0j']
const smc_cpu_m3 = ['Te05', 'Te0L', 'Te0P', 'Te0S', 'Tf04', 'Tf09', 'Tf0A', 'Tf0B', 'Tf0D', 'Tf0E',
	'Tf44', 'Tf49', 'Tf4A', 'Tf4B', 'Tf4D', 'Tf4E']
const smc_cpu_m4 = ['Te05', 'Te0S', 'Te09', 'Te0H', 'Tp01', 'Tp05', 'Tp09', 'Tp0D', 'Tp0V', 'Tp0Y',
	'Tp0b', 'Tp0e']
const smc_cpu_m5 = ['Tp00', 'Tp04', 'Tp08', 'Tp0C', 'Tp0G', 'Tp0K', 'Tp0O', 'Tp0R', 'Tp0U', 'Tp0X',
	'Tp0a', 'Tp0d', 'Tp0g', 'Tp0j', 'Tp0m', 'Tp0p', 'Tp0u', 'Tp0y']

// smc_cpu_keys picks the key set from the brand string: "Apple M<n>..."
// by generation, anything else (Intel) the x64 set; an unknown Apple
// generation has none, as in fastfetch.
fn smc_cpu_keys(brand string) []string {
	if !brand.starts_with('Apple M') {
		return smc_cpu_x64
	}
	rest := brand['Apple M'.len..]
	mut gen := 0
	for c in rest.bytes() {
		if c < `0` || c > `9` {
			break
		}
		gen = gen * 10 + int(c - `0`)
	}
	return match gen {
		1 { smc_cpu_m1 }
		2 { smc_cpu_m2 }
		3 { smc_cpu_m3 }
		4 { smc_cpu_m4 }
		5 { smc_cpu_m5 }
		else { []string{} }
	}
}

fn macos_temp() string {
	brand := darwin.sysctl_string('machdep.cpu.brand_string') or { '' }
	keys := smc_cpu_keys(brand)
	if keys.len == 0 {
		return '?'
	}
	smc := darwin.smc_open() or { return '?' }
	defer {
		smc.close()
	}
	mut sum := 0.0
	mut count := 0
	for key in keys {
		t := smc.read(key) or { continue }
		if t < 10.0 || t > 120.0 {
			continue
		}
		sum += t
		count++
	}
	if count == 0 {
		// the table names aren't on this SMC: an M1 on Sonoma answers 0x84
		// "no such key" for all of them and names its CPU sensors
		// Tp<n><a|b|x|z> / Te<n><...> instead (listed off a MacBookPro17,1).
		// probe that pattern directly, a/b only (x/z read as peaks) — ~40
		// cheap lookups, where walking the SMC's 1600-odd keys took 300 ms.
		for prefix in ['Tp', 'Te'] {
			for digit in 0 .. 10 {
				for suffix in ['a', 'b'] {
					key := '${prefix}${digit}${suffix}'
					t := smc.read(key) or { continue }
					if t < 10.0 || t > 120.0 {
						continue
					}
					sum += t
					count++
				}
			}
		}
	}
	if count == 0 {
		return '?'
	}
	// nearest degree, as the hwmon branch rounds its millidegrees
	celsius := i64(sum / f64(count) + 0.5)
	return '${celsius}°C (CPU)'
}
