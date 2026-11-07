// gpu's macOS half: compiled for macOS targets only, so the darwin
// helper never reaches a linux link.
module gpu

import darwin

// macos_gpus answers "Apple M1 (8 cores)"-style names, up to three,
// "; "-joined like the drm walk. every entry and table is released.
fn macos_gpus() string {
	dict := darwin.matching('IOAccelerator')
	category := darwin.cfstr('IOAccelerator')
	darwin.dict_add(dict, 'IOMatchCategory', category)
	darwin.release(category)
	mut parts := []string{}
	for entry in darwin.services(dict) {
		props := darwin.properties(entry)
		mut name := darwin.dict_string(props, 'model') or { '' }
		cores := darwin.dict_i64(props, 'gpu-core-count') or { 0 }
		darwin.release(props)
		if name.len == 0 {
			up := darwin.parent(entry)
			up_props := darwin.properties(up)
			name = darwin.dict_string(up_props, 'model') or { '' }
			darwin.release(up_props)
			darwin.io_release(up)
		}
		darwin.io_release(entry)
		if name.len == 0 || parts.len >= 3 {
			continue
		}
		parts << if cores > 0 { '${name} (${cores} cores)' } else { name }
	}
	if parts.len == 0 {
		return '?'
	}
	return parts.join('; ')
}
