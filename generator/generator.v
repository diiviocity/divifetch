// generator.v — the emitters: run.zig and headgen.zig for the fetch, the
// build.vsh that x.imp drives, the example config, and the helpers they
// share (the print groups, the art column, entry calls).
// the divifetch-zig generator.
module main

import os
import strings

fn v_escape(s string) string {
	return s.replace('\\', '\\\\').replace("'", "\\'")
}

// build_regen_args is the generator invocation the regen flow runs, rebuilt
// from the flags this generator pass was called with — the outputs spelled
// out too, so a script built elsewhere regenerates where it was told to.
fn build_regen_args(opt CliOpts) []string {
	mut args := ['v', 'run', 'generator', '-S', '-os', opt.out_src, '-ohg', opt.out_headgen, '-oh',
		opt.out_bake, '-orun', opt.out_run_src]
	for conf in opt.source_confs {
		args << '-s'
		args << conf
	}
	return args
}

// template_expand fills the literals upstream's module.conf templates
// carried: ${cc}, ${source_file} and ${output_file} are baked at generation
// time, so the emitted build script runs prepared strings.
fn template_expand(command string, cc string, source_file string, output_file string) string {
	return command.replace('$' + '{cc}', cc).replace('$' + '{source_file}', source_file).replace('$' + '{output_file}', output_file)
}

// CompileStep is one pre-zig work unit the flow runs before linking
// anything: an argv step (rustc's staticlib) or a shell string (a template
// override, which may carry pipes and redirections).
struct CompileStep {
mut:
	argv  []string
	shell string
}

// compile_steps walks every referenced compiled module (c, cpp, rust, d) in
// config order: rust and d build their objects with the default recipe
// unless a template overrides it, and c/cpp with a template override run
// their command. the d recipe compiles betterC — no runtime to link —
// unless the lip carried :std, which compiles full d. zig-built c/cpp
// sources without a template need no step.
fn compile_steps(cfg &Config, default_cc string) []CompileStep {
	mut steps := []CompileStep{}
	mut seen := map[string]bool{}
	for source in cfg.sources {
		for e in source.entries {
			if e.static_ { continue }
			kind := e.kind
			if seen[kind] { continue }
			lip := cfg.modules[kind]
			if lip.language == 'rust' && lip.deps_ext.len > 0 { continue }
			if lip.language !in ['c', 'cpp', 'rust', 'd'] { continue }
			seen[kind] = true
			object_file := 'modules/${kind}/${lip.source.all_before_last('.')}${lip.object_extension}'
			if lip.command != '' {
				steps << CompileStep{ shell: template_expand(lip.command, cc_for(lip.language, default_cc), 'modules/${kind}/${lip.source}', object_file) }
			} else if lip.language == 'rust' {
				steps << CompileStep{
					argv: ['rustc', '--crate-type', 'staticlib', '-C', 'opt-level=2', '-o',
						object_file, 'modules/${kind}/${lip.source}']
				}
			} else if lip.language == 'd' {
				steps << CompileStep{
					argv: if lip.deps_std {
						['dmd', '-c', '-of=${object_file}', 'modules/${kind}/${lip.source}']
					} else {
						['dmd', '-c', '-betterC', '-of=${object_file}',
							'modules/${kind}/${lip.source}']
					}
				}
			}
		}
	}
	return steps
}

// cc_for answers the ${cc} of a template: theModuleConf cc field wins, with
// the per-language tool echoing upstream's default answers.
fn cc_for(language string, conf_cc string) string {
	if conf_cc != '' {
		return conf_cc
	}
	return match language {
		'rust' { 'rustc' }
		'd' { 'dmd' }
		'cpp' { 'zig c++' }
		else { 'zig' }
	}
}

// extra_link_flags gathers everything that rides the link line in config
// order: each referenced module's :linker-flags, the libraries its :deps
// names (-l<dep>), and :std's own answer for the language. a module that
// declares neither links bare — the fetch adds nothing on its own.
fn extra_link_flags(cfg &Config) []string {
	mut flags := []string{}
	mut seen := map[string]bool{}
	for source in cfg.sources {
		for e in source.entries {
			if e.static_ || seen[e.kind] { continue }
			seen[e.kind] = true
			lip := cfg.modules[e.kind]
			for flag in lip.linker_flags {
				flags << flag
			}
			for flag in dep_flags(lip) {
				if flag in seen { continue }
				seen[flag] = true
				flags << flag
			}
		}
	}
	return flags
}

// dep_flags answers the -l spellings a compiled module's deps ask for:
// one per named library, and :std through the language's own answer. a
// rust module with :ext builds through cargo's staticlib; when std rides
// along, its stable-toolchain backtrace branches keep unwind references —
// libunwind closes those without any nightly. a no_std crate (the
// no-default-features spelling, :std off the deps) links bare with the
// panic-abort archive carrying it.
fn dep_flags(lip ModuleLip) []string {
	mut out := []string{}
	if lip.deps_std {
		out << match lip.language {
			'd' { ['-lphobos2', '-lc'] }
			else { ['-lc'] }
		}
	}
	for lib in lip.deps_libs {
		out << '-l${lib}'
	}
	if lip.language == 'rust' && lip.deps_ext.len > 0 && lip.deps_std {
		out << '-lunwind'
	}
	return out
}

// object_outputs names the files the pre-zig steps produce: the compiled
// rust static libraries and dmd objects, and every module that runs a
// template command. zig links these beside its own c and cpp sources.
fn object_outputs(cfg &Config) []string {
	mut out := []string{}
	mut seen := map[string]bool{}
	for source in cfg.sources {
		for e in source.entries {
			if e.static_ || seen[e.kind] { continue }
			kind := e.kind
			lip := cfg.modules[kind]
			if lip.language !in ['c', 'cpp', 'rust', 'd'] { continue }
			seen[kind] = true
			// a module whose recipe is a template overrides compiles to its
			// object file, which zig then links; rust and d always do. an
			// ext-dep rust module collects cargo's staticlib archive instead.
			if lip.language in ['rust', 'd'] || lip.command != '' {
				ext_a := lip.language == 'rust' && lip.deps_ext.len > 0
				out << 'modules/${kind}/${lip.source.all_before_last('.')}${if ext_a {
					'.a'
				} else {
					lip.object_extension
				}}'
			}
		}
	}
	return out
}

// output_buildfile writes build.vsh, built on x.imp: a regen flow that
// reruns the generator, a build flow that bakes what headgen says and the
// V entries print, then compiles the fetch (feeding the c and cpp sources
// to zig directly, linking everything else's objects), clean and the
// install pair, and the auto run. everything lands under :build-dir; the
// custom conf code rides the consts.
fn output_buildfile(conf BuildConf, regen_args []string, cfg &Config, out_src string, out_bake string, out_run_src string) string {
	out_src_dir := os.dir(out_src)
	c_list := c_modules(cfg)
	mut ext_seen := map[string]bool{}
	mut out := strings.new_builder(2048)
	out.write_string('${conf.exec}\n\n')
	out.write_string('// build.vsh — generated by the divifetch-zig generator (edit build.conf instead).\n')
	out.write_string('\n')
	out.write_string('import x.imp\n')
	out.write_string('import os\n\n')
	out.write_string("const build_dir = '${v_escape(conf.build_dir)}'\n")
	out.write_string("const target_exe = os.join_path_single(build_dir, '${v_escape(conf.target)}')\n")
	out.write_string("const zig = '${v_escape(conf.zig)}'\n")
	out.write_string("const zig_flags = '${v_escape(conf.flags)}'\n")
	out.write_string("const headgen_file = '${v_escape(conf.headgen_file)}'\n")
	out.write_string("const headgen_exe = os.join_path_single(build_dir, 'headgen')\n")
	out.write_string("const dest_dir = '${v_escape(conf.dest_dir)}'\n")
	out.write_string("const install_path = '${v_escape(conf.dest_dir)}/${v_escape(conf.target)}'\n")
	if conf.custom != '' {
		out.write_string('// the build :custom code, spelled as the conf had it.\n')
		out.write_string('${v_escape(conf.custom)}\n')
	}
	// the zig-built sources of c and cpp, and the pre-built objects.
	// rust and d ride the objects const instead: their sources feed their
	// own compilers, never the zig argv.
	mut c_literal := []string{}
	for kind in c_list {
		lip := cfg.modules[kind]
		if lip.language !in ['c', 'cpp'] { continue }
		c_literal << "'modules/${kind}/${lip.source}'"
	}
	if c_literal.len > 0 {
		out.write_string('const c_sources = [${c_literal.join(', ')}]\n')
	} else {
		out.write_string('const c_sources = []string{}\n')
	}
	mut obj_literal := []string{}
	for obj in object_outputs(cfg) {
		obj_literal << "'${v_escape(obj)}'"
	}
	if obj_literal.len > 0 {
		out.write_string('const objects = [${obj_literal.join(', ')}]\n')
	} else {
		out.write_string('const objects = []string{}\n')
	}
	// the pre-zig steps: rust's staticlibs, dmd's objects, and the template commands.
	mut steps_cfg := compile_steps(cfg, conf.cc)
	mut compile_literal := []string{}
	mut shell_literal := []string{}
	for step in steps_cfg {
		if step.shell != '' {
			shell_literal << "'${v_escape(step.shell)}'"
		} else {
			mut one := []string{}
			for arg in step.argv {
				one << "'${v_escape(arg)}'"
			}
			compile_literal << '[${one.join(', ')}]'
		}
	}
	if compile_literal.len > 0 {
		out.write_string('const compile_steps = [${compile_literal.join(', ')}]\n')
	} else {
		out.write_string('const compile_steps = [][]string{}\n')
	}
	if shell_literal.len > 0 {
		out.write_string('const compile_shells = [${shell_literal.join(', ')}]\n')
	} else {
		out.write_string('const compile_shells = []string{}\n')
	}
	// the extern-dep rust modules: each pair is [name, source, spellings...],
	// the manifest already written, cargo builds its archive in the flow.
	mut ext_literal := []string{}
	for source in cfg.sources {
		for e in source.entries {
			if e.static_ || ext_seen[e.kind] { continue }
			lip := cfg.modules[e.kind]
			if lip.language != 'rust' || lip.deps_ext.len == 0 { continue }
			ext_seen[e.kind] = true
			mut one := ["'${v_escape(e.kind)}'", "'${v_escape(lip.source)}'"]
			for ext in lip.deps_ext {
				one << "'${v_escape(ext_spelling(ext))}'"
			}
			ext_literal << '[${one.join(', ')}]'
		}
	}
	if ext_literal.len > 0 {
		out.write_string('const rust_ext = [${ext_literal.join(', ')}]\n')
	} else {
		out.write_string('const rust_ext = [][]string{}\n')
	}
	// linker flags ride the final link, grown from the module lips.
	flags := extra_link_flags(cfg)
	if flags.len > 0 {
		mut flag_literal := []string{}
		for flag in flags {
			flag_literal << "'${v_escape(flag)}'"
		}
		out.write_string('const extra_link = [${flag_literal.join(', ')}]\n')
	} else {
		out.write_string('const extra_link = []string{}\n')
	}
	// V entries bake one run per entry, so the steps carry each arg, and
	// their constants pair with the steps through their bake ids.
	steps := v_bake_steps(cfg)
	if steps.len > 0 {
		mut step_literal := []string{}
		mut id_literal := []string{}
		for step in steps {
			mut one := []string{}
			for arg in step.argv {
				one << "'${v_escape(arg)}'"
			}
			step_literal << '[${one.join(', ')}]'
			id_literal << '${step.id}'
		}
		out.write_string('const v_bakes = [${step_literal.join(', ')}]\n')
		out.write_string('const v_bake_ids = [${id_literal.join(', ')}]\n')
		out.write_string(r'// esc escapes one baked value into the body of a zig string literal:
// same shape headgen gives sources. the backslash doubles first, so the
// later replaces cannot meet a sequence they introduced themselves.
fn esc(value string) string {
	return value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
}
')
	} else {
		out.write_string('const v_bakes = [][]string{}\n')
	}
	out.write_string('\n')
	has_runs := sources_have_runs(cfg)
	if has_runs {
		// the divifetch-run twin: the regen flow writes its source, the
		// build compiles it beside the fetch, the run flow drives it.
		out.write_string("const run_src = '${v_escape(out_run_src)}'\n")
		out.write_string("const run_target_exe = os.join_path_single(build_dir, 'divifetch-run')\n")
	}
	// v script mode wants every const before the first code line.
	out.write_string('mut ctx := imp.new()\n\n')
	out.write_string("ctx.default(['${v_escape(conf.def)}'])\n\n")
	out.write_string('ctx.add_target(target_exe)\n')
	if has_runs {
		out.write_string('\nctx.add_target(run_target_exe)\n')
	}
	out.write_string('\n')
	mut regen_literal := []string{}
	for arg in regen_args {
		regen_literal << "'${v_escape(arg)}'"
	}
	out.write_string('mut regen_args := [${regen_literal.join(', ')}]\n\n')
	out.write_string('ctx.add_flow(\n')
	out.write_string("\tid: 'regen'\n")
	out.write_string("\thelp: 'regenerate run.zig and headgen.zig from the lips'\n")
	out.write_string("\ttakes: ['config.lip', 'modules']\n")
	if has_runs {
		out.write_string("\tgives: ['${v_escape(out_src)}', '${v_escape(out_run_src)}']\n")
	} else {
		out.write_string("\tgives: ['${v_escape(out_src)}']\n")
	}
	out.write_string('\tflow: fn [regen_args] (self imp.Flow) ! {\n')
	out.write_string('\t\timp.system_args(regen_args)!\n')
	// the twin's stale shapes sweep before the regen writes: a config that
	// dropped its (run ...) forms regenerates nothing, so the companion
	// source and binary vanish; one that still spells runs regenerates
	// them fresh a line later.
	out.write_string("\t\tif os.exists('${v_escape(out_run_src)}') {\n")
	out.write_string("\t\t\tos.rm('${v_escape(out_run_src)}')!\n")
	out.write_string('\t\t}\n')
	out.write_string("	\tmut stale := os.join_path_single('${v_escape(conf.build_dir)}', 'divifetch-run')\n")
	out.write_string('\t\tif os.exists(stale) { os.rm(stale)! }\n')
	out.write_string('\t\timp.system_args(regen_args)!\n')
	out.write_string('\t}\n')
	out.write_string(')\n\n')
	out.write_string('ctx.add_flow(\n')
	out.write_string("\tid: 'build'\n")
	out.write_string("\thelp: 'bake what headgen says and the V entries print, and compile the fetch'\n")
	if has_runs {
		out.write_string("\ttakes: ['${v_escape(out_src)}', '${v_escape(out_run_src)}', 'modules']\n")
		out.write_string('\tgives: [target_exe, run_target_exe]\n')
	} else {
		out.write_string("\ttakes: ['${v_escape(out_src)}', 'modules']\n")
		out.write_string('\tgives: [target_exe]\n')
	}
	out.write_string('\tflow: fn (self imp.Flow) ! {\n')
	out.write_string("\t\tos.mkdir_all('${v_escape(out_src_dir)}')!\n")
	out.write_string('\t\tos.mkdir_all(build_dir)!\n')
	out.write_string('\t\t// the generated sources reach the modules through a tree symlink\n')
	out.write_string("\t\tmod_alias := os.join_path_single('${out_src_dir}', 'modules')\n")
	out.write_string('\t\tif os.is_dir(mod_alias) && !os.is_link(mod_alias) {\n')
	out.write_string("\t\t\treturn error('the modules ' + mod_alias + ' is a real directory; the fetch needs it as a symlink into the repo tree')\n")
	out.write_string('\t\t}\n')
	out.write_string('\t\tif !os.is_link(mod_alias) {\n')
	out.write_string("\t\t\tos.symlink(os.abs_path('modules'), mod_alias)!\n")
	out.write_string('\t\t}\n')
	out.write_string('\t\t// the compiled-language modules build their objects first: the\n')
	out.write_string('\t\t// rust staticlibs, the dmd objects, and any template command the\n')
	out.write_string('\t\t// lips carried.\n')
	out.write_string('\t\tfor step in compile_steps {\n')
	out.write_string('\t\t\timp.system_args(step)!\n')
	out.write_string('\t\t}\n')
	out.write_string('\t\t// the extern-dep rust modules: each module dir carries the\n')
	out.write_string('\t\t// manifest cargo grew from the lip, its staticlib lands inside\n')
	out.write_string('\t\t// its own target/, and the archive rides the modules tree for\n')
	out.write_string('\t\t// the objects const.\n')
	out.write_string('\t\tfor pair in rust_ext {\n')
	out.write_string('\t\t\tname := pair[0]\n')
	out.write_string("			base_file := pair[1].all_before_last('.')\n")
	out.write_string("			mut manifest := 'modules/'\n")
	out.write_string('\t\t\tmanifest += pair[0]\n')
	out.write_string("			manifest += '/Cargo.toml'\n")
	out.write_string("			imp.system_args(['cargo', 'build', '--release', '--manifest-path', manifest])!\n")
	out.write_string("			mut out_a := 'modules/'\n")
	out.write_string('\t\t\tout_a += pair[0]\n')
	out.write_string("			out_a += '/target/release/lib'\n")
	out.write_string('\t\t\tout_a += name\n')
	out.write_string("			out_a += '.a'\n")
	out.write_string("			mut target_a := 'modules/'\n")
	out.write_string('\t\t\ttarget_a += pair[0]\n')
	out.write_string("			target_a += '/'\n")
	out.write_string("			target_a += base_file + '.a'\n")
	out.write_string('			os.cp(out_a, target_a)!\n')
	out.write_string('\t\t}\n')
	out.write_string('\t\tfor cmd in compile_shells {\n')
	out.write_string("\t\t\tcode := os.system_args(['/bin/sh', '-c', cmd])\n")
	out.write_string('\t\t\tif code != 0 {\n')
	out.write_string("\t\t\t\treturn error('a compile step failed: ' + cmd + ' (code ' + code.str() + ')')\n")
	out.write_string('\t\t\t}\n')
	out.write_string('\t\t}\n')
	out.write_string('\t\t// build-time entries bake here once: headgen runs the zig, c, cpp\n')
	out.write_string('\t\t// and rust ones, the v_bakes steps run the V ones, and their\n')
	out.write_string('\t\t// output lands in the bake file run.zig imports.\n')
	out.write_string("\t\tmut bake_out := ''\n")
	out.write_string('\t\tif os.exists(headgen_file) {\n')
	out.write_string("\t\t\tmut argv := [zig, 'build-exe']\n")
	out.write_string("\t\t\targv << zig_flags.split(' ')\n")
	out.write_string('\t\t\targv << [headgen_file]\n')
	out.write_string('\t\t\targv << c_sources\n')
	out.write_string('\t\t\targv << objects\n')
	out.write_string('\t\t\targv << extra_link\n')
	out.write_string("\t\t\targv << ['-femit-bin=' + headgen_exe]\n")
	out.write_string('\t\t\timp.system_args(argv)!\n')
	out.write_string('\t\t\tbake := os.exec([headgen_exe])\n')
	out.write_string('\t\t\tif bake.exit_code != 0 {\n')
	out.write_string('\t\t\t\tprint(bake.output)\n')
	out.write_string("\t\t\t\treturn error('headgen exited with ' + bake.exit_code.str())\n")
	out.write_string('\t\t\t}\n')
	out.write_string('\t\t\tbake_out += bake.output\n')
	out.write_string('\t\t}\n')
	if steps.len > 0 {
		out.write_string('\t\tfor i, step in v_bakes {\n')
		out.write_string('\t\t\tbaked := os.exec(step)\n')
		out.write_string('\t\t\tif baked.exit_code != 0 {\n')
		out.write_string('\t\t\t\tprint(baked.output)\n')
		out.write_string("\t\t\t\treturn error('a V bake step exited with ' + baked.exit_code.str())\n")
		out.write_string('\t\t\t}\n')
		out.write_string('\t\t\tbake_out += \'pub const bt_\' + v_bake_ids[i].str() + \' = "\' + esc(baked.output.trim_space()) + \'";\\n\'\n')
		out.write_string('\t\t}\n')
	}
	out.write_string("\t\tos.write_file('" + v_escape(out_bake) + "', bake_out)!\n")
	out.write_string("\t\tmut argv := [zig, 'build-exe']\n")
	out.write_string("\t\targv << zig_flags.split(' ')\n")
	out.write_string("\t\targv << ['${v_escape(out_src)}']\n")
	out.write_string('\t\targv << c_sources\n')
	out.write_string('\t\targv << objects\n')
	out.write_string('\t\targv << extra_link\n')
	out.write_string("\t\targv << ['-femit-bin=' + target_exe]\n")
	out.write_string('\t\timp.system_args(argv)!\n')
	if has_runs {
		out.write_string('\t\t// the twin links the same tree the fetch did: same flags, same objects, its own entry source and bin.\n')
		out.write_string("\t\tmut run_argv := [zig, 'build-exe']\n")
		out.write_string("\t\trun_argv << zig_flags.split(' ')\n")
		out.write_string('\t\trun_argv << [run_src]\n')
		out.write_string('\t\trun_argv << c_sources\n')
		out.write_string('\t\trun_argv << objects\n')
		out.write_string('\t\trun_argv << extra_link\n')
		out.write_string("\t\trun_argv << ['-femit-bin=' + run_target_exe]\n")
		out.write_string('\t\timp.system_args(run_argv)!\n')
	}
	out.write_string('\t}\n')
	out.write_string(')\n\n')
	out.write_string('ctx.add_flow(\n')
	out.write_string("\tid: 'clean'\n")
	out.write_string("\thelp: 'delete the build directory and the bake file'\n")
	out.write_string('\tcheck: imp.Check.none\n')
	out.write_string('\tflow: fn (self imp.Flow) ! {\n')
	out.write_string('\t\tmut swept := []string{}\n\t\tswept << build_dir\n')
	out.write_string("	\tswept << '" + v_escape(out_bake) + "'\n")
	out.write_string('\t\tfor path in swept {\n')
	out.write_string('\t\t\tif !os.is_dir(path) && os.exists(path) {\n')
	out.write_string('\t\t\t\tos.rm(path)!\n')
	out.write_string('\t\t\t} else if os.is_dir(path) {\n')
	out.write_string('\t\t\t\tos.rmdir_all(path)!\n')
	out.write_string('\t\t\t}\n')
	out.write_string('\t\t}\n')
	out.write_string('\t}\n')
	out.write_string(')\n\n')
	out.write_string('ctx.add_flow(\n')
	out.write_string("\tid: 'install'\n")
	out.write_string("\thelp: 'install the fetch to ' + dest_dir\n")
	out.write_string('\ttakes: [target_exe]\n')
	out.write_string('\tgives: [install_path]\n')
	out.write_string('\tflow: fn (self imp.Flow) ! {\n')
	out.write_string('\t\tos.mkdir_all(dest_dir)!\n')
	out.write_string("\t\timp.system_args(['install', '-Dm755', target_exe, install_path])!\n")
	out.write_string('\t}\n')
	out.write_string(')\n\n')
	out.write_string('ctx.add_flow(\n')
	out.write_string("\tid: 'uninstall'\n")
	out.write_string("\thelp: 'uninstall the fetch from ' + dest_dir\n")
	out.write_string('\tcheck: imp.Check.none\n')
	out.write_string('\tflow: fn (self imp.Flow) ! {\n')
	out.write_string("\t\timp.system_args(['rm', '-f', install_path])!\n")
	out.write_string('\t}\n')
	out.write_string(')\n\n')
	// imp's auto run flow demands exactly one target, so a twin-bearing
	// build spells both runs by hand: `run` keeps executing the plain
	// fetch, `run-run` chains the (run ...) binaries after its lines.
	if has_runs {
		out.write_string('ctx.add_flow(\n')
		out.write_string("	id: 'run'\n")
		out.write_string("\thelp: 'execute the fetch'\n")
		out.write_string('\ttakes: [target_exe]\n')
		out.write_string('\tcheck: imp.Check.none\n')
		out.write_string('\tflow: fn (self imp.Flow) ! {\n')
		out.write_string('\t\timp.system_args([os.abs_path(target_exe)])!\n')
		out.write_string('\t}\n')
		out.write_string(')\n\n')
		out.write_string('ctx.add_flow(\n')
		out.write_string("	id: 'run-run'\n")
		out.write_string("\thelp: 'divifetch-run: the fetch lines, then the (run ...) binaries'\n")
		out.write_string('\ttakes: [run_target_exe]\n')
		out.write_string('\tcheck: imp.Check.none\n')
		out.write_string('\tflow: fn (self imp.Flow) ! {\n')
		out.write_string('\t\timp.system_args([os.abs_path(run_target_exe)])!\n')
		out.write_string('\t}\n')
		out.write_string(')\n\n')
	} else {
		out.write_string('ctx.add_auto_flow(.run)\n\n')
	}
	out.write_string('ctx.flow()\n')
	return out.str()
}

// ─── emitting ─────────────────────────────────────────────────────────────

// zig_escape renders a string as the body of a zig literal: control bytes
// come out escaped (the escape byte arrives decoded), everything else stays.
fn zig_escape(s string) string {
	mut out := strings.new_builder(s.len + 8)
	for b in s.bytes() {
		match b {
			0x22 { out.write_string('\\"') }
			0x5c { out.write_string('\\\\') }
			0x0a { out.write_string('\\n') }
			0x0d { out.write_string('\\r') }
			0x09 { out.write_string('\\t') }
			else {
				if b < 0x20 || b == 0x7f {
					out.write_string('\\x${int(b):02x}')
				} else {
					out.write_byte(b)
				}
			}
		}
	}
	return out.str()
}

// nul_check catches the mispelled ANSI escape: '\0x1B' reads as NUL + text,
// so the warning points at the spelling, at the field, at the entry.
fn (mut cfg Config) nul_check(path string, field string, s string) {
	if !s.contains(nul) {
		return
	}
	cfg.warn_once('${path} ${field} has a NUL byte — \0 only means NUL to the blip reader; spell ANSI as \\e, not \\033 or \\0x1B')
}

// entry_call builds the call of a dynamic entry: fn(io?, environ?, arg?)
// for a zig module, and preset(arg?, &buf) for a C module, whose shim
// passes the module-owned buffer as the last argument.
fn entry_call(cfg &Config, e &Entry) string {
	lip := cfg.modules[e.kind]
	if lip.language in ['c', 'cpp', 'rust', 'd'] {
		mut c_args := []string{}
		if lip.arg != '' { c_args << '"${zig_escape(e.arg)}"' }
		c_args << '&${e.kind}_buf'
		return '${e.kind}.preset(${c_args.join(', ')})'
	}
	mut args := []string{}
	if lip.deps_io { args << 'io' }
	if lip.deps_env { args << 'environ' }
	if lip.arg_is_list {
		// the entry's :args ride as the one list argument, empty for an
		// arg-less entry: the preset's own candidate order answers.
		mut one := []string{}
		if e.args.len > 0 {
			for a in e.args {
				one << '"${zig_escape(a)}"'
			}
		} else if e.arg != '' {
			one << '"${zig_escape(e.arg)}"'
		}
		if one.len > 0 {
			args << '&.{ ${one.join(', ')} }'
		} else {
			args << '&.{}'
		}
	} else if lip.arg != '' {
		args << '"${zig_escape(e.arg)}"'
	}
	return '${e.kind}.${lip.fname}(${args.join(', ')})'
}

// build_art_lines reads the art file and builds the art column: the width
// is the largest column any line takes plus the configured padding (or the
// :art-width floor), shorter lines pad to the right, every line rides in
// the art prefix and suffix, and more entries than lines gain blank lines.
fn build_art_lines(props &Props, entry_count int) ![]string {
	if props.art_file == '' {
		return []string{}
	}
	text := os.read_file(props.art_file) or {
		return error('cannot read art file ${props.art_file}: ${err.msg()}')
	}
	mut lines := text.split_into_lines()
	if lines.len == 0 {
		return []string{}
	}
	mut width := props.art_width
	for raw_line in lines {
		line := art_line_decode(raw_line)
		width = max_int(width, visible_width(line) + props.art_padding)
	}
	if width < 0 {
		width = 0
	}
	if entry_count > lines.len {
		for entry_count > lines.len {
			lines << strings.repeat_string(' ', width)
		}
	}
	mut out := []string{}
	for raw_line in lines {
		line := art_line_decode(raw_line)
		mut pad := width - visible_width(line)
		if pad < 0 {
			pad = 0
		}
		out << props.art_prefix + line + strings.repeat_string(' ', pad) + props.art_suffix
	}
	return out
}

// fmt_escape escapes one piece for inside a format string: braces double, so
// a key cannot grow placeholders into the format, and the nul guard runs.
fn (mut cfg Config) fmt_escape(path string, field string, s string) string {
	cfg.nul_check(path, field, s)
	return zig_escape(s).replace('{', '{{').replace('}', '}}')
}

// entry_text composes one escaped entry line: the art column first, then the
// key prefixed and suffixed as configured, and either the baked value or
// {s} for a runtime call. the newline ends each one, escaped.
fn (cfg &Config) entry_text(path string, art string, e Entry) string {
	mut line := cfg.fmt_escape(path, 'art', art)
	if !e.no_key {
		line += cfg.fmt_escape(path, 'key-prefix', e.kp)
		line += cfg.fmt_escape(path, 'key', e.key)
		line += cfg.fmt_escape(path, 'key-suffix', e.ks)
	}
	line += cfg.fmt_escape(path, 'value-prefix', e.vp)
	if e.static_ {
		line += cfg.fmt_escape(path, 'value', e.value)
	} else {
		line += '{s}'
	}
	line += cfg.fmt_escape(path, 'value-suffix', e.vs)
	line += '\\n'
	return line
}

// group_note traces one print statement back to the forms behind it.
fn group_note(covered []Entry, path string, trailing_art bool) string {
	mut note := ''
	if covered.len > 0 {
		mut kinds := []string{}
		for e in covered {
			kinds << e.kind
		}
		mut span := '${covered[0].line}'
		if covered.len > 1 {
			span = '${covered[0].line}-${covered[covered.len - 1].line}'
		}
		note = '${kinds.join(' + ')} (${path}:${span})'
	}
	if trailing_art {
		note += if note != '' { ' + trailing art' } else { 'trailing art' }
	}
	return note
}

// emit_group writes one print statement: a static batch spells every line
// right into the format string; a dynamic one carries a {s} for the call,
// like the C generator batched its printfs.
fn emit_group(out &strings.Builder, text string, call string, note string) {
	if text == '' {
		return
	}
	mut fmt_args := '.{}'
	if call != '' {
		fmt_args = '.{${call}}'
	}
	out.write_string('    // ${note}\n')
	out.write_string('    try stdout.print("${text}", ${fmt_args});\n')
}

// import_names collects the dynamic kinds in first-reference order, so the
// generated imports read the way the config does. build-time entries stay
// out (their values arrive baked) and C modules too (they are reached
// through shims, not imports).
fn import_names(cfg &Config) []string {
	mut names := []string{}
	mut seen := map[string]bool{}
	for source in cfg.sources {
		for e in source.entries {
			if e.static_ || e.build_time || seen[e.kind] { continue }
			if cfg.modules[e.kind].language != 'zig' { continue }
			seen[e.kind] = true
			names << e.kind
		}
	}
	return names
}

// c_modules lists every referenced C-language module in first-reference
// order: the emitters give each one a shim, the build script compiles its
// source file with the fetch.
fn c_modules(cfg &Config) []string {
	mut out := []string{}
	mut seen := map[string]bool{}
	for source in cfg.sources {
		for e in source.entries {
			if e.static_ || seen[e.kind] { continue }
			if cfg.modules[e.kind].language !in ['c', 'cpp', 'rust', 'd'] { continue }
			seen[e.kind] = true
			out << e.kind
		}
	}
	return out
}

// VBakeStep is one entry's bake invocation: the bake constant it feeds and
// the argv that produces the value.
struct VBakeStep {
	id   int
	argv []string
}

// v_bake_steps are the invocations that bake V entries: one per build-time
// V entry, in order of the entries they belong to — v run <module.v> [args…].
// their stdout is what bake.zig wraps into the bt_<id> constant named by
// their ids.
fn v_bake_steps(cfg &Config) []VBakeStep {
	mut steps := []VBakeStep{}
	for source in cfg.sources {
		for e in source.entries {
			if e.static_ || e.bt_id < 0 { continue }
			lip := cfg.modules[e.kind]
			if lip.language != 'v' { continue }
			mut step := ['v', 'run', 'modules/${e.kind}/${lip.source}']
			if e.arg != '' {
				step << e.arg
			}
			steps << VBakeStep{
				id:   e.bt_id
				argv: step
			}
		}
	}
	return steps
}

// c_shim is the zig side of a C module: the exported symbol is declared
// extern, the preset that wraps it takes — and, per :arg, passes — the
// entry argument, writes into a module-owned buffer sized by
// :buffer-size, and keeps the "?" convention for a null return.
fn c_shim(kind string, lip ModuleLip, buf_size int) string {
	mut out := strings.new_builder(512)
	out.write_string('\n')
	out.write_string('// ${kind} is a compiled module: the build script builds it\n')
	out.write_string('// modules/${kind}/${lip.source} with the fetch, and the shim below\n')
	out.write_string('// reaches its exported preset through a module-owned buffer.\n')
	if lip.arg != '' {
		out.write_string('extern fn ${lip.fname}(arg: [*:0]const u8, buf: [*]u8, buf_size: usize) ?[*:0]const u8;\n')
		out.write_string('const ${kind} = struct {\n')
		out.write_string('    pub fn preset(arg: [*:0]const u8, buf: []u8) []const u8 {\n')
		out.write_string('        const ptr = ${lip.fname}(arg, buf.ptr, buf.len) orelse return "?";\n')
		out.write_string('        return std.mem.span(ptr);\n')
		out.write_string('    }\n')
		out.write_string('};\n')
	} else {
		out.write_string('extern fn ${lip.fname}(buf: [*]u8, buf_size: usize) ?[*:0]const u8;\n')
		out.write_string('const ${kind} = struct {\n')
		out.write_string('    pub fn preset(buf: []u8) []const u8 {\n')
		out.write_string('        const ptr = ${lip.fname}(buf.ptr, buf.len) orelse return "?";\n')
		out.write_string('        return std.mem.span(ptr);\n')
		out.write_string('    }\n')
		out.write_string('};\n')
	}
	out.write_string('var ${kind}_buf: [${buf_size}]u8 = undefined;\n')
	return out.str()
}

// output_headgen writes headgen.zig, the companion program the build runs
// once: it runs the build-time entries and prints their values as the
// bake.zig constants the fetch entry imports, the way the C generator's
// header generator wrote BUILD_TIME_ defines.
// output_headgen writes headgen.zig, the companion program the build runs
// once per source: it runs the build-time entries and prints their values as
// the bake.zig constants the fetch entry imports, the way the C generator's
// header generator wrote BUILD_TIME_ defines. sources arrive in config
// order and the ids are global across them.
fn output_headgen(cfg &Config, confs []string) string {
	path := confs.join(', ')
	mut out := strings.new_builder(2048)
	out.write_string('// headgen.zig — runs the build-time entries of ${path} once\n')
	out.write_string('// and prints bake.zig to stdout. the build runs it before the fetch\n')
	out.write_string('// compiles, so their values bake in and the fetch never refetches.\n')
	out.write_string('\n')
	out.write_string(r'const std = @import("std");

// write_escaped renders one baked value as the body of a zig string
// literal: the same shape the generator escape gives generated sources.
fn write_escaped(w: *std.Io.Writer, s: []const u8) !void {
	for (s) |b| {
		if (b == 0x22) {
			try w.writeAll("\\\"");
		} else if (b == 0x5c) {
			try w.writeAll("\\\\");
		} else if (b == 0x0a) {
			try w.writeAll("\\n");
		} else if (b == 0x0d) {
			try w.writeAll("\\r");
		} else if (b == 0x09) {
			try w.writeAll("\\t");
		} else if (b < 0x20 or b == 0x7f) {
			try w.print("\\x{x:0>2}", .{b});
		} else {
			try w.writeByte(b);
		}
	}
}
')
	out.write_string('\n')
	mut seen := map[string]bool{}
	for source in cfg.sources {
		for e in source.entries {
			if e.static_ || e.bt_id < 0 || seen[e.kind] { continue }
			lip := cfg.modules[e.kind]
			// V entries bake through v_bakes steps in the build script; headgen
			// carries only what compiles into itself — the zig, C, C++ and Rust
			// modules.
			if lip.language == 'v' { continue }
			seen[e.kind] = true
			if lip.language != 'zig' {
				out.write_string(c_shim(e.kind, lip, props_of(cfg).buffer_size))
				continue
			}
			out.write_string('const ${e.kind} = @import("modules/${e.kind}/module.zig");\n')
		}
	}
	out.write_string('\n')
	out.write_string('pub fn main(init: std.process.Init) !void {\n')
	out.write_string('    const io = init.io;\n')
	mut headgen_env := false
	for source in cfg.sources {
		if source.headgen_env { headgen_env = true }
	}
	if headgen_env {
		out.write_string('    const environ = init.environ_map;\n')
	}
	out.write_string('\n')
	out.write_string('    var stdout_buffer: [4096]u8 = undefined;\n')
	out.write_string('    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);\n')
	out.write_string('    const stdout = &stdout_writer.interface;\n')
	out.write_string('\n')
	for source in cfg.sources {
		for e in source.entries {
			if e.static_ || e.bt_id < 0 { continue }
			// V entries bake through v_bakes steps in the build script, having
			// headgen reach them only when the language compiles into it.
			if cfg.modules[e.kind].language == 'v' { continue }
			out.write_string('    try stdout.print("pub const bt_${e.bt_id} = \\\"", .{});\n')
			out.write_string('    try write_escaped(stdout, ${entry_call(cfg, e)});\n')
			out.write_string('    try stdout.print("\\";\\n", .{});\n')
		}
	}
	out.write_string('\n')
	out.write_string('    try stdout.flush();\n')
	out.write_string('}\n')
	return out.str()
}

// props_of walks the sources for a config's buffer size — every source
// folds the same field, so the first non-default one answers.
fn props_of(cfg &Config) Props {
	for source in cfg.sources {
		if source.props.buffer_size != 128 {
			return source.props
		}
	}
	return if cfg.sources.len > 0 { cfg.sources[0].props } else { Props{} }
}

// output_source writes run.zig: the imports of the referenced modules —
// across every source, deduped — then one run_<i> per config file, whose
// batches carry the art column in front of every entry the way the C
// generator batched them. a single source runs directly; several pick one
// at random at fetch time, upstream's multi-config selection. the chosen
// source's :execute replaces the process, mirroring the C execl. build-time
// entries point at their baked value in bake.zig instead of calling their
// module.
fn output_source(cfg &Config, confs []string, out_src string, out_bake string, twin bool) string {
	path := confs.join(', ')
	mut out := strings.new_builder(4096)
	if twin {
		// one twin line apart, the twin source is this same body: the twin's
		// main voids its runs out after the flush instead of going home.
		out.write_string('// run-run.zig — the divifetch-run twin. generated by the generator.\n')
		out.write_string('// it prints the fetch lines, then runs the (run ...) binaries\n')
		out.write_string('// the config chains after them. regenerate with: v run generator\n')
	} else {
		out.write_string('// run.zig — the divifetch-zig fetch entry. generated by the generator.\n')
		out.write_string('// edit config.lip and the module.lips instead; regenerate with: v run generator\n')
	}
	out.write_string('// source configs: ${path}\n')
	out.write_string('\n')
	out.write_string('const std = @import("std");\n')
	out.write_string('\n')
	for name in import_names(cfg) {
		out.write_string('const ${name} = @import("modules/${name}/module.zig");\n')
	}
	mut has_bake := false
	for source in cfg.sources {
		for e in source.entries {
			if e.bt_id >= 0 {
				has_bake = true
			}
		}
	}
	if has_bake {
		out.write_string('const bake = @import("${bake_import(out_src, out_bake)}");\n')
	}
	for kind in c_modules(cfg) {
		lip := cfg.modules[kind]
		out.write_string(c_shim(kind, lip, props_of(cfg).buffer_size))
	}
	// one runtime context at the top, shared by the source fns.
	out.write_string('\n')
	out.write_string('pub fn main(init: std.process.Init) !void {\n')
	out.write_string('    const io = init.io;\n')
	mut needs_env := false
	for source in cfg.sources {
		if source.needs_env { needs_env = true }
	}
	if needs_env {
		out.write_string('    const environ = init.environ_map;\n')
	}
	out.write_string('\n')
	out.write_string('    var stdout_buffer: [4096]u8 = undefined;\n')
	out.write_string('    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);\n')
	out.write_string('    const stdout = &stdout_writer.interface;\n')
	out.write_string('\n')
	// per-source params: stdout always, io when the source has a dynamic
	// preset or an :execute, environ when its runtime entries take the map.
	// gathered into named lists, since a Source is a value copy in a loop.
	mut sigs := []string{}
	mut calls := []string{}
	for source in cfg.sources {
		mut fnparams := ['stdout: *std.Io.Writer']
		mut fnargs := ['stdout']
		mut needs_io := source.needs_env
		for e in source.entries {
			if e.static_ || e.bt_id >= 0 { continue }
			needs_io = needs_io || cfg.modules[e.kind].deps_io
		}
		if needs_io {
			fnparams << 'io: std.Io'
			fnargs << 'io'
		}
		if source.needs_env {
			fnparams << 'environ: *const std.process.Environ.Map'
			fnargs << 'environ'
		}
		sigs << fnparams.join(', ')
		calls << fnargs.join(', ')
	}
	// single source: run it directly. several: one wins at random each run,
	// upstream's multi-config selection, with the art baked per source.
	if cfg.sources.len == 1 {
		out.write_string('    try run_0(${calls[0]});\n')
		out.write_string('\n')
		out.write_string('    try stdout.flush();\n')
		if twin {
			cfg.run_spawns(out, 0, false)
		}
		cfg.source_execute(out, 0)
	} else {
		out.write_string('    var entropy: [8]u8 = undefined;\n')
		out.write_string('    io.random(&entropy);\n')
		out.write_string('    var rand = std.Random.Sfc64.init(std.mem.readInt(u64, &entropy, .little));\n')
		out.write_string('    const chosen = rand.random().intRangeLessThan(usize, 0, ${cfg.sources.len});\n')
		out.write_string('    switch (chosen) {\n')
		for si in 0 .. cfg.sources.len {
			out.write_string('        ${si} => try run_${si}(${calls[si]}),\n')
		}
		out.write_string('        else => {},\n')
		out.write_string('    }\n')
		out.write_string('\n')
		out.write_string('    try stdout.flush();\n')
		for si in 0 .. cfg.sources.len {
			if twin {
				cfg.run_spawns(out, si, true)
			}
			cfg.source_execute(out, si)
		}
	}
	out.write_string('}\n')
	// the source fns: one per config, carrying the chosen file's art and
	// prefixes, with the print groups batched the C way.
	for si, source in cfg.sources {
		src_path := confs[si]
		out.write_string('\n')
		out.write_string('// run_${si} — the entries of ${src_path}.\n')
		out.write_string('fn run_${si}(${sigs[si]}) !void {\n')
		mut text := strings.new_builder(512)
		mut call := ''
		mut covered := []Entry{}
		for i, e in source.entries {
			mut art_piece := ''
			if source.art_lines.len > i {
				art_piece = source.art_lines[i]
			}
			if e.new_print && covered.len > 0 {
				emit_group(out, text.str(), call, group_note(covered, src_path, false))
				text = strings.new_builder(512)
				call = ''
				covered = []
			}
			if e.static_ {
				text.write_string(cfg.entry_text(src_path, art_piece, e))
			} else {
				if covered.len > 0 {
					emit_group(out, text.str(), call, group_note(covered, src_path, false))
					text = strings.new_builder(512)
					covered = []
				}
				text.write_string(cfg.entry_text(src_path, art_piece, e))
				call = if e.bt_id >= 0 { 'bake.bt_${e.bt_id}' } else { entry_call(cfg, e) }
			}
			covered << e
		}
		for i in source.entries.len .. source.art_lines.len {
			text.write_string(zig_escape(source.art_lines[i]) + '\\n')
		}
		emit_group(out, text.str(), call, group_note(covered, src_path, source.art_lines.len > source.entries.len))
		out.write_string('}\n')
	}
	return out.str()
}

// source_execute writes the chosen source's :execute, the C generator's
// execl after its prints.
fn (cfg &Config) source_execute(out &strings.Builder, si int) {
	source := cfg.sources[si]
	if source.execute == '' {
		return
	}
	if cfg.sources.len > 1 {
		out.write_string('    if (chosen == ${si}) {\n')
	}
	out.write_string('        const exec_note = std.process.replace(io, .{ .argv = &.{ "/bin/sh", "-c", "${zig_escape(source.execute)}" } });\n')
	out.write_string('        if (0 != @intFromError(exec_note)) {\n')
	out.write_string('            std.process.exit(127);\n')
	out.write_string('        }\n')
	if cfg.sources.len > 1 {
		out.write_string('    }\n')
	}
}

// run_spawns writes one source's (run ...) spawn-and-wait block: each
// binary answers only from its own argv, straight to the fetch's
// terminal, with the next one waiting the previous out. A source can
// never carry both these and :execute — the collector refuses that pair.
// The guard form wraps it in the multi-source `chosen` check, the way
// :execute does.
fn (cfg &Config) run_spawns(out &strings.Builder, si int, guarded bool) {
	source := cfg.sources[si]
	if source.runs.len == 0 {
		return
	}
	if guarded {
		out.write_string('    if (chosen == ${si}) {
')
	}
	for r in source.runs {
		mut argv := '&.{&\n'
		mut one := ['\"${zig_escape(r.bin)}\"']
		for arg in r.args {
			one << '\"${zig_escape(arg)}\"'
		}
		argv = '&.{ ${one.join(', ')} }'
		out.write_string('        // (run ...) from config.lip:${r.line}: ${zig_escape(r.bin)}
')
		out.write_string('        {
')
		out.write_string('            var child = std.process.spawn(io, .{
')
		out.write_string('                .stdin = .inherit,
')
		out.write_string('                .stdout = .inherit,
')
		out.write_string('                .stderr = .inherit,
')
		out.write_string('                .argv = ${argv},
')
		out.write_string('            }) catch |err| return err;
')
		out.write_string('            const term = child.wait(io) catch |err| return err;
')
		out.write_string('            if (!term.success()) return error.TwinChildFailed;
')
		out.write_string('        }
')
	}
	if guarded {
		out.write_string('    }
')
	}
}

// sources_have_runs answers for the buildfile emitter and main's twin
// write: any source anywhere spelling a (run ...) form.
fn sources_have_runs(cfg &Config) bool {
	for source in cfg.sources {
		if source.runs.len > 0 {
			return true
		}
	}
	return false
}

// ─── example config ───────────────────────────────────────────────────────

// output_example_config is the --genconf template: the same fields as the C
// generator, with the entries divifetch-zig ships as lip files.
fn output_example_config() string {
	return r'; divifetch example config.lip — generated by --genconf
;
; the config is a blip program: (define ...) and any blip expression work,
; and evaluated values feed every spelling. every form is one entry, in
; output order; an entry kind names a subdirectory of modules/ with its own
; module.lip, and only the referenced modules compile in. with several
; -s files the fetch picks one at random on each run.
;
; strings know the blip escapes (n, t, r, 0, the backslash and the quote)
; plus two the generator adds for ANSI: \e is the escape byte and \xHH one
; hex byte — \033 and \0x1B do NOT work here.

; spell your colors once, reference them everywhere.
(define dark "\e[1m\e[38;2;160;160;160m")

(config :art-file "ascii/cat.txt"
        :art-prefix dark
        :art-suffix "\e[0m"
        :key-prefix dark
        :key-suffix "\e[0m: "
        :build-time yes)

; the chained session of the fetch: divifetch-run prints the lines,
; then hands you this shell; v run build.vsh run keeps the plain form.
;(run :bin "zsh")

; a user function: one spelling for every mountpoint line.
(define (mount_p path)
  (mount :key (string-append "Mount (" path ")")
         :args [path]))

(user :key "")
(plain :value-prefix dark :value "---------")
(os :key "OS")
(host)
(kernel)
(pid1 :key "Supervisor")
(packages :build-time no :args ["pacman"])
(shell)
(wm)
(terminal)
(font)
(cpu)
(gpu)
(memory)
(display)
(mount_p "/")
(battery)

(break)

(colors_bright)
(colors_normal)
'
}

// ext_spelling answers the :ext crate spelling a manifest grew from: the
// name, its version requirement, the no-default-features toggle, and the
// feature list — the same shape the lip carried.
fn ext_spelling(ext ExtCrate) string {
	mut s := ext.name
	if ext.version != '' {
		s += ' ${ext.version}'
	}
	if ext.no_default_features {
		s += ' no-default-features'
	}
	if ext.features.len > 0 {
		s += ' features=[${ext.features.join(',')}]'
	}
	return s
}

// ext_cargo_toml renders the crate manifest one ext-dep module builds
// through: the module's own source rides in as the lib, the :ext spellings
// list the dependencies, and release carries panic=abort outright — the
// unwind machinery the stable std keeps referencing is libunwind's.
fn ext_cargo_toml(kind string, lip ModuleLip) string {
	mut out := strings.new_builder(512)
	out.write_string('# Cargo.toml — generated by the divifetch-zig generator\n')
	out.write_string('# for the :ext crates the module.lip names; edit the lip, not this.\n')
	out.write_string('[package]\n')
	out.write_string('name = "${kind}"\n')
	out.write_string('version = "0.0.0"\n')
	out.write_string('edition = "2021"\n')
	out.write_string('\n[lib]\n')
	out.write_string('path = "${lip.source}"\n')
	out.write_string('crate-type = ["staticlib"]\n')
	out.write_string('\n[dependencies]\n')
	for ext in lip.deps_ext {
		requirement := if ext.version != '' { ext.version } else { '*' }
		out.write_string('    ${ext.name} = ')
		if ext.no_default_features || ext.features.len > 0 {
			mut keys := []string{}
			keys << 'version = "${requirement}"'
			if ext.no_default_features {
				keys << 'default-features = false'
			}
			if ext.features.len > 0 {
				mut feats := []string{}
				for feat in ext.features {
					feats << '"${feat}"'
				}
				keys << 'features = [${feats.join(', ')}]'
			}
			out.write_string('{ ${keys.join(', ')} }')
		} else {
			out.write_string('"${requirement}"')
		}
		out.write_string('\n')
	}
	out.write_string('\n')
	out.write_string('[profile.release]\n')
	out.write_string('panic = "abort"\n')
	return out.str()
}

// write_ext_projects lays the crate projects an ext-dep rust module
// builds through: its manifest lives in the module dir itself, with the
// source beside it and the cargo output hidden in the target/ there.
fn write_ext_projects(cfg &Config) ! {
	mut ext_seen := map[string]bool{}
	for source in cfg.sources {
		for e in source.entries {
			if e.static_ || ext_seen[e.kind] { continue }
			lip := cfg.modules[e.kind]
			if lip.language != 'rust' || lip.deps_ext.len == 0 { continue }
			ext_seen[e.kind] = true
			path := os.join_path_single('modules/${e.kind}', 'Cargo.toml')
			write_out(path, ext_cargo_toml(e.kind, lip))!
		}
	}
}
