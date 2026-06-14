#include "includes/utils.h"
#include "includes/error.h"

bool is_present_in_vector(const std::vector<std::string>& vec, const std::string& target) {
    return std::find(vec.begin(), vec.end(), target) != vec.end();
}

void add_unique(std::vector<std::string>& vec, const std::string& target) {
    if (!is_present_in_vector(vec, target)) vec.push_back(target);
}

size_t utf8_display_width(const std::string& s) {
    size_t width = 0;
    size_t i = 0; 
    while (i < s.size()) {
        unsigned char c = (s[i]); 
        if (c == 0x1B && i + 1 < s.size() && s[i+1] == '[') {
            i += 2;
            while (i < s.size() && (s[i] < 0x40 || (s[i]) > 0x7E)) i++;
            i++;
        } else if (c == '\\' && i + 4 < s.size() && s[i+1] == '0' && s[i+2] == '3' && s[i+3] == '3' && s[i+4] == '[') {
            i += 5; 
            while (i < s.size() && (s[i] < 0x40 || (s[i]) > 0x7E)) i++;
            i++;
        } else if (c == '\\' && i + 3 < s.size() && s[i+1] == '0' && s[i+2] == '3' && s[i+3] == '3') {
            i += 4;
        } else {
            if ((c & 0x80) == 0) { width++; i++; }
            else if ((c & 0xE0) == 0xC0) { width++; i += 2; }
            else if ((c & 0xF0) == 0xE0) { width++; i += 3; }
            else if ((c & 0xF8) == 0xF0) { width++; i += 4; }
            else { i++; }
        }
    } 
    return width;
}

std::vector<std::string> parse_file_to_vector(std::string filename) {
    std::vector<std::string> text_lines;
    std::ifstream file(filename.c_str());
    if (!file.is_open()) { print_warning("couldn't open file '" + filename + "'"); return text_lines; }
    std::string current_line;
    while (std::getline(file, current_line)) text_lines.push_back(current_line);
    return text_lines;
}

std::string command_execution_output(const char* command_to_exec) {
    char buffer[128];
    std::string result;
    FILE* pipe = popen(command_to_exec, "r");
    if (!pipe) { return "?"; }
    while (fgets(buffer, sizeof(buffer), pipe) != NULL) { result += buffer; }
    pclose(pipe);
    while (!result.empty() && result[result.length() - 1] == '\n') 
        result.erase(result.length() - 1);
    return result;
}
