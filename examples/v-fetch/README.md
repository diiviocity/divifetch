# the v-fetch example

the V backend, all the way out: one config, one generated V program.
runtime entries ride the module presets compiled into .tmp/vfetch/run.v
(the build script symlinks each modules/v/<kind> dir beside the source so
the imports resolve, then runs `v -prod -o target/divifetch .tmp/vfetch`),
the hello_world_v script bakes once through the v_bakes steps into
bake.v, and the build holds no zig anywhere.

```shell
# from this directory:
v run generator -S -B   # or v run generator for the default task
v run build.vsh build
./target/divifetch
```

the v_backend rules the generator enforces — visible in the rest of the
tree as checks and errors, spelled here once:

- runtime V entries and runtime zig/compiled ones never share a config:
  the fetch compiles as one language or the other, never both
- a V build-time entry bakes through the build script's v_bakes steps;
  a zig or compiled-language one through headgen — the two bake shapes
  never share a config either
- a V module kind may not carry a stdlib module's name: the compiler
  resolves sibling dirs first, so an `os` kind would shadow every
  sibling's `import os` — the distro kind answers the os-release line
- BSD answers ride '?': the V prefixes keep the linux reads; the zig
  tree carries the full openbsd/freebsd rolled helpers

swap prints '?' here — the machine the example ran on has no swap.
