#ifndef MODULE_MOUNT_H
#define MODULE_MOUNT_H
#include <sys/statvfs.h>
#include <stddef.h>
#include <stdio.h>
const char *mount_module_preset(const char *path, char *buf, size_t buf_size);
#endif
