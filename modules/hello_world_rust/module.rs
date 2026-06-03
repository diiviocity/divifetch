use std::ffi::c_char;
#[no_mangle]
pub extern "C" fn hello_world_rust_module_preset(result: *mut c_char, result_size: usize,) -> *const c_char {
    let text = "Hello, World!";
    unsafe {
        let n = text.len().min(result_size.saturating_sub(1));
        std::ptr::copy_nonoverlapping(text.as_ptr(), result as *mut u8, n);
        if result_size > 0 { *result.add(n) = 0; }
        result
    }
}
