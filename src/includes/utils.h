#ifndef DIVIFETCH_UTILS_H

#include <vector>
#include <string>
#include <fstream>
#include <algorithm>

bool is_present_in_vector(const std::vector<std::string>& vec, const std::string& target);
void add_unique(std::vector<std::string>& vec, const std::string& target);
size_t utf8_display_width(const std::string& s);
std::vector<std::string> parse_file_to_vector(std::string filename);
std::string command_execution_output(const char* command_to_exec);

#endif
