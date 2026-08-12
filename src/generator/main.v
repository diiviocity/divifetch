import flag
import os

struct CliOpts {
	mut:
	show_help           bool                       @[short: h; long: help]
	show_version        bool                       @[short: v; long: version]
	task_source         bool                       @[short: S; long: source]
	source_confs        []string = ['config.conf'] @[only:  s; tail]
	out_src_fetch       string = 'src/fetch.c'     @[long:  os]
	out_src_head_gen    string = 'src/header.c'    @[long:  ohg]
	out_src_fetch_head  string = 'src/fetch.h'     @[long:  oh]
	task_build          bool                       @[short: B; long: build]
	build_conf          string = "build.conf"      @[only:  b]
	out_build           string = 'build.vsh'       @[long:  ob]
	task_build_run      bool                       @[short: R; long: run]
	build_run_args      string                     @[only:  r]
	task_genconf        bool                       @[short: C; long: genconf]
	out_conf            string = 'config.conf'     @[long:  oc]
}

fn main() {
	mut opt, no_matches := flag.to_struct[CliOpts](os.args, skip: 1)!
	if no_matches.len > 0 { print_error('unknown flags: ${no_matches.join(", ")}') }

	if opt.show_help { print_exit(output_help_generator()) }
	if opt.show_version { print_exit('divifetch generator v3.0.0') }

	mut sources := []ConfigSource{}
	mut needed := ConfigSourceNeeded{imports: if opt.source_confs.len > 1 { ['stdio.h', 'stdlib.h', 'time.h'] } else { ['stdio.h'] }}

	if !(opt.task_genconf || opt.task_source || opt.task_build || opt.task_build_run) {
		opt.task_source, opt.task_build, opt.task_build_run = true, true, true
	}

	if opt.task_source || opt.task_build {
		for config_file in opt.source_confs {
			mut source := ConfigSource{}
			parse_source_config(config_file, mut source)
			assess_needed_for_fetch(mut needed, source)
			sources << source
		}
	}

	if opt.task_genconf {
		write_file(opt.out_conf, output_example_config(), 'generated the example config file')
	}
	if opt.task_source {
		write_file(opt.out_src_fetch, output_fetch_main(sources, mut needed), 'generated the source code for the fetch program')
		write_file(opt.out_src_head_gen, output_fetch_header_gen(opt.out_src_fetch_head, needed), 'generated the source code for the header file generator')
	}
	if opt.task_build {
		mut command := executable_command_for_path(os.args[0])
		if os.args.len > 1 { command += ' ' + os.args[1..].join(' ') }
		write_file(opt.out_build, output_buildfile(opt, needed, command), 'generated the build script')
	}
	if opt.task_build_run {
		mut command := executable_command_for_path(opt.out_build)
		if opt.build_run_args.len > 0 { command += ' ' + opt.build_run_args }
		println('running the build script\n> ${command}')
		os.system(command)
	}
}
