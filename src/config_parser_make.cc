#include "includes/config_parser.h"
#include "includes/config_parser_make.h"
#include "includes/error.h"

void make_config_parser_apply_template_field(MakeTemplate &tmpl, const std::string &key, const std::string &val) {
    if      (key == "source_file")      tmpl.source_file      = val;
    else if (key == "command")          tmpl.command          = val;
    else if (key == "linker_flags")     tmpl.linker_flags     = val;
    else if (key == "object_extension") tmpl.object_extension = val;
    else if (key == "archive")          tmpl.archive          = val;
    else print_warning("unknown template field '" + key + "'");
}

void parse_make_templates_config(const std::string filename, std::map<std::string, MakeTemplate>& templates) {
    std::ifstream file(filename.c_str());
    if (!file.is_open()) print_error("couldn't open make config file '" + filename + "'");

    std::string source_config;
    std::string line;
    while (std::getline(file, line))
        source_config += config_parser_strip_comments(line) + ' ';

    std::vector<std::string> tokens = config_parser_tokenizer(source_config);
    size_t idx = 0;

    MakeTemplate defaults;

    while (idx < tokens.size()) {
        std::vector<std::string> form = config_parser_form_reader(tokens, idx);
        if (form.empty()) break;

        undash_string(form[0]);

        if (form[0] == "defaults") {
            size_t pos = 1;
            while (pos < form.size()) {
                if (form[pos] == "(") {
                    pos++;
                    if (pos >= form.size()) break;
                    std::string key = form[pos];
                    undash_string(key);
                    pos++;
                    if (pos >= form.size()) break;
                    std::string val = form[pos];
                    pos++;
                    if (pos < form.size() && form[pos] == ")") pos++;
                    make_config_parser_apply_template_field(defaults, key, val);
                } else {
                    pos++;
                }
            }
            continue;
        }

        if (form[0] == "template" && form.size() >= 2) {
            std::string lang = form[1];
            MakeTemplate tmpl = defaults;

            size_t pos = 2;
            while (pos < form.size()) {
                if (form[pos] == "(") {
                    pos++;
                    if (pos >= form.size()) break;
                    std::string key = form[pos];
                    undash_string(key);
                    pos++;
                    if (pos >= form.size()) break;
                    std::string val = form[pos];
                    pos++;
                    if (pos < form.size() && form[pos] == ")") pos++;
                    make_config_parser_apply_template_field(tmpl, key, val);
                } else {
                    pos++;
                }
            }

            templates[lang] = tmpl;
        }
    }
}

void parse_make_module_config(const std::string filename, std::map<std::string, MakeTemplate>& templates, MakeTemplate& tmpl) {
    std::ifstream file(filename.c_str());
    if (!file.is_open()) print_error("couldn't open module config file '" + filename + "'");

    std::string source_config;
    std::string line;
    while (std::getline(file, line))
        source_config += config_parser_strip_comments(line) + ' ';

    std::vector<std::string> tokens = config_parser_tokenizer(source_config);
    size_t idx = 0;

    std::string lang = "c";

    while (idx < tokens.size()) {
        std::vector<std::string> form = config_parser_form_reader(tokens, idx);
        if (form.empty()) break;

        undash_string(form[0]);

        if (form[0] == "language" && form.size() >= 2) {
            lang = form[1];
        }
    }

    if (templates.find(lang) == templates.end())
        print_error("no template '" + lang + "' in make.conf (referenced in '" + filename + "')");

    tmpl = templates[lang];

    idx = 0;
    while (idx < tokens.size()) {
        std::vector<std::string> form = config_parser_form_reader(tokens, idx);
        if (form.empty()) break;

        undash_string(form[0]);

        if (form[0] == "template") {
            size_t pos = 1;
            while (pos < form.size()) {
                if (form[pos] == "(") {
                    pos++;
                    if (pos >= form.size()) break;
                    std::string key = form[pos];
                    undash_string(key);
                    pos++;
                    if (pos >= form.size()) break;
                    std::string val = form[pos];
                    pos++;
                    if (pos < form.size() && form[pos] == ")") pos++;
                    make_config_parser_apply_template_field(tmpl, key, val);
                } else {
                    pos++;
                }
            }
        }
    }
}
