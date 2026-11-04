// hello_world_d module — a D sample for divifetch-zig.
//
// a D module lives beside its module.lip and is built to an object with
// dmd before the zig link. by default its recipe is -betterC: no druntime,
// no phobos, nothing linked unless the lip's :deps says so — this preset
// only borrows C's stdio, so the lip names :deps [:c]. a module using the
// D standard library spells :deps [:std] instead, which compiles without
// -betterC and rides phobos and druntime on the link.
//
// the ABI is the old generator's own: write into the buffer passed and
// return it — or null for the shim's "?".
import core.stdc.stdio : snprintf;

extern(C) char* hello_world_d_module_preset(char* result, int result_size) nothrow {
    snprintf(result, result_size, "Hello, World! (from D)");
    return result;
}
