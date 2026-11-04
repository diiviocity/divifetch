// hello_world_rust module — a Rust sample for divifetch-zig.
//
// a Rust module is built once per fetch as a static library (rustc
// --crate-type=staticlib), and the object links beside the zig sources.
// the preset copies into the caller's buffer and returns it, null kept for
// the "?" convention — and the no_mangle + extern "C" decl carries the ABI.
#[no_mangle]
pub extern "C" fn hello_world_rust_module_preset(buf: *mut u8, buf_size: usize) -> *const i8 {
	let text = b"Hello, World! (rust)";
	let mut i = 0usize;
	while i < text.len() && i < buf_size {
		unsafe {
			*buf.add(i) = text[i];
		}
		i += 1;
	}
	if i < buf_size {
		unsafe {
			*buf.add(i) = 0;
		}
	}
	buf as *const i8
}
