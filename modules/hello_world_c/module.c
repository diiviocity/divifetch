#include "module.h"
#include <stdio.h>
const char *hello_world_c_module_preset(char *result, size_t result_size) {
    snprintf(result, result_size, "Hello, World!");
    return result;
}
