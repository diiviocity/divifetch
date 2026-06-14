#include "includes/error.h"

void print_error(const std::string &error_text) {
    std::cerr << "\033[31m\033[1merror:\033[0m " << error_text << "\n";
    std::exit(1);
}

void print_warning(const std::string &warning_text) {
    std::cerr << "\033[33m\033[1mwarning:\033[0m " << warning_text << "\n";
}
