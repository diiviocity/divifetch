// hello_world_cpp module — a C++ sample for divifetch-zig.
//
// a C++ module does what a C one does: the build script feeds module.cpp to
// zig along with run.zig, and the shim reaches the exported preset through
// a module-owned buffer sized by the config's :buffer-size. C++ sources
// join the symbol manually, so the preset is wrapped in extern "C" here.
#include <cstdio>

extern "C" const char* hello_world_cpp_module_preset(char* result, size_t result_size) {
    snprintf(result, result_size, "Hello, World++!");
    return result;
}
