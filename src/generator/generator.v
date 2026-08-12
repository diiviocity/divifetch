import strings
import os
import time
import math

pub struct SourceDefenition {
	mut:
	id      int
	execute string
}

pub struct PrintEntry {
	mut:
	text string
	args string
}

pub struct ConfigSourceNeeded {
	mut:
	imports             []string
	defenitions         []SourceDefenition
	functions_all       []string
	functions_runtime   []string
	functions_buildtime []string
}

fn assess_needed_for_fetch(mut out_needed ConfigSourceNeeded, source ConfigSource) {
	for entry in source.entries {
		if entry.type != 'static' {
			if !os.exists('modules/${entry.type}/module.h') { print_error('couldn\'t find module header \'${entry.type}\'') }
			add_unique(mut out_needed.functions_all, entry.type)
			if entry.build_time == 'yes' { add_unique(mut out_needed.functions_buildtime, entry.type) }
			else                         { add_unique(mut out_needed.functions_runtime, entry.type) }
		}
	}
	if source.config.execute.len > 0 { add_unique(mut out_needed.imports, 'unistd.h') }
}

fn build_print_text(art_line string, entry SourceEntry) string {
	return art_line + entry.key_prefix + entry.key + entry.key_suffix + entry.value_prefix + entry.value + entry.value_suffix + '\\n'
}

fn output_fetch_print(source ConfigSource, mut out_needed ConfigSourceNeeded) string {
	mut out := '\tchar _buf[${source.config.buffer_size}];\n'

	mut art_lines_o, mut art_width := parse_file_to_vector(source.config.art_file), source.config.art_width
	for art_line in art_lines_o { art_width = math.max(visible_width(art_line)+source.config.art_padding, art_width) }

	art_lines_o << [strings.repeat_string(' ', art_width)].repeat(min_0(source.entries.len - art_lines_o.len))

	mut art_lines := []string{}
	for art_line in art_lines_o {
		art_width_line := visible_width(art_line)
		art_padding := min_0(art_width - art_width_line)
		art_lines << source.config.art_prefix + art_line + strings.repeat_string(' ', art_padding) + source.config.art_suffix
	}

	mut print_entries := []PrintEntry{}
	mut print_entry := PrintEntry{}
	for i, entry in source.entries {
		if (entry.build_time != "yes" && entry.type != 'static') || entry.new_print == "yes" {
			print_entries << print_entry
			print_entry = PrintEntry{}
		}

		if entry.type == 'static' {
			print_entry.text += build_print_text(art_lines[i], entry)
		} else {
			module_arg := if entry.value.len > 0 { '"${entry.value}", _buf, sizeof(_buf)' }
			              else { '_buf, sizeof(_buf)' }

			mut curr_entry := entry
			curr_entry.value = "%s"

			print_entry.text += build_print_text(art_lines[i], curr_entry)
			if entry.build_time == "yes" {
				mut defenition := SourceDefenition{}
				defenition.id = out_needed.defenitions.len
				defenition.execute = '${entry.type}_module_preset(${module_arg})'
				out_needed.defenitions << defenition
				print_entry.args += ', BUILD_TIME_${defenition.id}'
			} else {
				print_entry.args += ', ${entry.type}_module_preset(${module_arg})'
			}

		}
	}

	if art_lines_o.len > source.entries.len && source.entries.len > 0 {
		for i in source.entries.len .. art_lines_o.len {
			print_entry.text += '${art_lines[i]}\\n'
		}
	}

	print_entries << print_entry

	for entry in print_entries {
		if entry == PrintEntry{} { continue }
		out += if entry.args == "" { '\tfputs("${escape_string(entry.text)}", stdout);\n' }
		       else                { '\tprintf("${escape_string(entry.text)}"${entry.args});\n' }
	}

	if source.config.execute.len > 0 {
		out += '\texecl("${source.config.execute}", "${source.config.execute}", NULL);\n'
	}

	return out
}

fn output_fetch_header_gen(header_file_path string, out_needed ConfigSourceNeeded) string {
	mut out := '/* generated at ${time.now()} */\n'

	for function_buildtime in out_needed.functions_buildtime {
		out += '#include "modules/${function_buildtime}/module.h"\n'
	}
	out += '#include <stdio.h>
#include <time.h>
int main() {
	char _buf[512];
	FILE *headerfile = fopen("${header_file_path}", "w");
	if (headerfile == NULL) { fputs("couldn\'t open ${header_file_path}", stderr); return 0; }
	char _date_buf[100];
	time_t now = time(NULL);
	struct tm *local = localtime(&now);
	strftime(_date_buf, sizeof(_date_buf), "%Y-%m-%d %H:%M:%S", local);
	fprintf(headerfile, "/* generated at %s */\\n", _date_buf);\n'

	out += '\tfputs("'
	for function_runtime in out_needed.functions_runtime {
		out += '#include \\"modules/${function_runtime}/module.h\\"\\n'
	}
	for import_ in out_needed.imports {
		out += '#include <${import_}>\\n'
	}
	out += '", headerfile);\n'

	for defenition in out_needed.defenitions {
		out += '\tfprintf(headerfile, "#define BUILD_TIME_${defenition.id} \\"%s\\"\\n", ${defenition.execute});\n'
	}

	return out + '\treturn 0;\n}'
}

fn output_fetch_main(sources []ConfigSource, mut out_needed ConfigSourceNeeded) string {
	mut out := '/* generated at ${time.now()} */
#include "fetch.h"
int main() {\n'

	if sources.len == 1 {
		out += output_fetch_print(sources[0], mut out_needed)
	} else {
		out += '\tstruct timespec ts;
	clock_gettime(CLOCK_REALTIME, &ts);
	srand(ts.tv_nsec);
	int chosen_random_config = rand() % ${sources.len};
	switch(chosen_random_config) {\n'

		for i, source in sources {
			out += '\tcase ${i}: {
	${output_fetch_print(source, mut out_needed)}
	break;
	}\n'
		}

		out += '\t}\n'
	}

	return out + '\treturn 0;\n}\n'
}

fn output_example_config() string {
	os_name := exec("source /etc/os-release && echo $NAME")
	cpu := exec("grep -m 1 'model name' /proc/cpuinfo")

	mut out := ';;;; THE EXAMPLE CONFIG FILE

; read the documentation:
; https://git.divio.city/diviocity/divifetch/wiki

(config (art-width 45)
        (art-file "ascii/cat.txt")
        (art-prefix "\\033[1m")
        (art-suffix "\\033[0m")
        (key-prefix "\\033[1m\\033[34m")
        (key-suffix "\\033[0m: ")
        (value-prefix "")
        (value-suffix ""))


(plain divifetch)
(plain ---------)
(static OS "${os_name}")

(kernel)
(packages-pacman Packages)
(shell (build-time yes))
(terminal (build-time yes))
(wm (build-time yes))
(static CPU "${cpu}")\n'

	for gpu in exec("lspci | grep -i vga").split_into_lines() {
		out += '(static GPU "${gpu}")\n'
	}

	out += '(memory)\n'

	for mount in exec("awk '{print $2}' /etc/fstab | grep '^/'").split_into_lines() {
		if !out.starts_with("#") {
			out += '(mount "Mount (${mount})" "${mount}")\n'
		}
	}

	return out + '(battery)
(static Notice "modify the configuration file!")

(break)

(colors_normal)
(colors_bright)\n'
}

fn output_buildfile(opt CliOpts, out_needed ConfigSourceNeeded, initial_command string) string {
	mut config := BuildConfig{}
	mut templates := map[string]BuildTemplate{}

	parse_build_templates_config(opt.build_conf, mut config, mut templates)

	mut out := "${config.exec}

/* generated at ${time.now()} */

import build

const target = '${config.target}'
const target_head = '${config.target_head}'
const dest_dir = '${config.dest_dir}'
const build_dir = '${config.build_dir}'

const cc = '${config.cc}'
const cflags = '${config.cflags}'

mut context := build.context(default: '${config.default}')
${config.custom}
context.task(name: 'help', run: fn (self build.Task) ! {
	println(\"${output_help_build(initial_command)}\")
	exit(0)
})

context.task(name: 'generator', run: fn (self build.Task) ! {
	system('v -n -w -o ./generator ./src/generator')
	println('built ./generator')
})

context.task(name: 'build', depends: ['\${build_dir}/\${target}'], run: fn (self build.Task) ! {})

context.task(name: 'clean', run: fn (self build.Task) ! {
	if exists('\${build_dir}') {
		rmdir_all('\${build_dir}') or { panic(err) }
	}
})

context.task(name: 'run', depends: ['build'], run: |self| system('./\${build_dir}/\${target}'))

context.task(name: 'header', depends: ['\${build_dir}/\${target_head}'], run: fn (self build.Task) ! {
	println('> ./\${build_dir}/\${target_head}')
	system('./\${build_dir}/\${target_head}')
})

context.task(name: 'install', depends: ['build'], run: fn (self build.Task) ! {
	mkdir_all(dest_dir) or { panic(err) }
	system('install -Dm755 \${build_dir}/\${target} \${dest_dir}/\${target}')
})

context.task(name: 'uninstall', run: fn (self build.Task) ! {
	rm('\${dest_dir}/\${target}') or { panic(err) }
})

context.task( name: 'regen', run: fn (self build.Task) ! {
	println(\"> ${escape_string(initial_command)}\")
	system(\"${escape_string(initial_command)}\")
})

context.task(name: 'update', depends: ['clean', 'header', 'run'], run: fn (self build.Task) ! {})
context.task(name: 'crun', depends: ['clean', 'run'], run: fn (self build.Task) ! {})\n\n"

	mut lib_deps := []string{}
	mut link_objs := ''
	mut all_linker_flags := ''

	for function in out_needed.functions_all {
		mut tmpl := BuildTemplate{}

		parse_build_module_config('modules/${function}/module.conf', templates, mut tmpl)

		src := 'modules/${function}/${tmpl.source_file}'
		obj := '\${build_dir}/modules/${function}/module${tmpl.object_extension}'
		lib := '\${build_dir}/lib${function}.a'

		out += "context.artifact(
	name: '${obj}'
	run: fn (self build.Task) ! {
		source_file := '${src}'
		output_file := '${obj}'
		if !exists('\${source_file}') { panic('\${source_file} doesn\\'t exist') }
		mkdir_all('\${build_dir}/modules/${function}') or { panic(err) }
		system('${tmpl.command}')\n"

		if tmpl.archive == "yes" {
			out += "\t\tsystem('ar rcs ${lib} ${obj}')\n"
			link_objs += " -l${function}"
		} else {
			link_objs += ' ${obj}'
		}

		lib_deps << obj

		if tmpl.linker_flags.len > 0 {
			all_linker_flags += ' ${tmpl.linker_flags}'
		}

		out += "\t}\n)\n\n"
	}

	lib_deps_str := "'"+lib_deps.join("', '")+"'"

	return out + "context.artifact(
	name: '${opt.out_src_fetch_head}'
	depends: ['\${build_dir}/\${target_head}']
	run: fn (self build.Task) ! {
		println('> ./\${build_dir}/\${target_head}')
		system('./\${build_dir}/\${target_head}')
	}
)

context.artifact(
	name: '\${build_dir}/\${target_head}'
	depends: [${lib_deps_str}]
	run: fn (self build.Task) ! {
		source_file := 'src/header.c'
		if !exists('\${source_file}') { panic('\${source_file} doesn\\'t exist') }
		system('\${cc} \${cflags} -I. \${source_file} -L\${build_dir} ${link_objs}${all_linker_flags} -o \${build_dir}/\${target_head}')
		println('built \${target_head} in \${build_dir}')
	}
)

context.artifact(
	name: '\${build_dir}/\${target}'
	depends: ['${opt.out_src_fetch_head}', ${lib_deps_str}]
	run: fn (self build.Task) ! {
		source_file := '${opt.out_src_fetch}'
		if !exists('\${source_file}') { panic('\${source_file} doesn\\'t exist') }
		system('\${cc} \${cflags} -I. \${source_file} -L\${build_dir}${link_objs}${all_linker_flags} -o \${self.name}')
		println('built \${target} in \${build_dir}')
	}
)

context.run()\n"
}

fn build_help_options(options [][]string) string {
	mut lines := []string{}
	for option in options {
		lines << '  \033[1m${option[0]}\033[0m'
		for line in option[1].split('\n') { lines << '    ${line}' }
	}
	return lines.join('\n')
}

fn output_help_generator() string {
	return 'usage: ./generator [OPTIONS] *source configs*\n\noptions:\n' + build_help_options([
		['-h, --help',    'display this help and exit'],
		['-v, --version', 'display the version number and exit'],
		['-S, --source',  'generate the fetch and header generator source code'],
		['-s',            'specify a config file for source\nif multiple are specified they will be randomly selected at runtime\n(default: config.conf)'],
		['-os',           'specify where to output the source code of the fetch program\n(default: src/fetch.c)'],
		['-ohg',          'specify where to output the source code of the header file generator\n(default: src/header.c)'],
		['-oh',           'specify where to output the header file for the fetch program\n(default: src/fetch.h)'],
		['-B, --build',   'generate a build script'],
		['-b',            'specify the config file for build\n(default: build.conf)'],
		['-ob',           'specify where to output the build script\n(default: build.vsh)'],
		['-R, --run',     'execute the the build script'],
		['-r',            'specify arguments to execute the build script with'],
		['-C, --genconf', 'generate generate an example config file'],
		['-oc',           'specify where to output the example config\n(default: config.conf)'],
	])
}

fn output_help_build(regen string) string {
	return 'divifetch builder (generated at ${time.now()})\n\ntasks:\n' + build_help_options([
		['help',      'display this help and exit'],
		['clean',     'clean the build directory'],
		['build',     'build the fetch binary'],
		['run',       'execute the fetch binary'],
		['header',    'execute the header file generator'],
		['generator', 'build the divifetch generator'],
		['regen',     'execute the command that generated this script again\n(${regen})'],
		['install',   'install the fetch binary to \${dest_dir}'],
		['uninstall', 'uninstall the fetch binary from \${dest_dir}'],
	]) + '\n\naliases:\n' + build_help_options([
		['crun',      'clean run'],
		['update',    'clean header run'],
	])
}
