/* hello_world_c module — a C sample for divifetch-zig.
 *
 * a C module lives beside its module.lip and is compiled with the fetch
 * itself (the build script feeds module.c to zig). the preset follows the
 * old generator convention: write the output into the buffer the caller
 * passes and return a pointer to it, or a null pointer for "?".
 */
#include <stdio.h>

const char *hello_world_c_module_preset(char* result, size_t result_size) {
    snprintf(result, result_size, "Hello, World!");
    return result;
}
