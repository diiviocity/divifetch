#include <string>
#include <vector>

#include "includes/error.h"
#include "includes/utils.h"

#include "includes/config_parser.h"
#include "includes/config_parser_fetch.h"
#include "includes/config_parser_make.h"

void assess_needed_for_fetch(ConfigSourceNeeded& out_needed, const ConfigSource& current_config_source) {
    for (size_t i = 0; i < current_config_source.config_entries.size(); i++) {
        if (current_config_source.config_entries[i].type != "static") {
            std::string header_path = "modules/" + current_config_source.config_entries[i].type + "/module.h";
            std::ifstream module_header_file(header_path.c_str());
            if (!module_header_file.is_open()) { print_error("couldn't find module '"+current_config_source.config_entries[i].type+"'"); }
            add_unique(out_needed.functions_all, current_config_source.config_entries[i].type);
            if (current_config_source.config_entries[i].build_time != "yes") {
                add_unique(out_needed.functions_runtime, current_config_source.config_entries[i].type);
            } else {
                add_unique(out_needed.functions_buildtime, current_config_source.config_entries[i].type);
            }
        }
    }
    if (current_config_source.config_default.execute.size()) {
        add_unique(out_needed.imports, "unistd.h");
    }
}

std::string make_main_function_line(std::string art_line, FetchConfigEntry config_entry) {
    return art_line + config_entry.key_prefix + config_entry.key + config_entry.key_suffix + config_entry.value_prefix + config_entry.value + config_entry.value_suffix + "\\n";
}

void output_fetch_print(std::ofstream& fetch_file, const ConfigSource& current_config_source, ConfigSourceNeeded& out_needed) {
    fetch_file << "    char _buf[" << current_config_source.config_default.buffer_size << "];\n";

    std::vector<std::string> art_lines_original = parse_file_to_vector(current_config_source.config_default.art_file);

    while (current_config_source.config_entries.size() > art_lines_original.size()) {
        art_lines_original.push_back(std::string(current_config_source.config_default.art_width, ' '));
    }

    std::vector<std::string> art_lines;

    for (size_t i = 0; i < art_lines_original.size(); i++) {
        size_t art_line_width = utf8_display_width(art_lines_original[i]);
        size_t art_padding_width = ( art_line_width < static_cast<size_t>(current_config_source.config_default.art_width) ) ?
            static_cast<size_t>(current_config_source.config_default.art_width) - art_line_width : 0;

        art_lines.push_back(
            current_config_source.config_default.art_prefix
            + art_lines_original[i]
            + std::string(art_padding_width, ' ')
            + current_config_source.config_default.art_suffix
        );
    }

    std::string static_batch;

    for (size_t i = 0; i < current_config_source.config_entries.size(); i++) {
        if (current_config_source.config_entries[i].type == "static") {
            static_batch += make_main_function_line(art_lines[i], current_config_source.config_entries[i]);
        } else {
            if (!static_batch.empty()) {
                fetch_file << "    fputs(\"" << static_batch << "\", stdout);\n";
                static_batch.clear();
            }
            std::string module_arg = current_config_source.config_entries[i].value.size() > 0
                ? "\"" + current_config_source.config_entries[i].value + "\", _buf, sizeof(_buf)"
                : "_buf, sizeof(_buf)";
            FetchConfigEntry printf_entry = current_config_source.config_entries[i];
            printf_entry.value = "%s";
            if (current_config_source.config_entries[i].build_time == "yes") {
                FetchDefenition current_fetch_defenition;
                current_fetch_defenition.id = out_needed.defenitions.size();
                current_fetch_defenition.execute = current_config_source.config_entries[i].type+"_module_preset("+module_arg+")";
                out_needed.defenitions.push_back(current_fetch_defenition);
                fetch_file << "    printf(\"" << make_main_function_line(art_lines[i], printf_entry) << "\", BUILD_TIME_" << current_fetch_defenition.id << ");\n";
            } else {
                fetch_file << "    printf(\"" << make_main_function_line(art_lines[i], printf_entry) << "\", "
                           << current_config_source.config_entries[i].type << "_module_preset(" << module_arg << "));\n";
            }
            
        }
    }

    if (art_lines_original.size() > current_config_source.config_entries.size()) {
        for (size_t i = current_config_source.config_entries.size(); i < art_lines_original.size(); i++) {
            static_batch += art_lines[i] + "\\n";
        }
    }

    if (!static_batch.empty()) {
        fetch_file << "    fputs(\"" << static_batch << "\", stdout);\n";
    }

    if (current_config_source.config_default.execute.size()) {
        fetch_file << "    execl(\"" << current_config_source.config_default.execute << "\", " << current_config_source.config_default.execute << "\", NULL);\n";
    }
}

void output_fetch_header_gen(std::ofstream& header_gen_file, std::string header_file_path, ConfigSourceNeeded& out_needed) {
    for (size_t i = 0; i < out_needed.functions_buildtime.size(); i++) {
        header_gen_file << "#include \"modules/" << out_needed.functions_buildtime[i] << "/module.h\"\n";
    }
    header_gen_file << "#include <stdio.h>\n"
                    << "int main() {\n"
                    << "    char _buf[256];\n"
                    << "    FILE *headerfile = fopen(\"" << header_file_path <<"\", \"w\");\n"
                    << "    if (headerfile == NULL) { fputs(\"couldn't open " << header_file_path <<"\", stderr); return 0; }\n";

    header_gen_file << "    fputs(\"";
    for (size_t i = 0; i < out_needed.functions_runtime.size(); i++) {
        header_gen_file << "#include \\\"modules/" << out_needed.functions_runtime[i] << "/module.h\\\"\\n";
    }
    for (size_t i = 0; i < out_needed.imports.size(); i++) {
        header_gen_file << "#include <" << out_needed.imports[i] << ">\\n";
    }
    header_gen_file << "\", headerfile);\n";

    for (size_t i = 0; i < out_needed.defenitions.size(); i++) {
        header_gen_file << "    fprintf(headerfile, \"#define BUILD_TIME_" << out_needed.defenitions[i].id << " \\\"%s\\\"\\n\", " << out_needed.defenitions[i].execute << ");\n";
    }

    header_gen_file << "    return 0;\n"
                    << "}\n";

}

void output_fetch_main(std::ofstream& fetch_file, const std::vector<ConfigSource>& configs_sources, ConfigSourceNeeded& out_needed) {
    fetch_file << "#include \"fetch.h\"\n"
               << "int main() {\n";

    if (configs_sources.size() == 1) {
        output_fetch_print(fetch_file, configs_sources[0], out_needed);
    } else {
        fetch_file << "    struct timespec ts;\n"
                   << "    clock_gettime(CLOCK_REALTIME, &ts);\n"
                   << "    srand(ts.tv_nsec);\n"
                   << "    int chosen_random_config = rand() % " << configs_sources.size() << ";\n"
                   << "    switch(chosen_random_config) {\n";

        for (size_t i = 0; i < configs_sources.size(); i++) {
            fetch_file << "    case " << i << ": {\n";
            output_fetch_print(fetch_file, configs_sources[i], out_needed);
            fetch_file << "    break;\n"
                       << "}\n";
        }

        fetch_file << "    }\n";
    }

    fetch_file << "    return 0;\n"
               << "}\n";

}

void output_example_config(std::string config_out_file_path) {
    std::ofstream config_file(config_out_file_path.c_str());

    config_file << ";;;; THE EXAMPLE CONFIG FILE\n\n"

                << "; read the documentation:\n"
                << "; https://git.divio.city/diviocity/divifetch/wiki\n\n"

                << "(config (art-width 45)\n"
                << "        (art-file \"ascii/cat.txt\")\n"
                << "        (art-prefix \"\\033[1m\")\n"
                << "        (art-suffix \"\\033[0m\")\n"
                << "        (key-prefix \"\\033[1m\\033[34m\")\n"
                << "        (key-suffix \"\\033[0m: \")\n"
                << "        (value-prefix \"\")\n"
                << "        (value-suffix \"\"))\n\n\n"

                << "(plain divifetch)\n"
                << "(plain ---------)\n"

                << "(static OS \"" << command_execution_output("source /etc/os-release && echo $NAME") << "\")\n\n"

                << "(kernel)\n"
                << "(packages-pacman Packages)\n"
                << "(shell (build-time yes))\n"
                << "(terminal (build-time yes))\n"
                << "(wm (build-time yes))\n"
                << "(static CPU \"" << command_execution_output("grep -m 1 'model name' /proc/cpuinfo") << "\")\n";

    std::stringstream gpus_list(command_execution_output("lspci | grep -i vga"));
    std::string current_gpu;
    while (getline(gpus_list, current_gpu, '\n')) {
        config_file << "(static GPU \"" << current_gpu << "\")\n";
    }

    config_file << "(memory)\n";

    std::stringstream fstab_mounts(command_execution_output("awk '{print $2}' /etc/fstab | grep '^/'"));
    std::string current_mount;
    while (getline(fstab_mounts, current_mount, '\n')) {
        config_file << "(mount \"Mount (" << current_mount << ")\" \""  << current_mount << "\")\n";
    }

    config_file << "(battery)\n"
                << "(static Notice \"modify the configuration file!\")\n\n"

                << "(break)\n\n"

                << "(colors_normal)\n"
                << "(colors_bright)\n";

    config_file.close();

    std::cout << "generated the example config file " << config_out_file_path << "\n";
}

void output_makefile(std::ofstream& make_file, std::string& make_config_file_path, ConfigSourceNeeded& out_needed, const std::string& out_source_file_path, const std::string& out_header_file_path) {
    std::map<std::string, MakeTemplate> templates;

    parse_make_templates_config(make_config_file_path, templates);

    make_file << "include config.mk\n\n"
            
              << "DESTDIR = /usr/local/bin\n"
              << "TARGET  = divifetch\n\n"

              << ".PHONY: all header clean install uninstall run\n\n"

              << "all: $(TARGET)\n\n"

              << "header: build/header\n"
              << "\t./build/header\n\n"

              << "build:\n"
              << "\tmkdir -p build\n\n"

              << "clean:\n"
              << "\trm -rf build/modules\n"
              << "\trm build/header $(TARGET)\n\n"

              << "install: $(TARGET)\n"
              << "\tmkdir -p $(DESTDIR)\n"
              << "\tinstall -Dm755 $(TARGET) $(DESTDIR)/$(TARGET)\n\n"

              << "uninstall:\n"
              << "\trm $(DESTDIR)/$(TARGET)\n\n"

              << "run: $(TARGET)\n"
              << "\t./$(TARGET)\n\n";

    std::string lib_deps, link_objs, all_linker_flags;

    for (size_t i = 0; i < out_needed.functions_all.size(); i++) {
        MakeTemplate current_tmpl;

        parse_make_module_config("modules/"+out_needed.functions_all[i]+"/module.conf", templates, current_tmpl);

        std::string src = "modules/" + out_needed.functions_all[i] + "/" + current_tmpl.source_file;
        std::string obj = "build/modules/" + out_needed.functions_all[i] + "/module" + current_tmpl.object_extension;
        std::string lib = "build/lib" + out_needed.functions_all[i] + ".a";

        make_file << obj << ": " << src << " | build\n"
                  << "\tmkdir -p build/modules/" << out_needed.functions_all[i] << "\n"
                  << "\t" << current_tmpl.command << "\n\n";

        if (current_tmpl.archive == "yes") {
            make_file << lib << ": " << obj << "\n"
                      << "\tar rcs $@ $^\n\n";
            lib_deps += " " + lib;
            link_objs += " -l" + out_needed.functions_all[i];
        } else {
            lib_deps += " " + obj;
            link_objs += " " + obj;
        }

        if (!current_tmpl.linker_flags.empty())
            all_linker_flags += " " + current_tmpl.linker_flags;
    }

    make_file << out_header_file_path << ": build/header\n"
              << "\t./build/header\n\n"

              << "build/header: build/header.c" << lib_deps << "\n"
              << "\t$(CC) $(CFLAGS) -I. "
              << "build/header.c -Lbuild"
              << link_objs << all_linker_flags
              << " -o build/header\n\n"

              << "$(TARGET): " << out_source_file_path << " " << out_header_file_path << lib_deps << "\n"
              << "\t$(CC) $(CFLAGS) -I. "
              << out_source_file_path << " -Lbuild"
              << link_objs << all_linker_flags
              << " -o $(TARGET)\n";
}

void output_help(std::string current_executable_name) {
    std::cout << "usage: " << current_executable_name << " [OPTIONS]\n"
              << "commands:\n"
              << "      source      generate only the source code for the fetch program\n"
              << "      config      generate an example config file\n"
              << "      make        generate a Makefile\n\n"

              << "multiple commands can be specified (default: source make)\n\n"

              << "options:\n"
              << "      -h,  --help                display this help and exit\n"
              << "      -c,  --config <file>       specify a fetch config file (default: config.conf)\n"
              << "      -cm, --make-config <file>  specify the make config file (default: make.conf)\n"
              << "      -os, --out-source <file>   specify where to output the source code (default: fetch.c)\n"
              << "      -oh, --out-header <file>   specify where to output the header file for the source code (default: fetch.h)\n"
              << "      -oc, --out-config <file>   specify where to output the example config file (default: config.conf.example)\n"
              << "      -om, --out-make <file>     specify where to output the Makefile (default: Makefile)\n\n"

              << "-c can be specified multiple times for random runtime selection between them\n";
}

int main(int argc, char* argv[]) {
    std::vector<std::string> config_file_paths;
    std::string make_config_file_path = "make.conf";
    std::string out_config_file_path = "config.conf.example";
    std::string out_source_file_path = "fetch.c";
    std::string out_header_file_path = "fetch.h";
    std::string out_make_file_path = "Makefile";

    std::vector<std::string> subcommands;

    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "-h" || arg == "--help") {
            output_help(argv[0]); return 0;
        } else if (arg == "source" || arg == "config" || arg == "make") {
            add_unique(subcommands, arg);
        } else if (arg == "-c" || arg == "--config") {
            if (i+1 < argc) config_file_paths.push_back(argv[++i]);
            else { print_error(arg+" requires an argument"); }
        } else if (arg == "-cm" || arg == "--make-config") {
            if (i+1 < argc) make_config_file_path = argv[++i];
            else { print_error(arg+" requires an argument"); }
        } else if (arg == "-os" || arg == "--out-source") {
            if (i+1 < argc) out_source_file_path = argv[++i];
            else { print_error(arg+" requires an argument"); }
        } else if (arg == "-oh" || arg == "--out-header") {
            if (i+1 < argc) out_header_file_path = argv[++i];
            else { print_error(arg+" requires an argument"); }
        } else if (arg == "-oc" || arg == "--out-config") {
            if (i+1 < argc) out_config_file_path = argv[++i];
            else { print_error(arg+" requires an argument"); }
        } else if (arg == "-om" || arg == "--out-make") {
            if (i+1 < argc) out_make_file_path = argv[++i];
            else { print_error(arg+" requires an argument"); }
        } else {
            print_warning("unknown argument '"+arg+"', ignoring");
        }
    }

    if (!config_file_paths.size()) config_file_paths.push_back("config.conf");

    if (!subcommands.size()) { subcommands.push_back("source"); subcommands.push_back("make"); }

    if (is_present_in_vector(subcommands, "config")) {
        output_example_config(out_config_file_path);
    }

    if (is_present_in_vector(subcommands, "source")) {
        std::ofstream fetch_file(out_source_file_path.c_str());
        std::ofstream header_gen_file("build/header.c");
        std::vector<ConfigSource> configs_sources;
        ConfigSourceNeeded out_needed;

        out_needed.imports.push_back("stdio.h");

        if (config_file_paths.size() > 1) {
            out_needed.imports.push_back("stdlib.h");
            out_needed.imports.push_back("time.h");
        }

        for (size_t i = 0; i < config_file_paths.size(); i++) {
            ConfigSource current_config_source;
            parse_fetch_config(config_file_paths[i], current_config_source);
            assess_needed_for_fetch(out_needed, current_config_source);
            configs_sources.push_back(current_config_source);
        }

        output_fetch_main(fetch_file, configs_sources, out_needed);
        output_fetch_header_gen(header_gen_file, out_header_file_path, out_needed);

        fetch_file.close();
        std::cout << "generated the source code for the fetch program " << out_source_file_path << "\n";
    }

    if (is_present_in_vector(subcommands, "make")) {
        std::ofstream make_file(out_make_file_path.c_str());
        ConfigSourceNeeded out_needed;

        for (size_t i = 0; i < config_file_paths.size(); i++) {
            ConfigSource current_config_source;
            parse_fetch_config(config_file_paths[i], current_config_source);
            assess_needed_for_fetch(out_needed, current_config_source);
        }

        output_makefile(make_file, make_config_file_path, out_needed, out_source_file_path, out_header_file_path);

        make_file.close();
        std::cout << "generated the Makefile " << out_make_file_path << "\n";
    }

    return 0;
}
