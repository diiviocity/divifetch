#ifndef DIVIFETCH_CONFIG_PARSER_MAKE_H

#include <string>
#include <fstream>
#include <map>

struct MakeTemplate {
    std::string source_file;
    std::string command;
    std::string linker_flags;
    std::string object_extension;
    std::string archive;
};

void make_config_parser_apply_template_field(MakeTemplate &tmpl, const std::string &key, const std::string &val);
void parse_make_templates_config(const std::string filename, std::map<std::string, MakeTemplate>& templates);
void parse_make_module_config(const std::string filename, std::map<std::string, MakeTemplate>& templates, MakeTemplate& tmpl);

#endif
