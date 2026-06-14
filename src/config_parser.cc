#include "includes/config_parser.h"

void undash_string(std::string& str) {
    std::replace(str.begin(), str.end(), '-', '_');
}

int string_to_int(const std::string& str) {
    std::istringstream iss(str);
    int result;
    iss >> result;
    return result;
}

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
        if (std::isspace((source_config[i]))) { i++; continue; }

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
            while (i < source_config.size() && !std::isspace((source_config[i])) && source_config[i] != '(' && source_config[i] != ')' && source_config[i] != '"') {
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
    if (idx >= tokens.size()) {
        std::vector<std::string> empty;
        return empty;
    }
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
