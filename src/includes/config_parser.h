#ifndef DIVIFETCH_CONFIG_PARSER_H

#include <vector>
#include <string>
#include <algorithm>
#include <sstream>
#include <cstdlib>

void undash_string(std::string& str);
int string_to_int(const std::string& str);
std::string config_parser_strip_comments(const std::string &line);
std::vector<std::string> config_parser_tokenizer(const std::string &source_config);
std::vector<std::string> config_parser_form_reader(const std::vector<std::string> &tokens, size_t &idx);

#endif
