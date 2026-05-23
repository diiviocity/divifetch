#include <algorithm>
#include <iostream>
#include <sstream>
#include <fstream>
#include <cstdint>
#include <string>
#include <vector>
#include <cstdio>
#include <memory>
#include <array>

struct ConfigEntry {
    std::string type;
    std::string key;
    std::string key_prefix;
    std::string key_suffix;
    std::string value;
    std::string value_prefix;
    std::string value_suffix;
};

struct ConfigDefault {
    int art_width;
    std::string art_file;
    std::string art_prefix;
    std::string art_suffix;
    std::string type;
    std::string key_prefix;
    std::string key_suffix;
    std::string value;
    std::string value_prefix;
    std::string value_suffix;
};

std::string config_parser_strip_comments(const std::string &line) {
    bool in_string = false;
    for (size_t i = 0; i < line.size(); ++i) {
        if (line[i] == '"' && (i == 0 || line[i-1] != '\\')) in_string = !in_string;
        if (!in_string && line[i] == ';') return line.substr(0, i);
    }
    return line;
}

std::vector<std::string> config_parser_tokenizer(const std::string &source_config) {
    std::vector<std::string> tokens;
    size_t i = 0;
    while (i < source_config.size()) {
        if (std::isspace(source_config[i])) { i++; continue; }

        if (source_config[i] == '(' || source_config[i] == ')') {
            tokens.push_back(std::string(1, source_config[i]));
            i++;
        } else if (source_config[i] == '"') {
            std::string s;
            i++;
            while (i < source_config.size()) {
                if (source_config[i] == '\\' && i+1 < source_config.size()) {
                    s += source_config[i]; s += source_config[i+1]; i += 2;
                } else if (source_config[i] == '"') { i++; break; }
                else { s += source_config[i]; i++; }
            }
            tokens.push_back(s);
        } else {
            std::string atom;
            while (i < source_config.size() && !std::isspace(source_config[i]) && source_config[i] != '(' && source_config[i] != ')' && source_config[i] != '"') {
                atom += source_config[i];
                i++;
            }
            tokens.push_back(atom);
        }
    }
    return tokens;
}

std::vector<std::string> config_parser_form_reader(const std::vector<std::string> &tokens, size_t &idx) {
    while (idx < tokens.size() && tokens[idx] != "(") idx++;
    if (idx >= tokens.size()) return {};
    idx++;

    std::vector<std::string> form;
    int depth = 1;
    while (idx < tokens.size() && depth > 0) {
        if (tokens[idx] == "(") { depth++; form.push_back(tokens[idx]); idx++; }
        else if (tokens[idx] == ")") { depth--; if (depth > 0) form.push_back(tokens[idx]); idx++; }
        else { form.push_back(tokens[idx]); idx++; }
    }
    return form;
}

void config_parser_apply_config_field(ConfigDefault &config_default, const std::string &key, const std::string &val) {
    if      (key == "art_width")    config_default.art_width    = std::stoi(val);
    else if (key == "art_file")     config_default.art_file     = val;
    else if (key == "art_prefix")   config_default.art_prefix   = val;
    else if (key == "art_suffix")   config_default.art_suffix   = val;
    else if (key == "key_prefix")   config_default.key_prefix   = val;
    else if (key == "key_suffix")   config_default.key_suffix   = val;
    else if (key == "value_prefix") config_default.value_prefix = val;
    else if (key == "value_suffix") config_default.value_suffix = val;
}

void config_parser_apply_entry_field(ConfigEntry &config_entry, const std::string &key, const std::string &val) {
    if      (key == "key")          config_entry.key           = val;
    else if (key == "key_prefix")   config_entry.key_prefix    = val;
    else if (key == "key_suffix")   config_entry.key_suffix    = val;
    else if (key == "value")        config_entry.value         = val;
    else if (key == "value_prefix") config_entry.value_prefix  = val;
    else if (key == "value_suffix") config_entry.value_suffix  = val;
}

void config_parser_unsex_string(std::string& str) {
    std::replace(str.begin(), str.end(), '-', '_');
}

void parse_config(const std::string filename, ConfigDefault &config_default, std::vector<ConfigEntry> &config_entries) {
    std::ifstream file(filename);
    if (!file.is_open()) return;

    std::string source_config;
    std::string line;
    while (std::getline(file, line))
        source_config += config_parser_strip_comments(line) + ' ';

    std::vector<std::string> tokens = config_parser_tokenizer(source_config);
    size_t idx = 0;

    while (idx < tokens.size()) {
        std::vector<std::string> form = config_parser_form_reader(tokens, idx);
        if (form.empty()) break;

        config_parser_unsex_string(form[0]);

        if (form[0] == "config") {
            if (form.size() < 2) continue;
            if (form[1] == "(") {
                size_t pos = 1;
                while (pos < form.size()) {
                    if (form[pos] == "(") {
                        pos++;
                        if (pos >= form.size()) break;
                        std::string key = form[pos];
                        config_parser_unsex_string(key);
                        pos++;
                        if (pos >= form.size()) break;
                        std::string val = form[pos];
                        pos++;
                        if (pos < form.size() && form[pos] == ")") pos++;
                        config_parser_apply_config_field(config_default, key, val);
                    } else {
                        pos++;
                    }
                }
            } else if (form.size() >= 3) {
                config_parser_unsex_string(form[1]);
                config_parser_apply_config_field(config_default, form[1], form[2]);
            }
            continue;
        }
        
        ConfigEntry current_entry;
        current_entry.type = form[0];
        current_entry.key = current_entry.type;
        if (!current_entry.key.empty()) current_entry.key[0] = std::toupper(current_entry.key[0]);
        current_entry.key_prefix = config_default.key_prefix;
        current_entry.key_suffix = config_default.key_suffix;
        current_entry.value = "";
        current_entry.value_prefix = config_default.value_prefix;
        current_entry.value_suffix = config_default.value_suffix;

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

        const std::vector<std::string> form_position_order = {"key", "value", "key_prefix", "key_suffix", "value_prefix", "value_suffix"};

        size_t form_pos = 1;
        std::vector<std::string> form_positional;
        while (form_pos < form.size() && form[form_pos] != "(") {
            form_positional.push_back(form[form_pos]);
            form_pos++;
        }

        for (size_t i = 0; i < form_positional.size() && i < form_position_order.size(); ++i)
            config_parser_apply_entry_field(current_entry, form_position_order[i], form_positional[i]);

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
                config_parser_apply_entry_field(current_entry, field, val);
            } else { form_pos++; }
        }

        config_entries.push_back(current_entry);
    }
}


std::vector<std::string> parse_file_to_vector(std::string filename) {
    std::vector<std::string> text_lines;
    std::ifstream file(filename);
    std::string current_line;
    while (std::getline(file, current_line)) text_lines.push_back(current_line);
    return text_lines;
}


void parse_file_to_out(std::ofstream& fetch_file, std::string filename) {
    std::vector<std::string> text_lines;
    std::ifstream file(filename);
    std::string current_line;
    while (std::getline(file, current_line)) fetch_file << current_line << "\n";
}


bool is_present_in_vector(const std::vector<std::string>& vec, std::string_view target) {
    return std::find(vec.begin(), vec.end(), target) != vec.end();
}

void assess_needed_for_modules(std::vector<std::string>& out_needed_imports, std::vector<std::string>& out_needed_functions, const std::vector<ConfigEntry>& config_entries) {
    out_needed_imports.push_back("stddef.h");
    out_needed_imports.push_back("stdio.h");

    for (size_t i = 0; i < config_entries.size(); i++) {
        if (config_entries[i].type != "static") {
            if ( !is_present_in_vector(out_needed_functions, config_entries[i].type) ) {
                out_needed_functions.push_back(config_entries[i].type);
                std::vector<std::string> current_entry_needed_imports = parse_file_to_vector("modules/" + out_needed_functions.back() + "/imports");
                for (size_t j = 0; j < current_entry_needed_imports.size(); j++) {
                    std::string current_needed_import = current_entry_needed_imports[j];
                    if (!is_present_in_vector(out_needed_imports, current_needed_import))
                        out_needed_imports.push_back(current_needed_import);
                }
            }
        }
    }
}


void out_write_needed_for_modules(std::ofstream& fetch_file, std::vector<std::string>& out_needed_imports, std::vector<std::string>& out_needed_functions) {
    for (size_t i = 0; i < out_needed_imports.size(); i++) {
        fetch_file << "#include <" << out_needed_imports[i] << ">" << "\n";
    }
    for (size_t i = 0; i < out_needed_functions.size(); i++) {
        parse_file_to_out(fetch_file, "modules/" + out_needed_functions[i] + "/module.c");
    }
}

std::string make_main_function_line(std::string art_line, std::string key, std::string key_prefix, std::string key_suffix, std::string value, std::string value_prefix, std::string value_suffix) {
    return art_line + key_prefix + key + key_suffix + value_prefix + value + value_suffix + "\\n";
}

size_t utf8_display_width(const std::string& s) {
    size_t width = 0;
    size_t i = 0; 
    while (i < s.size()) {
        unsigned char c = s[i]; 
        if (c == 0x1B && i + 1 < s.size() && s[i+1] == '[') {
            i += 2;
            while (i < s.size() && (s[i] < 0x40 || s[i] > 0x7E)) i++;
            i++;
        } else if (c == '\\' && i + 4 < s.size() && s[i+1] == '0' && s[i+2] == '3' && s[i+3] == '3'
                 && s[i+4] == '[') {
            i += 5; 
            while (i < s.size() && (s[i] < 0x40 || s[i] > 0x7E)) i++;
            i++;
        } else if (c == '\\' && i + 3 < s.size() && s[i+1] == '0' && s[i+2] == '3' && s[i+3] == '3') {
            i += 4;
        } else {
            if ((c & 0x80) == 0) { width++; i++; }            // ASCII
            else if ((c & 0xE0) == 0xC0) { width++; i += 2; } // 2-byte
            else if ((c & 0xF0) == 0xE0) { width++; i += 3; } // 3-byte
            else if ((c & 0xF8) == 0xF0) { width++; i += 4; } // 4-byte
            else { i++; } // invalid
        }
    } 
    return width;
}

void out_write_fetch_main(std::ofstream& fetch_file, 
                          const ConfigDefault& config_default,
                          const std::vector<ConfigEntry>& config_entries) {
    std::vector<std::string> art_lines_original = parse_file_to_vector(config_default.art_file);

    while (config_entries.size() > art_lines_original.size()) {
        art_lines_original.push_back(std::string(config_default.art_width, ' '));
    }

    std::vector<std::string> art_lines;

    for (size_t i = 0; i < art_lines_original.size(); i++) {
        size_t art_line_width = utf8_display_width(art_lines_original[i]);
        size_t art_padding_width = ( art_line_width < config_default.art_width ) ? config_default.art_width - art_line_width : 0;

        art_lines.push_back(
            config_default.art_prefix
            + art_lines_original[i]
            + std::string(art_padding_width, ' ')
            + config_default.art_suffix
        );
    }
    
    fetch_file << "int main() {" << "\n" 
               << "    char _buf[256];" << "\n";

    auto flush_static_batch = [&](std::string& batch) {
        if (!batch.empty()) {
            fetch_file << "    fputs(\"" << batch << "\", stdout);" << "\n";
            batch.clear();
        }
    };

    std::string static_batch;

    for (size_t i = 0; i < config_entries.size(); i++) {
        if (config_entries[i].type == "static") {
            static_batch += make_main_function_line(
                art_lines[i],
                config_entries[i].key,
                config_entries[i].key_prefix,
                config_entries[i].key_suffix,
                config_entries[i].value,
                config_entries[i].value_prefix,
                config_entries[i].value_suffix
            );
        } else {
            flush_static_batch(static_batch);
            std::string module_arg = config_entries[i].value.size() > 0
                ? "\"" + config_entries[i].value + "\", _buf, sizeof(_buf)"
                : "_buf, sizeof(_buf)";
            fetch_file << "    printf(\"" << make_main_function_line(
                art_lines[i],
                config_entries[i].key,
                config_entries[i].key_prefix,
                config_entries[i].key_suffix,
                "%s",
                config_entries[i].value_prefix,
                config_entries[i].value_suffix
            ) << "\", " << config_entries[i].type << "_module_preset(" << module_arg << "));" << "\n";
        }
    }

    if (art_lines_original.size() > config_entries.size()) {
        for (size_t i = config_entries.size(); i < art_lines_original.size(); i++) {
            static_batch += art_lines[i] + "\\n";
        }
    }

    flush_static_batch(static_batch);

    fetch_file << "    return 0;" << "\n"
               << "}" << "\n";
    
}

std::string command_execution_output(const char* command_to_exec) {
    std::array<char, 128> buffer;
    std::string result;
    auto deleter = [](FILE* f) { pclose(f); };
    std::unique_ptr<FILE, decltype(deleter)> pipe(popen(command_to_exec, "r"), deleter);
    if (!pipe) { return "?"; }
    while (fgets(buffer.data(), static_cast<int>(buffer.size()), pipe.get()) != nullptr) { result += buffer.data(); }
    while (!result.empty() && result.back() == '\n') result.pop_back();
    return result;
}

void out_write_config_main(std::string config_out_file_path) {
    std::ofstream config_file(config_out_file_path);

    config_file << ";;;; THE EXAMPLE CONFIG FILE" << "\n\n"

                << "; read the documentation:" << "\n"
                << "; https://git.divio.city/diviocity/divifetch/wiki" << "\n\n"

                << "(config (art-width 45)" << "\n"
                << "        (art-file \"ascii/cat.txt\")" << "\n"
                << "        (art-prefix \"\\033[1m\")" << "\n"
                << "        (art-suffix \"\\033[0m\")" << "\n"
                << "        (key-prefix \"\\033[1m\\033[34m\")" << "\n"
                << "        (key-suffix \"\\033[0m: \")" << "\n"
                << "        (value-prefix \"\")" << "\n"
                << "        (value-suffix \"\"))\n" << "\n\n"

                << "(plain divifetch)" << "\n"
                << "(plain ---------)" << "\n"

                << "(static OS \"" << command_execution_output("source /etc/os-release && echo $NAME") << "\")\n\n"

                << "(kernel)" << "\n"
                << "(packages-pacman Packages)" << "\n"
                << "(shell)" << "\n"
                << "(terminal)" << "\n"
                << "(wm)" << "\n"
                << "(static CPU \"" << command_execution_output("grep -m 1 'model name' /proc/cpuinfo") << "\")" << "\n";

    std::stringstream gpus_list(command_execution_output("lspci | grep -i vga"));
    std::string current_gpu;
    while (getline(gpus_list, current_gpu, '\n')) {
        config_file << "(static GPU \"" << current_gpu << "\")\n";
    }

    config_file << "(memory)" << "\n";

    std::stringstream fstab_mounts(command_execution_output("awk '{print $2}' /etc/fstab | grep '^/'"));
    std::string current_mount;
    while (getline(fstab_mounts, current_mount, '\n')) {
        config_file << "(mount \"Mount (" << current_mount << ")\" \""  << current_mount << "\")\n";
    }

    config_file << "(battery)" << "\n"
                << "(static Notice \"modify the configuration file!\")" << "\n\n"

                << "(break)" << "\n\n"

                << "(colors_normal)" << "\n"
                << "(colors_bright)" << "\n";

    config_file.close();
    
    std::cout << "generated the example config file " << config_out_file_path << "\n";
}

void out_write_help(std::string current_executable_name) {
    std::cout << "usage: " << current_executable_name << " [OPTIONS]" << "\n"
              << "commands:" << "\n"
              << "      source      generate only the source code for the fetch program" << "\n"
              << "      config      generate an example config file" << "\n"
              << "when no command is specified the default behaviour is to run source" << "\n"
              << "options:" << "\n"
              << "      -h,  --help                display this help and exit" << "\n"
              << "      -c,  --config <file>       specify the config file (default: config.conf)" << "\n"
              << "      -os, --out-source <file>   specify the output file for source (default: fetch.c)" << "\n" 
              << "      -oc, --out-config <file>   specify the output file for config (default: config.conf.example)" << "\n";
}

int main(int argc, char* argv[]) {
    std::string config_file_path = "config.conf";
    std::string out_config_file_path = "config.conf.example";
    std::string out_source_file_path = "fetch.c";

    std::string subcommand;
 
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "-h" || arg == "--help") {
            out_write_help(argv[0]); return 0;
        } else if (arg == "source" || arg == "config") {
            subcommand = arg;
        } else if (arg == "-c" || arg == "--config") {
            if (i+1 < argc) config_file_path = argv[++i];
            else { std::cerr << "error: " << arg << " requires an argument\n"; return 1; }
        } else if (arg == "-os" || arg == "--out-source") {
            if (i+1 < argc) out_source_file_path = argv[++i];
            else { std::cerr << "error: " << arg << " requires an argument\n"; return 1; }
        } else if (arg == "-oc" || arg == "--out-config") {
            if (i+1 < argc) out_config_file_path = argv[++i];
            else { std::cerr << "error: " << arg << " requires an argument\n"; return 1; }
        } else {
            std::cerr << "warning: unknown argument '" << arg << "', ignoring\n";
        }
    }
 
    if (subcommand == "config") { out_write_config_main(out_config_file_path); return 0; }
 
    if (subcommand == "source") {
        std::ofstream fetch_file(out_source_file_path);
 
        std::vector<std::string> out_needed_imports;
        std::vector<std::string> out_needed_functions;
        std::vector<ConfigEntry> config_entries;
        ConfigDefault config_default;
 
        parse_config(config_file_path, config_default, config_entries);
        assess_needed_for_modules(out_needed_imports, out_needed_functions, config_entries);
        out_write_needed_for_modules(fetch_file, out_needed_imports, out_needed_functions);
        out_write_fetch_main(fetch_file, config_default, config_entries);
 
        fetch_file.close();
        std::cout << "generated the source code for the fetch program " << out_source_file_path << "\n";
    }
    
    return 0;
}

