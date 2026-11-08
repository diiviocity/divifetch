// main.v — the generator entry point: the cli flags, the task wiring
// (source, build, run) and the help. everything else lives at its
// own file: config_parser*.v read, generator.v writes, utils.v moves bits.
// the divifetch generator.
module main

import flag
import os

const generator_version = 'divifetch generator v1.0.0'

// ─── cli ──────────────────────────────────────────────────────────────────

struct CliOpts {
mut:
	show_help      bool                        @[short: h; long: help]
	show_version   bool                        @[short: v; long: version]
	task_source    bool                        @[short: S; long: source]
	source_confs   []string                    @[only: s; tail]
	out_src        string = '.tmp/run.zig'     @[long: os]
	out_run_src    string = '.tmp/run-run.zig' @[long: orun]
	task_build     bool                        @[short: B; long: build]
	build_conf     string = 'build.conf'       @[only: b]
	out_build      string = 'build.vsh'        @[long: ob]
	task_build_run bool                        @[short: R; long: run]
	build_run_args string                      @[only: r]
	out_headgen    string = '.tmp/headgen.zig' @[long: ohg]
	out_bake       string = '.tmp/bake.zig'    @[long: oh]
}

// ─── main ─────────────────────────────────────────────────────────────────

fn output_help() string {
	return 'divifetch generator

builds run.zig from a config.lip and the module.lips it references

usage:
    ./generator [flags] [config files]

options:
    -h --help            display this help and exit
    -v --version         display the version number and exit
    -S --source          generate the source of the fetch entry (default task)
    -s <file>            a config file for source (default: config.lip), repeatable
    -os <file>           where the source is written (default: run.zig)
    -orun <file>         where the divifetch-run twin source goes, when
                         the config spells (run ...) forms
    -B --build           generate the build script
    -b <file>            a config file for build (default: build.conf)
    -ob <file>           where the build script is written (default: build.vsh)
    -R --run             execute the freshly generated build script
    -r <args>            arguments passed to the build script
    -ohg <file>          where the build-time bake program is written (default: headgen.zig)

with no task, this runs source, build and run, like the C generator did.
builds and runs also go standalone: v run build.vsh build
(a build with :build-time entries runs headgen first, and its bake.zig
feeds run.zig its baked values)'
}

fn print_error(msg string) {
	eprintln('generator: ${msg}')
}

// v_backend_paths swaps the default .zig output spellings for the V
// backend's, where the generated program is a directory of its own: the
// entry source, the bake const file, and — the twin — its own dir, one
// main per program. a flag the build spelled keeps its value.
fn v_backend_paths(mut opt CliOpts) {
	if opt.out_src == '.tmp/run.zig' {
		opt.out_src = '.tmp/vfetch/run.v'
	}
	if opt.out_run_src == '.tmp/run-run.zig' {
		opt.out_run_src = '.tmp/vfetch-run/run-run.v'
	}
	if opt.out_bake == '.tmp/bake.zig' {
		opt.out_bake = '.tmp/vfetch/bake.v'
	}
}

// write_out writes one generated file, creating its directory first, so a
// .tmp/ path needs no prep.
fn write_out(path string, contents string) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, contents)!
}

fn main() {
	mut opt, no_matches := flag.to_struct[CliOpts](os.args, skip: 1)!
	if no_matches.len > 0 {
		print_error('unknown flags: ${no_matches.join(', ')}')
		exit(1)
	}
	if opt.show_help || opt.show_version {
		if opt.show_help {
			println(output_help())
		}
		if opt.show_version {
			println(generator_version)
		}
		return
	}
	if !opt.task_source && !opt.task_build && !opt.task_build_run {
		// no task: the C generator's default — source, then build, then run.
		opt.task_source, opt.task_build, opt.task_build_run = true, true, true
	}
	if opt.task_source && opt.source_confs.len == 0 {
		opt.source_confs << 'config.lip'
	}
	// the source is parsed for the fetch source and for the build script
	// alike: only the modules it references get compiled into it.
	mut cfg := Config{
		sources: []
		modules: map[string]ModuleLip{}
		warned:  map[string]bool{}
	}

	mut has_headgen := false
	if opt.task_source || opt.task_build {
		cfg = collect_config(opt.source_confs) or {
			print_error(err.msg())
			exit(1)
		}
		for source in cfg.sources {
			for e in source.entries {
				if e.static_ { continue }
				if e.bt_id >= 0 && cfg.modules[e.kind].language != 'v' {
					has_headgen = true
				}
			}
		}
	}
	if opt.task_source {
		if backend_of(cfg) == 'v' {
			v_backend_paths(mut opt)
			src_v := output_source_v(&cfg, opt.source_confs, false) or {
				print_error(err.msg())
				exit(1)
			}
			write_out(opt.out_src, src_v) or {
				print_error('cannot write ${opt.out_src}: ${err.msg()}')
				exit(1)
			}
			// bake wrappers for build-time V preset modules: a single
			// importable module cannot be `v run` directly, so each one
			// gets a tiny main that calls its preset with the entry args.
			mut seen_wrap := map[string]bool{}
			for source in cfg.sources {
				for e in source.entries {
					if e.static_ || e.bt_id < 0 { continue }
					lip := cfg.modules[e.kind]
					if lip.language != 'v' || lip.fname == '' { continue }
					if e.kind in seen_wrap { continue }
					seen_wrap[e.kind] = true
					mut w := ''
					if lip.arg_is_list || lip.arg != '' {
						w += 'import os\n'
					}
					w += 'import ${e.kind}\n\n'
					w += 'fn main() {\n'
					if lip.arg_is_list {
						w += '    if os.args.len > 1 {\n'
						w += '        println(${e.kind}.preset(os.args[1..]))\n'
						w += '    } else {\n'
						w += '        println(${e.kind}.preset([]string{}))\n'
						w += '    }\n'
					} else if lip.arg != '' {
						w += '    if os.args.len > 1 {\n'
						w += '        println(${e.kind}.preset(os.args[1]))\n'
						w += '    } else {\n'
						w += "        println(${e.kind}.preset(''))\n"
						w += '    }\n'
					} else {
						w += '    println(${e.kind}.preset())\n'
					}
					w += '}\n'
					write_out('.tmp/vfetch-bake-${e.kind}.v', w) or {
						print_error('cannot write bake wrapper: ${err.msg()}')
						exit(1)
					}
				}
			}
			println('generated the fetch entry source: ${opt.out_src}')
			if sources_have_runs(&cfg) {
				run_v := output_source_v(&cfg, opt.source_confs, true) or {
					print_error(err.msg())
					exit(1)
				}
				write_out(opt.out_run_src, run_v) or {
					print_error('cannot write ${opt.out_run_src}: ${err.msg()}')
					exit(1)
				}
				println('generated the divifetch-run twin source: ${opt.out_run_src}')
			}
		} else {
			write_out(opt.out_src, output_source(&cfg, opt.source_confs, opt.out_src, opt.out_bake, false)) or {
				print_error('cannot write ${opt.out_src}: ${err.msg()}')
				exit(1)
			}
			println('generated the fetch entry source: ${opt.out_src}')
			if sources_have_runs(&cfg) {
				write_out(opt.out_run_src, output_source(&cfg, opt.source_confs, opt.out_run_src, opt.out_bake, true)) or {
					print_error('cannot write ${opt.out_run_src}: ${err.msg()}')
					exit(1)
				}
				println('generated the divifetch-run twin source: ${opt.out_run_src}')
			}
			write_ext_projects(cfg) or {
				print_error('cannot write the extern crate projects: ${err.msg()}')
				exit(1)
			}
			if has_headgen {
				write_out(opt.out_headgen, output_headgen(&cfg, opt.source_confs)) or {
					print_error('cannot write ${opt.out_headgen}: ${err.msg()}')
					exit(1)
				}
				println('generated the build-time bake program: ${opt.out_headgen}')
			}
		}
	}
	if opt.task_build {
		conf := parse_build_conf(resolve_build_conf(opt.build_conf)) or {
			print_error(err.msg())
			exit(1)
		}
		buildfile := output_buildfile(conf, build_regen_args(opt), &cfg, opt.out_src, opt.out_bake, opt.out_run_src) or {
			print_error(err.msg())
			exit(1)
		}
		write_out(opt.out_build, buildfile) or {
			print_error('cannot write ${opt.out_build}: ${err.msg()}')
			exit(1)
		}
		os.chmod(opt.out_build, 0o755)!
		println('generated the build script: ${opt.out_build}')
	}
	if opt.task_build_run {
		mut argv := ['v', 'run', opt.out_build]
		if opt.build_run_args != '' {
			argv << opt.build_run_args.split(' ')
		}
		println('running the build script\n> ${argv.join(' ')}')
		code := os.system_args(argv)
		if code != 0 {
			print_error('the build script exited with status ${code}')
			exit(1)
		}
	}
}
