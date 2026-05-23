char* kernel_module_preset(char* result, size_t result_size) {
    struct utsname buf;
    if (uname(&buf) != 0) { snprintf(result, result_size, "?"); return result; }
    snprintf(result, result_size, "%s", buf.release);
    return result;
}
