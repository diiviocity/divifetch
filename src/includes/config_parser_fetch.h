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
};

struct FetchConfigDefault {
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

struct ConfigSource {
    std::vector<FetchConfigEntry> config_entries;
    FetchConfigDefault config_default;
};

struct ConfigSourceNeeded {
    std::vector<std::string> functions;
};

void fetch_config_parser_apply_config_field(FetchConfigDefault &config_default, const std::string &key, const std::string &val);
void fetch_config_parser_apply_entry_field(FetchConfigEntry &config_entry, const std::string &key, const std::string &val);
void parse_fetch_config(const std::string filename, ConfigSource& current_config_source);

#endif
