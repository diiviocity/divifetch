#ifndef DIVIFETCH_CONFIG_PARSER_FETCH_H

#include <cstddef>
#include <string>
#include <fstream>

struct FetchConfigEntry {
    std::string type;
    std::string key;
    std::string key_prefix;
    std::string key_suffix;
    std::string value;
    std::string value_prefix;
    std::string value_suffix;
    std::string build_time;
};

struct FetchConfigDefault {
    int buffer_size;
    std::string execute;
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
    std::string build_time;
};

struct ConfigSource {
    std::vector<FetchConfigEntry> config_entries;
    FetchConfigDefault config_default;
};

struct FetchDefenition {
    int id;
    std::string execute;
};

struct ConfigSourceNeeded {
    std::vector<std::string> imports;
    std::vector<FetchDefenition> defenitions;
    std::vector<std::string> functions_all;
    std::vector<std::string> functions_runtime;
    std::vector<std::string> functions_buildtime;
};

void fetch_config_parser_apply_config_field(FetchConfigDefault &config_default, const std::string &key, const std::string &val);
void fetch_config_parser_apply_entry_field(FetchConfigEntry &config_entry, const std::string &key, const std::string &val);
void parse_fetch_config(const std::string filename, ConfigSource& current_config_source);

#endif
