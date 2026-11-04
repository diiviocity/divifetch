// hello_world_rustix module — the extern-deps rust sample for divifetch-zig.
//
// a module that names :ext crates in :deps rides cargo for the build: the
// generator lays a crate project under .imp/extcrate whose lib is this
// very file, whose [dependencies] are the spellings, and whose release
// profile pins panic=abort. the build script runs `cargo build --release`
// and zig links the staticlib archive beside its own sources; std, the
// crates' bodies and the preset all ride the archive, so the link takes
// libc and libunwind — :std answers libc, and the :ext entry adds
// libunwind for the stable toolchain's std.
#[no_mangle]
pub extern "C" fn hello_world_rustix_module_preset(buf: *mut u8, buf_size: usize) -> *const u8 {
	let u = rustix::system::uname();
	let s = format!(
		"Hello, World! ({}, from rustix {})",
		u.sysname().to_string_lossy(),
		u.release().to_string_lossy()
	);
	let len = s.len().min(buf_size);
	unsafe {
		std::ptr::copy(s.as_ptr(), buf, len);
		if len < buf_size {
			*buf.add(len) = 0;
		}
	}
	buf as *const u8
}
