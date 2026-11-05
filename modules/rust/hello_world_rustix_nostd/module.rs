// hello_world_rustix_nostd module — the no-libc rust sample for divifetch-zig.
//
// rustix with no-default-features is the no_std move: raw syscall
// interfaces, no druntime-flavored std, nothing referencing the libc or
// thread libs during the run. the crate project the generator lays beside
// module.rs pins panic="abort", the archive stays clean of std's backtrace
// branches, and the zig link takes no flags: with (build :flags ...
// "-Dtarget=x86_64-linux-none") the whole fetch compiles to a static
// binary — ldd answers: not a dynamic executable.
//
// a no_std crate carries two marks below: the panic handler the compiler
// wants from us, and an empty rust_eh_personality the prebuilt compiler
// builtins leave a data pointer to — under panic=abort the personality
// never enters, and one empty stub closes the link.
#![no_std]

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[no_mangle]
pub extern "C" fn rust_eh_personality() {}

#[no_mangle]
pub extern "C" fn hello_world_rustix_nostd_module_preset(buf: *mut u8, buf_size: usize) -> *const u8 {
    let u = rustix::system::uname();
    let mut out: [u8; 80] = [0; 80];
    let sys = u.sysname().to_bytes();
    let rel = u.release().to_bytes();
    let mut i = 0usize;
    for b in sys.iter().chain(b" (from rustix no_std)".iter()).chain(rel.iter()) {
        if i >= out.len() - 1 {
            break;
        }
        out[i] = *b;
        i += 1;
    }
    let mut j = 0usize;
    while j < i && j < buf_size {
        unsafe {
            *buf.add(j) = out[j];
        }
        j += 1;
    }
    if j < buf_size {
        unsafe {
            *buf.add(j) = 0;
        }
    }
    buf as *const u8
}
