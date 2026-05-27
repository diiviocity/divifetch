#ifndef MODULE_SHELL_H
#define MODULE_SHELL_H
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <stdio.h>
const char *shell_module_preset(char *buf, size_t buf_size);
#endif
