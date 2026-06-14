#include "includes/config_parser.h"
#include "includes/config_parser_fetch.h"
#include "includes/error.h"

void fetch_config_parser_apply_config_field(FetchConfigDefault &config_default, const std::string &key, const std::string &val) {
    if      (key == "art_width")    config_default.art_width    = string_to_int(val);
    else if (key == "art_file")     config_default.art_file     = val;
    else if (key == "art_prefix")   config_default.art_prefix   = val;
    else if (key == "art_suffix")   config_default.art_suffix   = val;
    else if (key == "key_prefix")   config_default.key_prefix   = val;
    else if (key == "key_suffix")   config_default.key_suffix   = val;
    else if (key == "value_prefix") config_default.value_prefix = val;
    else if (key == "value_suffix") config_default.value_suffix = val;
}

void fetch_config_parser_apply_entry_field(FetchConfigEntry &config_entry, const std::string &key, const std::string &val) {
    if      (key == "key")          config_entry.key          = val;
    else if (key == "key_prefix")   config_entry.key_prefix   = val;
    else if (key == "key_suffix")   config_entry.key_suffix   = val;
    else if (key == "value")        config_entry.value        = val;
    else if (key == "value_prefix") config_entry.value_prefix = val;
    else if (key == "value_suffix") config_entry.value_suffix = val;
}

void parse_fetch_config(const std::string filename, ConfigSource& current_config_source) {
    std::ifstream file(filename.c_str());
    if (!file.is_open()) print_error("couldn't open config file '" + filename + "'");

    std::string source_config;
    std::string line;
    while (std::getline(file, line))
        source_config += config_parser_strip_comments(line) + ' ';

    std::vector<std::string> tokens = config_parser_tokenizer(source_config);
    size_t idx = 0;

    while (idx < tokens.size()) {
        std::vector<std::string> form = config_parser_form_reader(tokens, idx);
        if (form.empty()) break;

        undash_string(form[0]);

        if (form[0] == "config") {
            if (form.size() < 2) continue;
            if (form[1] == "(") {
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
                        fetch_config_parser_apply_config_field(current_config_source.config_default, key, val);
                    } else {
                        pos++;
                    }
                }
            } else if (form.size() >= 3) {
                undash_string(form[1]);
                fetch_config_parser_apply_config_field(current_config_source.config_default, form[1], form[2]);
            }
            continue;
        }
        
        FetchConfigEntry current_entry;
        current_entry.type = form[0];
        current_entry.key = current_entry.type;
        if (!current_entry.key.empty()) current_entry.key[0] = std::toupper((current_entry.key[0]));
        current_entry.key_prefix = current_config_source.config_default.key_prefix;
        current_entry.key_suffix = current_config_source.config_default.key_suffix;
        current_entry.value = "";
        current_entry.value_prefix = current_config_source.config_default.value_prefix;
        current_entry.value_suffix = current_config_source.config_default.value_suffix;

        if (current_entry.type == "break") {
            current_entry.type = "plain";
            current_entry.key = "";
        } else if (current_entry.type == "colors_normal") {
            current_entry.type = "plain";
            current_entry.key = "\\033[40m   \\033[41m   \\033[42m   \\033[43m   \\033[44m   \\033[45m   \\033[46m   \\033[47m   \\033[0m";
        } else if (current_entry.type == "colors_bright") {
            current_entry.type = "plain";
            current_entry.key = "\\033[100m   \\033[101m   \\033[102m   \\033[103m   \\033[104m   \\033[105m   \\033[106m   \\033[107m   \\033[0m";
        }

        if (current_entry.type == "plain") {
            current_entry.type = "static";
            current_entry.key_prefix = "";
            current_entry.key_suffix = "";
            current_entry.value_prefix = "";
            current_entry.value_suffix = "";
        }

        std::vector<std::string> form_position_order;
        form_position_order.push_back("key");
        form_position_order.push_back("value");
        form_position_order.push_back("key_prefix");
        form_position_order.push_back("key_suffix");
        form_position_order.push_back("value_prefix");
        form_position_order.push_back("value_suffix");

        size_t form_pos = 1;
        std::vector<std::string> form_positional;
        while (form_pos < form.size() && form[form_pos] != "(") {
            form_positional.push_back(form[form_pos]);
            form_pos++;
        }

        for (size_t i = 0; i < form_positional.size() && i < form_position_order.size(); ++i)
            fetch_config_parser_apply_entry_field(current_entry, form_position_order[i], form_positional[i]);

        while (form_pos < form.size()) {
            if (form[form_pos] == "(") {
                form_pos++; 
                if (form_pos >= form.size()) break;
                std::string field = form[form_pos];
                form_pos++; 
                if (form_pos >= form.size()) break;
                std::string val = form[form_pos];
                form_pos++; 
                if (form_pos < form.size() && form[form_pos] == ")") form_pos++;
                fetch_config_parser_apply_entry_field(current_entry, field, val);
            } else { form_pos++; }
        }

        current_config_source.config_entries.push_back(current_entry);
    }
}
