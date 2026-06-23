#ifndef MODULE_TERMINAL_H
#define MODULE_TERMINAL_H
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <stdio.h>
#include <stdbool.h>
const char *terminal_module_preset(char *buf, size_t buf_size);
#endif
