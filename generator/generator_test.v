// generator_test.v — what gets written: run.zig, headgen.zig and build.vsh
// — their imports, shims, bake wiring and flow shapes — against the sources
// built by the collector, plus the registry shapes the multi-config fetch
// carries.
module main

import os

const fixture_dir = os.abs_path(os.dir(@FILE) + '/..')

const tree_snippet = '(kernel)\n(shell)\n(packages :build-time yes)\n(colors-normal)\n(break)\n'

fn collected_tree() !Config {
	log := '/tmp/opencode/lib__generator_test.lip'
	os.write_file(log, tree_snippet)!
	defer {
		os.rm(log) or {}
	}
	os.chdir(fixture_dir)!
	return collect_config([log])
}

// a c-shaped registry, hand-built the way load_module would have found
// modules/hello_world_c. the tree returns by value; tests that grow it
// take mut Config and fill it in.
fn c_shaped_tree() Config {
	mut cfg := Config{
		sources: [Sources{
			entries: []
		}]
		modules: map[string]ModuleLip{}
		warned:  map[string]bool{}
	}
	cfg.modules['hello_world_c'] = ModuleLip{
		name:     'hello_world_c'
		fname:    'hello_world_c_module_preset'
		language: 'c'
		source:   'module.c'
	}
	cfg.sources[0].props.buffer_size = 256
	cfg.sources[0].entries << Entry{
		kind:    'hello_world_c'
		key:     'Hello World C'
		static_: false
		line:    3
	}
	return cfg
}

fn build_opts() CliOpts {
	mut opt := CliOpts{}
	opt.source_confs << 'config.lip'
	return opt
}

fn test_import_names_skip_static_build_time_and_v() {
	os.chdir(fixture_dir)!
	mut cfg := collected_tree()!
	// kernel and shell are the runtime zig calls; dpkg is baked, colors and
	// break prebaked.
	names := import_names(&cfg)
	assert names == ['kernel', 'shell']
}

fn test_c_modules_walk_first_order() {
	os.chdir(fixture_dir)!
	mut cfg := collected_tree()!
	assert c_modules(&cfg) == []
}

fn test_c_shim_declares_the_export() {
	tree := c_shaped_tree()
	text := c_shim('hello_world_c', tree.modules['hello_world_c'], 256)
	assert text.contains('extern fn hello_world_c_module_preset(buf: [*]u8, buf_size: usize) ?[*:0]const u8;')
	assert text.contains('pub fn preset(buf: []u8) []const u8 {')
	assert text.contains('return std.mem.span(ptr);')
	assert text.contains('var hello_world_c_buf: [256]u8 = undefined;')
}

fn test_c_shim_passes_the_arg_first() {
	lip := ModuleLip{
		name:     'hello_world_c'
		fname:    'hello_world_c_module_preset'
		language: 'c'
		source:   'module.c'
		arg:      'path'
	}
	text := c_shim('hello_world_c', lip, 128)
	assert text.contains('pub fn preset(arg: [*:0]const u8, buf: []u8) []const u8 {')
	assert text.contains('hello_world_c_module_preset(arg, buf.ptr, buf.len)')
	assert text.contains('var hello_world_c_buf: [128]u8 = undefined;')
}

fn test_c_shaped_call_passes_the_buffer() {
	mut cfg := c_shaped_tree()
	call := entry_call(&cfg, &cfg.sources[0].entries[0])
	assert call == 'hello_world_c.preset(&hello_world_c_buf)'
}

fn test_c_shaped_call_passes_the_arg_and_buffer() {
	lip := ModuleLip{
		name:     'hello_world_c'
		fname:    'hello_world_c_module_preset'
		language: 'c'
		source:   'module.c'
		arg:      'path'
	}
	mut cfg := c_shaped_tree()
	cfg.modules['hello_world_c'] = lip
	cfg.sources[0].entries[0].arg = '/home'
	call := entry_call(&cfg, &cfg.sources[0].entries[0])
	assert call == 'hello_world_c.preset("/home", &hello_world_c_buf)'
}

fn test_c_modules_lists_in_first_order() {
	mut cfg := c_shaped_tree()
	assert c_modules(&cfg) == ['hello_world_c']
}

fn test_headgen_holds_only_zig_imports() {
	os.chdir(fixture_dir)!
	mut cfg := collected_tree()!
	text := output_headgen(&cfg, ['f.lip'])
	assert text.contains('const std = @import("std");')
	// baked here: packages, the only zig-kind build-time entry.
	assert text.contains('const packages = @import("modules/packages/module.zig");')
	assert !text.contains('const kernel = ')
	assert !text.contains('const shell = ')
	assert text.contains('fn write_escaped(w: *std.Io.Writer, s: []const u8) !void {')
}

fn test_headgen_prints_each_bake_constant() {
	os.chdir(fixture_dir)!
	mut cfg := collected_tree()!
	text := output_headgen(&cfg, ['f.lip'])
	assert text.contains(r'try stdout.print("pub const bt_0 = \"", .{});')

	assert text.contains('";\\n')
}

fn test_bake_split_work() {
	os.chdir(fixture_dir)!
	mut cfg := collected_tree()!
	cfg.modules['hello_world_v'] = ModuleLip{
		name:     'hello_world_v'
		language: 'v'
		source:   'module.v'
		arg:      'text'
	}
	cfg.sources[0].entries << Entry{
		kind:       'hello_world_v'
		key:        'Hello World V'
		static_:    false
		build_time: true
		bt_id:      1
		arg:        'echo me'
		line:       5
	}
	// the v entry is build-time and lands in its own bake slot.
	steps := v_bake_steps(&cfg)
	assert steps.len == 1
	assert steps[0].id == 1
	assert steps[0].argv == ['v', 'run', 'modules/hello_world_v/module.v', 'echo me']
}

fn test_v_bake_steps_skip_zig_and_c_entries() {
	mut cfg := c_shaped_tree()
	cfg.sources[0].entries << Entry{
		kind:       'static'
		value:      'x'
		static_:    true
		build_time: true
		line:       3
	}
	// a c entry is build-time but compiles into headgen, never v_bakes.
	steps := v_bake_steps(&cfg)
	assert steps.len == 0
}

fn test_output_source_imports_and_bake() {
	os.chdir(fixture_dir)!
	mut cfg := collected_tree()!
	text := output_source(&cfg, ['tree.lip'], '.tmp/run.zig', '.tmp/bake.zig', false)
	assert text.contains('const std = @import("std");')
	assert text.contains('const kernel = @import("modules/kernel/module.zig");')
	assert text.contains('const shell = @import("modules/shell/module.zig");')
	assert !text.contains('const packages = @import(')
	assert text.contains('const bake = @import("bake.zig");')
	// the environ line only shows when a runtime entry asks for it.
	assert text.contains('    const environ = init.environ_map;\n')
}

fn test_output_source_lines_bake_build_time() {
	os.chdir(fixture_dir)!
	mut cfg := collected_tree()!
	text := output_source(&cfg, ['tree.lip'], '.tmp/run.zig', '.tmp/bake.zig', false)
	assert text.contains('.{bake.bt_0});')
	assert !text.contains('.{packages')
}

fn test_output_source_groups_new_print() {
	// a new_print entry takes its own statement, so the groups end there.
	mut cfg := c_shaped_tree()
	text := output_source(&cfg, ['f.lip'], '.tmp/run.zig', '.tmp/bake.zig', false)
	assert text.contains('// hello_world_c (f.lip:3)\n')
	assert text.contains('try stdout.print(')
	assert text.contains('", .{hello_world_c.preset(&hello_world_c_buf)});\n')
}

fn test_output_source_ends_with_a_flush() {
	os.chdir(fixture_dir)!
	mut cfg := collected_tree()!
	text := output_source(&cfg, ['tree.lip'], '.tmp/run.zig', '.tmp/bake.zig', false)
	assert text.contains('    try stdout.flush();\n}\n')
}

fn test_output_source_without_environ() {
	os.chdir(fixture_dir)!
	// a kernel-only tree runs without an environment.
	mut cfg := collected('(kernel)')!
	text := output_source(&cfg, ['f.lip'], '.tmp/run.zig', '.tmp/bake.zig', false)
	assert !text.contains('environ')
}

fn collected(snippet string) !Config {
	log := '/tmp/opencode/lib__generator_test.lip'
	os.write_file(log, snippet)!
	defer { os.rm(log) or {} }
	os.chdir(fixture_dir)!
	return collect_config([log])
}

fn test_output_headgen_skips_v_entries() {
	os.chdir(fixture_dir)!
	mut cfg := collected_tree()!
	cfg.modules['hello_world_v'] = ModuleLip{
		name:     'hello_world_v'
		language: 'v'
		source:   'module.v'
	}
	cfg.sources[0].entries << Entry{
		kind:       'hello_world_v'
		key:        'Hello World V'
		static_:    false
		build_time: true
		bt_id:      1
		line:       9
	}
	text := output_headgen(&cfg, ['f.lip'])
	assert !text.contains('hello_world_v')
	// the ids headgen skips land nowhere, so nothing else shifts.
	assert text.contains('bt_0')
	assert !text.contains('bt_1')
}

fn test_build_art_lines_reads_and_rides() {
	os.chdir(fixture_dir)!
	mut props := Props{}
	props.art_file = 'ascii/cat.txt'
	props.art_padding = 3
	props.art_prefix = '<'
	props.art_suffix = '>'
	lines := build_art_lines(props, 3)!
	// real cat.txt: every line rides in the prefix and suffix, and the
	// column holds the widest line plus the padding.
	assert lines.len >= 3
	assert lines[0].starts_with('<')
	assert lines[0].ends_with('>')
	for line in lines {
		assert visible_width(line[1..line.len - 1]) == 45
	}
}

fn test_build_art_lines_pads_to_the_configured_width() {
	fn_art := '/tmp/opencode/lib__art_test.txt'
	defer { os.rm(fn_art) or {} }
	os.write_file(fn_art, 'ab\nabc\n')!
	mut props := Props{}
	props.art_file = fn_art
	props.art_padding = 2
	props.art_width = 7
	lines := build_art_lines(props, 1)!
	// both lines pad into the configured floor of 7 columns (no prefix).
	assert lines.len == 2
	assert lines[0] == 'ab     '
	assert lines[1] == 'abc    '
}

fn test_build_art_lines_gains_blank_lines_for_more_entries() {
	fn_art := '/tmp/opencode/lib__art_test2.txt'
	defer { os.rm(fn_art) or {} }
	os.write_file(fn_art, 'a\n')!
	mut props := Props{}
	props.art_file = fn_art
	// two entries, one art line: the second gets a blank column line.
	lines := build_art_lines(props, 2)!
	assert lines.len == 2
	assert lines[0] == 'a   '
	assert lines[1] == '    '
}

fn test_build_art_lines_omits_the_column_without_a_file() {
	mut props := Props{}
	props.art_file = ''
	lines := build_art_lines(props, 3)!
	assert lines.len == 0
}

fn test_build_art_lines_errors_on_a_missing_file() {
	mut props := Props{}
	props.art_file = '/tmp/opencode/no_such_art_file.txt'
	build_art_lines(props, 1) or {
		assert err.msg().contains('cannot read art file')
		return
	}
	panic('a missing art file should have stopped')
}

fn test_output_buildfile_consts() {
	os.chdir(fixture_dir)!
	defer { os.chdir('/tmp/opencode') or {} }
	mut conf := BuildConf{}
	conf.target = 'myfetch'
	conf.zig = 'myzig'
	conf.flags = '-fstrip'
	conf.dest_dir = '/usr/bin'
	conf.def = 'build'
	conf.headgen_file = 'headgen.zig'
	mut fixed := Config{
		sources: [Sources{}]
		modules: map[string]ModuleLip{}
		warned:  map[string]bool{}
	}
	text := output_buildfile(conf, build_regen_args(build_opts()), &fixed, '.tmp/run.zig', '.tmp/bake.zig', '.tmp/run-run.zig')
	assert text.contains("const build_dir = 'target'")
	assert text.contains("const target_exe = os.join_path_single(build_dir, 'myfetch')")
	assert text.contains("const zig = 'myzig'")
	assert text.contains("const zig_flags = '-fstrip'")
	assert text.contains("const install_path = '/usr/bin/myfetch'")
	assert text.contains("ctx.default(['build'])")
	assert text.contains('import x.imp')
	// the rust source rides the crate's [lib path], never the zig argv.
	assert !text.contains("const c_sources = ['modules/hello_world_rustix")
	assert text.contains('const objects = []string{}')
	assert text.contains('const compile_steps = [][]string{}')
	assert text.contains('const compile_shells = []string{}')
	// the default link is bare: no module, no flags.
	assert text.contains('const extra_link = []string{}')
	assert text.contains('const v_bakes = [][]string{}')
	assert !text.contains('const v_bake_ids')
	assert !text.contains('fn esc(value string) string {')
	regen_line := text.split('\n').filter(it.contains('mut regen_args := '))[0]
	if !text.contains('mut regen_args') { panic('no regen') }
	assert regen_line == "mut regen_args := ['v', 'run', 'generator', '-S', '-os', '.tmp/run.zig', '-ohg', '.tmp/headgen.zig', '-oh', '.tmp/bake.zig', '-orun', '.tmp/run-run.zig', '-s', 'config.lip']"
	assert text.contains("os.mkdir_all('.tmp')!")
	assert text.contains('os.symlink')
	assert !text.contains('@import("../')

	assert text.contains("id: 'regen'")
	assert text.contains("id: 'build'")
	assert text.contains("id: 'clean'")
	assert text.contains("id: 'install'")
	assert text.contains("id: 'uninstall'")
	assert text.contains('ctx.add_auto_flow(.run)')
	assert text.ends_with('ctx.flow()\n')
}

fn test_output_buildfile_emits_the_v_bakes_and_ids() {
	os.chdir(fixture_dir)!
	mut cfg := c_shaped_tree()
	cfg.modules['hello_world_v'] = ModuleLip{
		name:     'hello_world_v'
		language: 'v'
		source:   'module.v'
		arg:      'text'
	}
	cfg.sources[0].entries << Entry{
		kind:       'hello_world_v'
		key:        'Hello World V'
		static_:    false
		build_time: true
		bt_id:      0
		arg:        'hi there'
		line:       4
	}
	text := output_buildfile(BuildConf{}, build_regen_args(build_opts()), &cfg, '.tmp/run.zig', '.tmp/bake.zig', '.tmp/run-run.zig')
	assert text.contains("const v_bakes = [['v', 'run', 'modules/hello_world_v/module.v', 'hi there']]")
	assert text.contains('const v_bake_ids = [0]')
	assert text.contains('fn esc(value string) string {')
	assert text.contains('bake_out += \'pub const bt_\' + v_bake_ids[i].str() + \' = "\' + esc(baked.output.trim_space())')
}

fn test_output_buildfile_gains_the_c_source_args() {
	mut cfg := c_shaped_tree()
	text := output_buildfile(BuildConf{}, build_regen_args(build_opts()), &cfg, '.tmp/run.zig', '.tmp/bake.zig', '.tmp/run-run.zig')
	assert text.contains("const c_sources = ['modules/hello_world_c/module.c']")
	// nothing links by default: a lip without :deps keeps the link bare.
	assert text.contains('const extra_link = []string{}')
}

fn test_output_buildfile_links_what_the_deps_say() {
	// :std answers per language and raw deps ride as -l flags.
	mut cfg := c_shaped_tree()
	cfg.modules['hello_world_c'].deps_std = true
	std_c := output_buildfile(BuildConf{}, build_regen_args(build_opts()), &cfg, '.tmp/run.zig', '.tmp/bake.zig', '.tmp/run-run.zig')
	assert std_c.contains("const extra_link = ['-lc']")
	cfg.modules['hello_world_c'].deps_std = false
	cfg.modules['hello_world_c'].deps_libs = ['m', 'pthread']
	raw := output_buildfile(BuildConf{}, build_regen_args(build_opts()), &cfg, '.tmp/run.zig', '.tmp/bake.zig', '.tmp/run-run.zig')
	assert raw.contains("const extra_link = ['-lm', '-lpthread']")
	cfg.modules['hello_world_c'].language = 'd'
	cfg.modules['hello_world_c'].deps_libs = []
	cfg.modules['hello_world_c'].deps_std = true
	std_d := output_buildfile(BuildConf{}, build_regen_args(build_opts()), &cfg, '.tmp/run.zig', '.tmp/bake.zig', '.tmp/run-run.zig')
	// full d rides phobos and druntime, and libc carries them.
	assert std_d.contains("const extra_link = ['-lphobos2', '-lc']")
}

fn test_output_buildfile_steps_carry_the_d_recipe() {
	mut cfg := c_shaped_tree()
	// the default recipe compiles betterC, riding no runtime at all.
	cfg.modules['hello_world_c'].language = 'd'
	cfg.modules['hello_world_c'].source = 'module.d'
	better := output_buildfile(BuildConf{}, build_regen_args(build_opts()), &cfg, '.tmp/run.zig', '.tmp/bake.zig', '.tmp/run-run.zig')
	assert better.contains("const compile_steps = [['dmd', '-c', '-betterC', '-of=modules/hello_world_c/module.o', 'modules/hello_world_c/module.d']]")
	assert better.contains("const objects = ['modules/hello_world_c/module.o']")
	// :std compiles full d and the object joins the phobos link.
	cfg.modules['hello_world_c'].deps_std = true
	full := output_buildfile(BuildConf{}, build_regen_args(build_opts()), &cfg, '.tmp/run.zig', '.tmp/bake.zig', '.tmp/run-run.zig')
	assert !full.contains('-betterC')
	assert full.contains('-of=modules/hello_world_c/module.o')
}

fn test_output_buildfile_carries_the_rust_ext_pairs() {
	// the real sample lip spells :deps [:ext [...]]; the buildfile pairs it
	// with the spellings and the flow steps in cargo for the archive.
	os.chdir(fixture_dir)!
	mut cfg := c_shaped_tree()
	cfg.load_module('hello_world_rustix')!
	cfg.sources[0].entries << Entry{
		kind: 'hello_world_rustix'
		key:  'Ext'
		line: 4
	}
	text := output_buildfile(BuildConf{}, build_regen_args(build_opts()), &cfg, '.tmp/run.zig', '.tmp/bake.zig', '.tmp/run-run.zig')
	assert text.contains("const rust_ext = [['hello_world_rustix', 'module.rs', 'rustix 1.1.* features=[system]']]")
	// the archive rides the objects const, not the zig argv.
	assert text.contains("const objects = ['modules/hello_world_rustix/module.a']")
	// the rust source rides the crate's [lib path], never the zig argv.
	assert !text.contains("const c_sources = ['modules/hello_world_rustix")
	// std carries libc, libunwind answers the std backtrace branches.
	assert text.contains("const extra_link = ['-lc', '-lunwind']")
	// the plain rustc recipe does not run for the ext module: cargo does.
	assert text.contains('const compile_steps = [][]string{}')
	assert text.contains('for pair in rust_ext {')
	assert text.contains("imp.system_args(['cargo', 'build', '--release', '--manifest-path', manifest])")
}

fn test_ext_cargo_toml_walks_the_spellings() {
	mut ext := [ExtCrate{
		name:    'rustix'
		version: '1.1.*'
	}, ExtCrate{
		name:     'libc'
		version:  '0.2'
		features: ['mint']
	}]
	mut lip := ModuleLip{
		name:     'hello_world_rustix'
		fname:    'x'
		language: 'rust'
		source:   'module.rs'
		deps_ext: ext
	}
	toml := ext_cargo_toml('hello_world_rustix', lip)
	assert toml.contains('[package]')
	assert toml.contains('name = "hello_world_rustix"')
	assert toml.contains('path = "module.rs"')
	assert toml.contains('crate-type = ["staticlib"]')
	assert toml.contains('rustix = "1.1.*"')
	assert toml.contains('libc = { version = "0.2", features = ["mint"] }')
	assert toml.contains('[profile.release]')
	assert toml.contains('panic = "abort"')
	// the no-default-features spelling rides too.
	ext[1].no_default_features = true
	lip.deps_ext = ext
	toml2 := ext_cargo_toml('hello_world_rustix', lip)
	assert toml2.contains('libc = { version = "0.2", default-features = false, features = ["mint"] }')
}

fn test_write_ext_projects_lays_the_manifests() {
	os.chdir(fixture_dir)!
	mut cfg := c_shaped_tree()
	cfg.load_module('hello_world_rustix')!
	cfg.sources[0].entries << Entry{
		kind: 'hello_world_rustix'
		key:  'Ext'
		line: 4
	}
	write_ext_projects(cfg)!
	write_ext_projects(cfg)!
	path := os.join_path_single('modules/hello_world_rustix', 'Cargo.toml')
	manifest := os.read_file(path)!
	assert manifest.contains('[dependencies]')
	assert manifest.contains('rustix = { version = "1.1.*", features = ["system"] }')
	assert manifest.contains('panic = "abort"')
	assert manifest.contains('[profile.release]')
	os.rm(path) or {}

	defer {
		os.rm(path) or {}
		dir := os.join_path_single('.imp', 'extcrate')
		os.rmdir(os.join_path_single(dir, 'hello_world_rustix')) or {}
		os.rmdir(dir) or {}
	}
}

fn test_output_buildfile_nostd_links_bare() {
	// the no_std sample names rustix only; the deps carry neither :std nor
	// a library, so the link line stays empty — the no-libc example's rule.
	os.chdir(fixture_dir)!
	mut cfg := c_shaped_tree()
	cfg.load_module('hello_world_rustix_nostd')!
	cfg.sources[0].entries << Entry{
		kind: 'hello_world_rustix_nostd'
		key:  'Nostd'
		line: 4
	}
	text := output_buildfile(BuildConf{}, build_regen_args(build_opts()), &cfg, '.tmp/run.zig', '.tmp/bake.zig', '.tmp/run-run.zig')
	assert text.contains("const rust_ext = [['hello_world_rustix_nostd', 'module.rs', 'rustix 1.1.* no-default-features features=[system]']]")
	assert text.contains("const objects = ['modules/hello_world_rustix_nostd/module.a']")
	assert text.contains('const extra_link = []string{}')
}

fn test_output_source_twin_spawns_only_when_twinned() {
	os.chdir(fixture_dir)!
	// the twin carries the spawn-and-wait blocks; the plain fetch stays
	// clean — the runs belong to divifetch-run alone.
	mut augmented := collected_tree()!
	augmented.sources[0].runs = [RunEntry{
		bin:  './bin/hi'
		args: ['there']
		line: 3
	}]
	twin := output_source(&augmented, ['tree.lip'], '.tmp/run-run.zig', '.tmp/bake.zig', true)
	assert twin.contains('std.process.spawn(io, .{')
	assert twin.contains('.argv = &.{ "./bin/hi", "there" }')
	assert twin.contains('if (!term.success()) return error.TwinChildFailed;')
	plain := output_source(&augmented, ['tree.lip'], '.tmp/run.zig', '.tmp/bake.zig', false)
	assert !plain.contains('std.process.spawn(io, .{')
}

fn test_output_buildfile_wires_the_twin_when_runs_exist() {
	mut cfg := collected_tree()!
	cfg.sources[0].runs = [RunEntry{
		bin:  './bin/hi'
		args: []
		line: 3
	}]
	text := output_buildfile(BuildConf{}, build_regen_args(build_opts()), &cfg, '.tmp/run.zig', '.tmp/bake.zig', '.tmp/run-run.zig')
	assert text.contains("const run_target_exe = os.join_path_single(build_dir, 'divifetch-run')")
	assert text.contains('ctx.add_target(run_target_exe)')
	assert text.contains("run_argv << ['-femit-bin=' + run_target_exe]")
	assert text.contains("\tid: 'run'")
	assert !text.contains('ctx.add_auto_flow(.run)')
	// a config without runs keeps the old shape: the plain fetch is the
	// run flow's target, no twin anything.
	mut plaincfg := collected_tree()!
	plain := output_buildfile(BuildConf{}, build_regen_args(build_opts()), &plaincfg, '.tmp/run.zig', '.tmp/bake.zig', '.tmp/run-run.zig')
	assert !plain.contains('run_target_exe')
	assert plain.contains('ctx.add_auto_flow(.run)')
}

fn test_entry_call_hands_the_list_arg() {
	os.chdir(fixture_dir)!
	// the merged packages module carries the entry's :args as one slice:
	// a single spelling rides a one-item literal, many ride the list, and
	// an arg-less entry rides the empty list for the preset's own round.
	mut cfg := collected_tree()!
	lip := cfg.load_module('packages')!
	assert lip.arg_is_list
	mut e := Entry{
		kind: 'packages'
		key:  'Packages'
		line: 4
	}
	e.arg = 'pacman'
	assert entry_call(&cfg, &e) == 'packages.preset(io, &.{ "pacman" })'
	e = Entry{
		kind: 'packages'
		key:  'Packages'
		line: 4
	}
	e.args = ['pacman', 'xbps']
	assert entry_call(&cfg, &e) == 'packages.preset(io, &.{ "pacman", "xbps" })'
	e = Entry{
		kind: 'packages'
		key:  'Packages'
		line: 4
	}
	e.args = []
	assert entry_call(&cfg, &e) == 'packages.preset(io, &.{})'
}

fn test_build_regen_args_spells_the_outputs() {
	mut opt := CliOpts{}
	opt.out_src = 'else.zig'
	opt.out_headgen = 'else-headgen.zig'
	opt.out_bake = 'else-bake.zig'
	opt.source_confs << 'mine.lip'
	args := build_regen_args(opt)
	assert args == ['v', 'run', 'generator', '-S', '-os', 'else.zig', '-ohg', 'else-headgen.zig',
		'-oh', 'else-bake.zig', '-orun', '.tmp/run-run.zig', '-s', 'mine.lip']
}

fn test_parse_build_conf_defaults_without_a_file() {
	conf := parse_build_conf('build.conf')!
	assert conf.exec == '#!/usr/bin/env -S v run'
	assert conf.zig == 'zig'
	assert conf.flags == '-Doptimize=ReleaseFast -fstrip'
	assert conf.target == 'divifetch'
	assert conf.dest_dir == '/usr/local/bin'
	assert conf.def == 'build'
	assert conf.headgen_file == '.tmp/headgen.zig'
	assert conf.build_dir == 'target'
	assert conf.custom == ''
	assert conf.cc == ''
}

fn test_parse_build_conf_reads_every_field() {
	conf_path := '/tmp/opencode/build_lip.conf'
	os.write_file(conf_path, r'(build :exec "other"
	:zig "myzig"
	:flags "-fstrip"
	:target "mine"
	:headgen-file "hg.zig"
	:dest-dir "/opt/bin"
	:default "clean"
	:build-dir "out"
	:custom "const note = 7"
	:cc "gcc")')!
	defer {
		os.rm(conf_path) or {}
	}
	conf := parse_build_conf(conf_path)!
	assert conf.exec == 'other'
	assert conf.zig == 'myzig'
	assert conf.flags == '-fstrip'
	assert conf.target == 'mine'
	assert conf.headgen_file == 'hg.zig'
	assert conf.dest_dir == '/opt/bin'
	assert conf.def == 'clean'
	assert conf.build_dir == 'out'
	assert conf.custom == 'const note = 7'
	assert conf.cc == 'gcc'
}

fn test_parse_build_conf_unknown_key_stops() {
	conf_path := '/tmp/opencode/build_bad.conf'
	os.write_file(conf_path, '(build :zap "x")')!
	defer {
		os.rm(conf_path) or {}
	}
	parse_build_conf(conf_path) or {
		assert err.msg().contains('build has no key :zap')
		return
	}
	panic('unknown build key should have stopped')
}

fn test_output_example_config_holds_the_shapes() {
	example := output_example_config()
	// the template mirrors the repo's own config: blip defines, the
	// mount_p function, the fetch's chained session comment, and the
	// kinds a fresh checkout carries.
	assert example.contains('(config :art-file "ascii/cat.txt"')
	assert example.contains(':key-prefix dark')
	assert example.contains('(define dark "')
	assert example.contains('(define (mount_p path)')
	assert example.contains('(mount_p "/home")')
	assert example.contains(';(run :bin "zsh")')
	assert example.contains('(colors_bright)') && example.contains('(colors_normal)')
	assert example.contains('(break)')
	assert !example.contains('generator/main.v')
}

fn test_colors_keys_are_eight_blocks() {
	assert colors_normal_key == '\x1b[40m   \x1b[41m   \x1b[42m   \x1b[43m   \x1b[44m   \x1b[45m   \x1b[46m   \x1b[47m   \x1b[0m'
	assert colors_bright_key == '\x1b[100m   \x1b[101m   \x1b[102m   \x1b[103m   \x1b[104m   \x1b[105m   \x1b[106m   \x1b[107m   \x1b[0m'
}

fn test_no_key_entry_prints_the_value_alone() {
	os.chdir(fixture_dir)!
	cfg := collected('(kernel :key "")')!
	line := cfg.entry_text('f.lip', 'x', cfg.sources[0].entries[0])
	// no key block at all: no key-prefix, no colon-bearing suffix; the
	// value prints after the art column.
	assert !line.contains('key-prefix')
	assert !line.contains('{s}:{') || !line.contains('"{s}:{s}')
	assert line.contains('{s}')
}

fn test_fmt_escape_doubles_braces() {
	os.chdir(fixture_dir)!
	cfg := collected('(kernel)')!
	line := cfg.entry_text('f.lip', 'x', Entry{
		kind: 'static'
		key:  '{a}'
	})
	assert line.contains('{{a}}')
}

fn test_entry_call_names_the_kw_shape() {
	os.chdir(fixture_dir)!
	cfg := collected('(battery)')!
	call := entry_call(&cfg, &cfg.sources[0].entries[0])
	assert call == 'battery.preset(io)'
}

fn test_entry_call_with_environ_and_arg() {
	os.chdir(fixture_dir)!
	cfg := collected('(shell) (command :args ["echo hi"]) (mount :args ["/home"])')!
	shell_call := entry_call(&cfg, &cfg.sources[0].entries[0])
	assert shell_call == 'shell.preset(io, environ)'
	command_call := entry_call(&cfg, &cfg.sources[0].entries[1])
	assert command_call == 'command.preset(io, "echo hi")'
	mount_call := entry_call(&cfg, &cfg.sources[0].entries[2])
	assert mount_call == 'mount.preset("/home")'
}

// ─── multi-config selection, :execute and the new languages ─────────────────

fn test_multi_config_carries_one_sources_per_file() {
	os.chdir(fixture_dir)!
	cfg := collected('(kernel)\n(battery)\n')!
	// the two snippets are two files in real runs; here the collector keeps
	// one Sources per file, each with its own entries and props.
	assert cfg.sources.len == 1
	one := collected('(kernel)')!
	two := collected('(battery)')!
	assert one.sources[0].entries.len == 1
	assert two.sources[0].entries.len == 1
}

fn test_output_source_picks_one_at_random_across_sources() {
	os.chdir(fixture_dir)!
	one := collected('(kernel)')!
	two := collected('(battery)')!
	mut cfg := Config{
		sources: [one.sources[0], two.sources[0]]
		modules: one.modules
		warned:  one.warned
	}
	for i, e in cfg.sources[1].entries {
		if e.kind != 'battery' { continue }
		_ = i
		cfg.sources[1].entries[i].build_time = true
		cfg.sources[1].entries[i].bt_id = 0
	}
	text := output_source(&cfg, ['a.lip', 'b.lip'], '.tmp/run.zig', '.tmp/bake.zig', false)
	// each source compiles to a run_<i>, and the main picks one at random:
	// the crypto random and a switch with both arms, with the chosen line's
	// :execute after the flush.
	assert text.contains('    var entropy: [8]u8 = undefined;\n')
	assert text.contains('    io.random(&entropy);\n')
	assert text.contains('    var rand = std.Random.Sfc64.init(std.mem.readInt(u64, &entropy, .little));\n')
	assert text.contains('    const chosen = rand.random().intRangeLessThan(usize, 0, 2);\n')
	assert text.contains('    switch (chosen) {')
	assert text.contains('        0 => try run_0(')
	assert text.contains('        1 => try run_1(')
	assert text.contains('the entries of a.lip')
	assert text.contains('the entries of b.lip')
}

fn test_output_source_executes_the_conf_entry() {
	os.chdir(fixture_dir)!
	one := collected('(kernel)')!
	two_log := '/tmp/opencode/lib__gen_exec_test.lip'
	os.write_file(two_log, '(config :execute "cmatrix | head -40")\n(uptime)\n')!
	defer { os.rm(two_log) or {} }
	two := collect_config([two_log])!
	mut cfg := Config{
		sources: [one.sources[0], two.sources[0]]
		modules: one.modules
		warned:  one.warned
	}
	text := output_source(&cfg, ['a.lip', 'b.lip'], '.tmp/run.zig', '.tmp/bake.zig', false)
	assert text.contains('if (chosen == 1) {')
	assert text.contains('/bin/sh') && text.contains('"cmatrix | head -40" } });')
	// a source without :execute prints none.
	assert text.contains('if (chosen == 0)') == false
}

fn test_normalize_language_unifies_spellings() {
	assert normalize_language('c++') == 'cpp'
	assert normalize_language('cpp') == 'cpp'
	assert normalize_language('zig') == 'zig'
}

fn test_cpp_module_uses_the_default_source_and_shim() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/hw_cpp', 'module.lip', '(module :language "c++" :fn "hw_cpp_module_preset")')
	defer {
		os.rm('modules/hw_cpp/module.lip') or {}
		os.rmdir('modules/hw_cpp') or {}
	}
	mut cfg := collected('(hw_cpp)')!
	lip := cfg.modules['hw_cpp']
	assert lip.language == 'cpp'
	assert lip.source == 'module.cpp'
	// the shim is the c-shaped one; the build script rides the source to zig.
	kinds := c_modules(&cfg)
	assert kinds == ['hw_cpp']
	call := entry_call(&cfg, &cfg.sources[0].entries[0])
	assert call == 'hw_cpp.preset(&hw_cpp_buf)'
}

fn test_rust_module_hands_the_object_to_zig() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/hw_rust', 'module.lip', '(module :language "rust" :fn "hw_rust_module_preset")')
	defer {
		os.rm('modules/hw_rust/module.lip') or {}
		os.rmdir('modules/hw_rust') or {}
	}
	mut cfg := collected('(hw_rust)')!
	assert cfg.modules['hw_rust'].source == 'module.rs'
	// the shim covers rust exactly like c, and the object step appears.
	kinds := c_modules(&cfg)
	assert kinds == ['hw_rust']
	call := entry_call(&cfg, &cfg.sources[0].entries[0])
	assert call == 'hw_rust.preset(&hw_rust_buf)'
}

fn test_compile_steps_cookie_the_rust_staticlib() {
	os.chdir(fixture_dir)!
	mut cfg := c_shaped_tree()
	cfg.modules['hw_rust'] = ModuleLip{
		name:     'hw_rust'
		fname:    'hw_rust_module_preset'
		language: 'rust'
		source:   'module.rs'
	}
	cfg.sources[0].entries << Entry{
		kind: 'hw_rust'
		key:  'Rust'
		line: 4
	}
	steps := compile_steps(&cfg, '')
	assert steps.len == 1
	assert steps[0].shell == ''
	assert steps[0].argv == ['rustc', '--crate-type', 'staticlib', '-C', 'opt-level=2', '-o',
		'modules/hw_rust/module.o', 'modules/hw_rust/module.rs']
	// the object is what zig links.
	objects := object_outputs(&cfg)
	assert objects == ['modules/hw_rust/module.o']
}

fn test_template_expand_fills_the_slots() {
	pat := '$' + '{cc} -O2 -c ' + '$' + '{source_file} -o ' + '$' + '{output_file}'
	out := template_expand(pat, 'g++', 'modules/x/module.cpp', 'modules/x/module.o')
	assert out == 'g++ -O2 -c modules/x/module.cpp -o modules/x/module.o'
}

fn test_compile_steps_run_the_template_command() {
	os.chdir(fixture_dir)!
	mut cfg := c_shaped_tree()
	cfg.modules['hw_cpp2'] = ModuleLip{
		name:             'hw_cpp2'
		fname:            'preset'
		language:         'cpp'
		source:           'module.cpp'
		command:          'g++ -c ' + '$' + '{source_file} -o ' + '$' + '{output_file}'
		object_extension: '.o'
	}
	cfg.sources[0].entries << Entry{
		kind: 'hw_cpp2'
		key:  'X'
		line: 4
	}
	steps := compile_steps(&cfg, 'g++')
	assert steps.len == 1
	assert steps[0].shell == 'g++ -c modules/hw_cpp2/module.cpp -o modules/hw_cpp2/module.o'
	// and its object rides the zig link beside the c sources.
	objects := object_outputs(&cfg)
	assert objects == ['modules/hw_cpp2/module.o']
}

fn test_v_module_command_rejected() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/v_bad', 'module.lip', '(module :language "v" :command "go")')
	defer {
		os.rm('modules/v_bad/module.lip') or {}
		os.rmdir('modules/v_bad') or {}
	}
	collected('(v_bad :build-time yes)') or {
		assert err.msg().contains(':command applies to the compiled languages (c, cpp, rust, d)')
		return
	}
	assert false, 'a v command should have stopped'
}

fn mkdir_one(dir string, file string, content string) {
	os.mkdir_all(dir) or { panic('mkdir failed: ' + err.msg()) }
	os.write_file(dir + '/' + file, content) or { panic('write failed: ' + err.msg()) }
}
