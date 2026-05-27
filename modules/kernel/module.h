#ifndef MODULE_KERNEL_H
#define MODULE_KERNEL_H
#include <sys/utsname.h>
#include <stddef.h>
#include <stdio.h>
const char *kernel_module_preset(char *buf, size_t buf_size);
#endif
