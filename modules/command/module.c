char* command_module_preset(const char* command_to_exec, char* result, size_t result_size) {
    FILE* pipe = popen(command_to_exec, "r");
    if (!pipe) {
        snprintf(result, result_size, "?");
        return result;
    }
    size_t pos = 0;
    char buf[128];
    while (fgets(buf, sizeof(buf), pipe) != NULL) {
        size_t n = strlen(buf);
        if (pos + n < result_size - 1) {
            memcpy(result + pos, buf, n);
            pos += n;
        }
    }
    result[pos] = '\0';
    pclose(pipe);
    while (pos > 0 && result[pos - 1] == '\n') {
        result[--pos] = '\0';
    }
    return result;
}
