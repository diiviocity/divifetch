# the no-libc example

divifetch-zig under (build :flags ...) spelling -Dtarget=x86_64-linux-none
keeps the zig std on raw syscalls, and the rust no_std module
(hello_world_rustix_nostd) carries its own panic handler, so the whole fetch
compiles with no libc — ldd answers `not a dynamic executable`.

then, from this dir:

```
v run generator -S -B -s config.lip
v run build.vsh build
./target/divifetch
ldd target/divifetch
```

the fuzzy bits sit in the samples: modules/hello_world_rustix_nostd (the :ext
rustix spelling with no-default-features and the two no_std marks
module.rs carries) and build.conf beside this file (the none target
spelling in :flags).
