#include "module.h"
#include <cstdio>

extern "C"
const char *hello_world_cpp_module_preset(char *result, size_t result_size) {
    std::snprintf(result, result_size, "Hello, World!");
    return result;
}
