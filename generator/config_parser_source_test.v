// config_parser_source_test.v — the source-config side: the (config ...)
// form, entries and their prebaked kinds, keys, module lips and the zig
// signatures they are checked against, and the collector that ties them.
module main

import os
import blip.vlib.blip.reader

// here is the generator's own directory: the real modules and their lips
// live under modules/, ascii under ../ascii — tests chdir here once.
const fixture_dir = os.abs_path(os.dir(@FILE) + '/..')

// collected writes a snippet to disk and runs the collector over it, so
// every test reads its forms exactly the way the real config reads.
fn collected(snippet string) !Config {
	log := '/tmp/opencode/lib__source_test.lip'
	os.write_file(log, snippet)!
	defer {
		os.rm(log) or {}
	}
	return collect_config([log])
}

// collected_propform — same, with the (config ...) form first inside the snippet.
fn collected_from_propform(config_line string, entry_line string) !Config {
	s := '${config_line}\n${entry_line}'
	return collected(s)
}

fn test_props_defaults() {
	mut props := Props{}
	assert props.buffer_size == 128
	assert props.art_padding == 3
	assert props.art_width == -1
	assert props.art_file == ''
	assert props.key_prefix == ''
	assert props.key_suffix == ''
	assert props.underscore == ' '
	assert props.key_case == 'first'
}

fn test_config_every_field() {
	cfg := collected_from_propform(r'(config :buffer-size 256
        :art-padding 9
        :art-file "ascii/cat.txt"
        :art-prefix "\e[1m"
        :art-suffix "\e[0m"
        :key-prefix "\e[1m"
        :key-suffix " : "
        :value-prefix "<"
        :value-suffix ">"
        :underscore " — "
        :key-case "upper")', '(kernel)')!
	assert cfg.sources[0].entries[0].kp.len == 4
	assert cfg.sources[0].entries[0].ks == ' : '
	assert cfg.sources[0].entries[0].vp == '<'
	assert cfg.sources[0].entries[0].vs == '>'
}

fn test_config_build_time_folds_into_entries() {
	cfg := collected_from_propform('(config :build-time yes)', '(kernel)')!
	assert cfg.sources[0].entries[0].build_time
	assert cfg.sources[0].entries[0].static_ == false
}

fn test_config_new_print_folds_into_entries() {
	cfg := collected_from_propform('(config :new-print yes)', '(kernel)')!
	assert cfg.sources[0].entries[0].new_print
}

fn test_config_unknown_key_stops_the_generator() {
	collected_from_propform('(config :what "x")', '(kernel)') or {
		assert err.msg().contains('config has no key :what')
		return
	}
	panic('unknown config key should have stopped')
}

fn test_config_rejects_positional_values() {
	collected_from_propform('(config 42)', '(kernel)') or {
		assert err.msg().contains('config takes :key value pairs, not positional values')
		return
	}
	panic('config with positional values should have stopped')
}

fn test_config_key_case_must_be_a_known_spelling() {
	collected_from_propform('(config :key-case "weird")', '(kernel)') or {
		assert err.msg().contains('config :key-case must be lower, upper, first or title')
		return
	}
	panic('a wrong :key-case should have stopped')
}

fn test_config_art_width_warns_but_accepts() {
	// :art-width stays for compat; it warns once through this run so the
	// collector must accept it.
	cfg := collected_from_propform('(config :art-width 45)', '(kernel)')!
	assert cfg.sources[0].entries[0].line > 0
}

fn test_config_languages_select_the_search() {
	os.chdir(fixture_dir)!
	// the spellings normalize (c++ → cpp) and merge into the registry's
	// list, exactly in the order the config spells them.
	mut cfg := collected_from_propform('(config :languages [:zig :d :cpp])', '(kernel)')!
	assert cfg.languages == ['zig', 'd', 'cpp']
	assert cfg.sources[0].props.languages == ['zig', 'd', 'cpp']
	// a quoted string spelling rides too: "c++" and :cpp meet in cpp,
	// and the entry behind it loads.
	cfg = collected_from_propform('(config :languages ["c++"])', '(hello_world_cpp)')!
	assert cfg.languages == ['cpp']
	assert cfg.sources[0].entries[0].kind == 'hello_world_cpp'
}

fn test_config_languages_must_be_a_known_spelling() {
	os.chdir(fixture_dir)!
	collected_from_propform('(config :languages [:zig :ruby])', '(kernel)') or {
		assert err.msg().contains("config :languages holds 'ruby'")
		return
	}
	panic('an unknown :languages spelling should have stopped')
}

fn test_config_languages_keep_the_other_dirs_out() {
	os.chdir(fixture_dir)!
	// a zig-only fetch never reaches modules/rust/: the module stops under
	// the named error instead of loading past the selection.
	collected_from_propform('(config :languages [:zig])', '(hello_world_rustix)') or {
		assert err.msg().contains("no module called 'hello_world_rustix'")
		return
	}
	panic('a module outside :languages should have stopped')
}

fn test_language_dirs_default_to_the_whole_tree() {
	// no (config :languages) spelled: every shipped language subdir walks,
	// in the canonical order the kinds bind in.
	cfg := collected_from_propform('', '(kernel)')!
	assert cfg.languages.len == 0
	assert cfg.language_dirs() == accepted_languages
}

fn test_battery_entry_parses_without_a_key() {
	// load_module reads modules/zig/battery/module.lip from the cwd, and
	// the zig preset inside it is what :deps was checked against.
	os.chdir(fixture_dir)!
	cfg := collected_from_propform('', '(battery)')!
	e := cfg.sources[0].entries[0]
	assert e.kind == 'battery'
	assert !e.static_
	assert e.key == 'Battery'
	assert e.arg == ''
	// the emitted call takes the io the lip declared.
	assert cfg.sources[0].needs_env == false
	call := entry_call(&cfg, &cfg.sources[0].entries[0])
	assert call == 'battery.preset(io)'
}

fn test_key_derives_from_kind_and_case() {
	os.chdir(fixture_dir)!
	// the kinds derive with underscores swapped into the configured glue
	// and the configured case, exactly like the C generator derived them.
	cfg := collected_from_propform('(config :key-case "upper")', '(kernel) (hello_world_rustix)')!
	assert cfg.sources[0].entries[0].key == 'KERNEL'
	assert cfg.sources[0].entries[1].key == 'HELLO WORLD RUSTIX'
	underscore_tree := collected_from_propform('(config :underscore "_")', '(hello_world_rustix)')!
	assert underscore_tree.sources[0].entries[0].key == 'Hello_World_Rustix'
}

fn test_static_entry_takes_positionals() {
	os.chdir(fixture_dir)!
	cfg := collected_from_propform('', '(static "OS" "Artix Linux")')!
	e := cfg.sources[0].entries[0]
	assert e.static_
	assert e.kind == 'static'
	assert e.key == 'OS'
	assert e.value == 'Artix Linux'
}

fn test_static_entry_derives_the_default_key() {
	os.chdir(fixture_dir)!
	cfg := collected_from_propform('', '(static "up to date") (static :value "X11")')!
	// inline: a static with no key derives from its kind with the props.
	assert cfg.sources[0].entries[1].key == 'Static'
}

fn test_plain_is_stripped_and_bakes() {
	os.chdir(fixture_dir)!
	cfg := collected_from_propform('(config :key-prefix "K" :key-suffix "S")', '(plain "───")')!
	e := cfg.sources[0].entries[0]
	assert e.static_
	assert e.kind == 'static'
	// prefixes fall off entirely; the single positional is the key.
	assert e.kp == ''
	assert e.ks == ''
	assert e.vp == ''
	assert e.vs == ''
	assert e.key == '───'
	assert e.value == ''
}

fn test_break_renders_a_bare_newline() {
	os.chdir(fixture_dir)!
	cfg := collected_from_propform('', '(break)')!
	e := cfg.sources[0].entries[0]
	assert e.static_
	assert e.kind == 'plain'
	assert e.key == ''
	// with every field empty, the line strips to a newline.
	assert cfg.entry_text('/tmp/f.lip', '', e) == '\\n'
}

fn test_colors_render_blocks_through_the_key() {
	os.chdir(fixture_dir)!
	cfg := collected_from_propform('', '(colors-normal) (colors-bright)')!
	// the blocks ride the key; the bg colors step through 40..47, then the
	// bright ones through 100..107, and both close with a reset.
	normal := cfg.sources[0].entries[0]
	assert normal.kind == 'plain'
	assert normal.key.trim_space() == normal.key
	assert normal.key.contains('\x1b[40m')
	assert normal.key.contains('\x1b[47m   ')
	assert !normal.key.contains('\x1b[100m')
	bright := cfg.sources[0].entries[1]
	assert bright.key.contains('\x1b[100m')
	assert !bright.key.contains('\x1b[40m')
}

fn test_dynamic_takes_a_kw_arguments_vector() {
	os.chdir(fixture_dir)!
	cfg := collected_from_propform('', '(mount :key "Mount (/home)" :args ["/home"])')!
	e := cfg.sources[0].entries[0]
	assert e.kind == 'mount'
	assert e.key == 'Mount (/home)'
	assert e.arg == '/home'
	call := entry_call(&cfg, &e)
	assert call == 'mount.preset("/home")'
}

fn test_dynamic_value_serves_the_argument_too() {
	os.chdir(fixture_dir)!
	// the old C spellings put the module argument in the second positional
	// value; the :value key serves the same slot.
	cfg := collected_from_propform('', '(mount "Mount (x)" "x") (mount :key "y" :value "/y")')!
	assert cfg.sources[0].entries[0].arg == 'x'
	assert cfg.sources[0].entries[1].arg == '/y'
}

fn test_dynamic_args_conflict_rejected() {
	os.chdir(fixture_dir)!
	collected_from_propform('', '(mount :args ["/x"] :value "/y")') or {
		assert err.msg().contains('give one of :value and :args, not both')
		return
	}
	panic('conflicting :value and :args should have stopped')
}

fn test_args_more_than_one_stops() {
	os.chdir(fixture_dir)!
	collected_from_propform('', '(mount :args ["/x" "/y"])') or {
		assert err.msg().contains('modules take one argument, but :args has 2')
		return
	}
	panic('module with two args should have stopped')
}

fn test_static_takes_no_args() {
	os.chdir(fixture_dir)!
	collected_from_propform('', '(static "a" "b" :args ["x"])') or {
		assert err.msg().contains('static takes no :args')
		return
	}
	panic('static with :args should have stopped')
}

fn test_unknown_entry_key_stops() {
	os.chdir(fixture_dir)!
	collected_from_propform('', '(kernel :what "v")') or {
		assert err.msg().contains('kernel has no key :what')
		return
	}
	panic('unknown entry key should have stopped')
}

fn test_entry_rejects_too_many_positionals() {
	os.chdir(fixture_dir)!
	collected_from_propform('', '(static "a" "b" "c" "d" "e" "f" "g")') or {
		assert err.msg().contains('static takes at most 6 positional values')
		return
	}
	panic('seven positionals should have stopped')
}

fn test_environ_needs_come_from_the_lip() {
	os.chdir(fixture_dir)!
	cfg := collected_from_propform('', '(wm)')!
	assert cfg.sources[0].needs_env
}

fn test_environ_needs_stay_out_of_build_time() {
	os.chdir(fixture_dir)!
	// build-time entries run inside headgen, so the fetch entry keeps its
	// environ only when a runtime one asks.
	cfg := collected_from_propform('(config :build-time yes)', '(wm)')!
	assert !cfg.sources[0].needs_env
	assert cfg.sources[0].headgen_env
}

fn test_entries_needs_env_accumulate() {
	os.chdir(fixture_dir)!
	cfg := collected_from_propform('', '(kernel) (wm)')!
	// kernel asks for nothing, wm asks for the environment: the fetch does.
	assert cfg.sources[0].needs_env
}

fn test_headgen_env_accumulates() {
	os.chdir(fixture_dir)!
	cfg := collected_from_propform('(config :build-time yes)', '(kernel) (wm)')!
	assert cfg.sources[0].headgen_env
}

fn test_load_caches_the_module() {
	os.chdir(fixture_dir)!
	mut cfg := Config{
		warned: map[string]bool{}
	}
	first := cfg.load_module('battery')!
	second := cfg.load_module('battery')!
	assert first == second
}

fn test_missing_module_stops_named() {
	os.chdir(fixture_dir)!
	// the dir exists but the lip is absent: the named shape is the error.
	os.mkdir_all('modules/zig/no_such_module')!
	defer {
		os.rmdir('modules/zig/no_such_module') or {}
	}
	mut cfg := Config{
		warned: map[string]bool{}
	}
	cfg.load_module('no_such_module') or {
		assert err.msg().contains("module 'no_such_module' has no module.lip")
		return
	}
	panic('module without lip should have stopped')
}

fn mkdir_one(dir string, file string, content string) {
	os.mkdir_all(dir) or { panic('mkdir failed: ${err.msg()}') }
	os.write_file('${dir}/${file}', content) or { panic('write failed: ${err.msg()}') }
}

fn test_no_module_dir_stops_named() {
	os.chdir(fixture_dir)!
	collected_from_propform('', '(does_not_exist)') or {
		assert err.msg().contains("no module called 'does_not_exist'")
		return
	}
	panic('unknown module should have stopped')
}

fn test_lip_rejects_unknown_keys() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/zig/bad_kind', 'module.lip', '(module :what "x")')
	defer {
		os.rm('modules/zig/bad_kind/module.lip') or {}
		os.rmdir('modules/zig/bad_kind') or {}
	}
	mut cfg := Config{
		warned: map[string]bool{}
	}
	cfg.load_module('bad_kind') or {
		assert err.msg().contains('module has no key :what')
		return
	}
	panic('unknown lip key should have stopped')
}

fn test_language_must_be_a_known_spelling() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/zig/bad_lang', 'module.lip', '(module :language "ruby")')
	defer {
		os.rm('modules/zig/bad_lang/module.lip') or {}
		os.rmdir('modules/zig/bad_lang') or {}
	}
	mut cfg := Config{
		warned: map[string]bool{}
	}
	cfg.load_module('bad_lang') or {
		assert err.msg().contains("module :language must be one of zig, c, cpp, rust, d, v, got 'ruby'")
		return
	}
	panic('unknown language should have stopped')
}

fn test_the_dir_language_and_the_lip_agree() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/zig/misdir', 'module.lip', '(module :language "d" :fn "x")')
	defer {
		os.rm('modules/zig/misdir/module.lip') or {}
		os.rmdir('modules/zig/misdir') or {}
	}
	mut cfg := Config{
		warned: map[string]bool{}
	}
	cfg.load_module('misdir') or {
		assert err.msg().contains('modules/zig/ takes the zig modules, but the lip says :language')
		return
	}
	panic('a lip in the wrong language subdir should have stopped')
}

fn test_c_module_rejects_context_deps() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/c/bad_lang_c', 'module.lip', '(module :language "c" :fn "x" :deps [:io])')
	defer {
		os.rm('modules/c/bad_lang_c/module.lip') or {}
		os.rmdir('modules/c/bad_lang_c') or {}
	}
	mut cfg := Config{
		warned: map[string]bool{}
	}
	cfg.load_module('bad_lang_c') or {
		assert err.msg().contains("context is a zig module's concern")
		return
	}
	panic('c module with io should have stopped')
}

fn test_rust_module_carries_the_std_dep() {
	// the real sample lip spells :deps [:std]; it loads with the flag set.
	os.chdir(fixture_dir)!
	mut cfg := Config{
		warned: map[string]bool{}
	}
	lip := cfg.load_module('hello_world_rust')!
	assert lip.language == 'rust'
	assert lip.deps_std
	// without the spelling the crate links bare (no_std style).
	mkdir_one('modules/rust/bare_rust', 'module.lip', '(module :language "rust" :fn "x")')
	defer {
		os.rm('modules/rust/bare_rust/module.lip') or {}
		os.rmdir('modules/rust/bare_rust') or {}
	}
	mut bare := Config{
		warned: map[string]bool{}
	}
	assert !bare.load_module('bare_rust')!.deps_std
}

fn test_c_module_spells_the_std_dep_too() {
	// c and cpp accept the same spelling for uniformity, though their libc
	// rides the link regardless.
	os.chdir(fixture_dir)!
	mkdir_one('modules/c/std_c', 'module.lip', '(module :language "c" :fn "x" :deps [:std])')
	defer {
		os.rm('modules/c/std_c/module.lip') or {}
		os.rmdir('modules/c/std_c') or {}
	}
	mut cfg := Config{
		warned: map[string]bool{}
	}
	cfg.load_module('std_c')!
}

fn test_rust_module_rejects_context_deps() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/rust/bad_rust', 'module.lip', '(module :language "rust" :fn "x" :deps [:io])')
	defer {
		os.rm('modules/rust/bad_rust/module.lip') or {}
		os.rmdir('modules/rust/bad_rust') or {}
	}
	mut cfg := Config{
		warned: map[string]bool{}
	}
	cfg.load_module('bad_rust') or {
		assert err.msg().contains("context is a zig module's concern")
		return
	}
	panic('rust module with io should have stopped')
}

fn test_compiled_module_rejects_non_library_deps() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/rust/bad_deps', 'module.lip', '(module :language "rust" :fn "x" :deps ["so/no"])')
	defer {
		os.rm('modules/rust/bad_deps/module.lip') or {}
		os.rmdir('modules/rust/bad_deps') or {}
	}
	mut cfg := Config{
		warned: map[string]bool{}
	}
	cfg.load_module('bad_deps') or {
		assert err.msg().contains(":deps holds 'so/no'")
		assert err.msg().contains('name the libraries to link')
		return
	}
	panic('non-library dep should have stopped')
}

fn test_v_module_rejects_the_std_dep() {
	// v has no link stage, so even :std is meaningless there.
	os.chdir(fixture_dir)!
	mkdir_one('modules/v/std_v', 'module.lip', '(module :language "v" :deps [:std])')
	defer {
		os.rm('modules/v/std_v/module.lip') or {}
		os.rmdir('modules/v/std_v') or {}
	}
	mut cfg := Config{
		warned: map[string]bool{}
	}
	cfg.load_module('std_v') or {
		assert err.msg().contains(':deps does not apply')
		return
	}
	panic('v module with std should have stopped')
}

fn test_d_module_names_the_libraries_it_links() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/d/lib_d', 'module.lip', '(module :language "d" :fn "x" :deps [:c :m])')
	defer {
		os.rm('modules/d/lib_d/module.lip') or {}
		os.rmdir('modules/d/lib_d') or {}
	}
	mut cfg := Config{
		warned: map[string]bool{}
	}
	lip := cfg.load_module('lib_d')!
	assert lip.language == 'd'
	assert lip.source == 'module.d'
	assert lip.deps_libs == ['c', 'm']
	assert !lip.deps_std
}

fn test_d_module_carries_the_std_dep() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/d/std_d', 'module.lip', '(module :language "d" :fn "x" :deps [:std])')
	defer {
		os.rm('modules/d/std_d/module.lip') or {}
		os.rmdir('modules/d/std_d') or {}
	}
	mut cfg := Config{
		warned: map[string]bool{}
	}
	lip := cfg.load_module('std_d')!
	assert lip.deps_std
	assert lip.deps_libs.len == 0
}

fn test_d_module_rejects_context_deps() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/d/bad_d', 'module.lip', '(module :language "d" :fn "x" :deps [:io])')
	defer {
		os.rm('modules/d/bad_d/module.lip') or {}
		os.rmdir('modules/d/bad_d') or {}
	}
	mut cfg := Config{
		warned: map[string]bool{}
	}
	cfg.load_module('bad_d') or {
		assert err.msg().contains("context is a zig module's concern")
		return
	}
	panic('d module with io should have stopped')
}

fn test_d_module_rejects_non_library_deps() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/d/junk_d', 'module.lip', '(module :language "d" :fn "x" :deps ["c m"])')
	defer {
		os.rm('modules/d/junk_d/module.lip') or {}
		os.rmdir('modules/d/junk_d') or {}
	}
	mut cfg := Config{
		warned: map[string]bool{}
	}
	cfg.load_module('junk_d') or {
		assert err.msg().contains(":deps holds 'c m'")
		return
	}
	panic('non-library dep should have stopped')
}

fn test_rust_ext_spells_the_crates() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/rust/extspec', 'module.lip',
		'(module :language "rust" :fn "x" :deps [:ext ["rustix" "rustix 1.1.* features=[system]" "libc 0.2 no-default-features"]])')
	defer {
		os.rm('modules/rust/extspec/module.lip') or {}
		os.rmdir('modules/rust/extspec') or {}
	}
	mut cfg := Config{
		warned: map[string]bool{}
	}
	lip := cfg.load_module('extspec')!
	assert lip.deps_ext.len == 3
	assert lip.deps_ext[0].name == 'rustix'
	assert lip.deps_ext[0].version == ''
	assert lip.deps_ext[1].version == '1.1.*'
	assert lip.deps_ext[1].features == ['system']
	assert lip.deps_ext[2].name == 'libc'
	assert lip.deps_ext[2].version == '0.2'
	assert lip.deps_ext[2].no_default_features
}

fn test_rust_ext_without_the_crate_list_stops() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/rust/extbare', 'module.lip', '(module :language "rust" :fn "x" :deps [:ext])')
	defer {
		os.rm('modules/rust/extbare/module.lip') or {}
		os.rmdir('modules/rust/extbare') or {}
	}
	mut cfg := Config{
		warned: map[string]bool{}
	}
	cfg.load_module('extbare') or {
		assert err.msg().contains('the :ext entry takes the crates it names')
		return
	}
	panic(':ext without crates should have stopped')
}

fn test_rust_ext_rejects_a_tangled_token() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/rust/extjunk', 'module.lip', '(module :language "rust" :fn "x" :deps [:ext ["rustix security=middle"]])')
	defer {
		os.rm('modules/rust/extjunk/module.lip') or {}
		os.rmdir('modules/rust/extjunk') or {}
	}
	mut cfg := Config{
		warned: map[string]bool{}
	}
	cfg.load_module('extjunk') or {
		assert err.msg().contains('takes its version requirement, no-default-features and features=[..]')
		return
	}
	panic('a tangled crate token should have stopped')
}

fn test_compiled_module_rejects_the_ext_dep() {
	// extern crates ride cargo, and cargo is a rust story.
	os.chdir(fixture_dir)!
	mkdir_one('modules/c/badext', 'module.lip', '(module :language "c" :fn "x" :deps [:ext ["libc"]])')
	defer {
		os.rm('modules/c/badext/module.lip') or {}
		os.rmdir('modules/c/badext') or {}
	}
	mut cfg := Config{
		warned: map[string]bool{}
	}
	cfg.load_module('badext') or {
		assert err.msg().contains(":deps :ext is a rust module's")
		return
	}
	panic('c module with ext deps should have stopped')
}

fn test_packages_entry_takes_the_backend_list() {
	os.chdir(fixture_dir)!
	// the merged packages module takes the entry's :args as one list
	// argument: single spellings land in arg, many spellings land entire.
	mut cfg := Config{
		warned: map[string]bool{}
	}
	lip := cfg.load_module('packages')!
	assert lip.arg_is_list
	collected := collected_from_propform('', '(packages :args ["pacman" "xbps"])')!
	assert collected.sources[0].entries[0].args == ['pacman', 'xbps']
	assert collected.sources[0].entries[0].arg == ''
}

fn test_single_arg_module_rejects_the_list() {
	// a preset with one plain argument keeps the one-at-most rule.
	os.chdir(fixture_dir)!
	collected_from_propform('', '(command :args ["echo hi" "extra"])') or {
		assert err.msg().contains('modules take one argument, but :args has 2')
		return
	}
	panic('a list on a single-arg module should have stopped')
}

fn test_v_module_lives_without_a_fn() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/v/bare_v', 'module.lip', '(module :language "v")')
	defer {
		os.rm('modules/v/bare_v/module.lip') or {}
		os.rmdir('modules/v/bare_v') or {}
	}
	mut cfg := Config{
		warned: map[string]bool{}
	}
	lip := cfg.load_module('bare_v')!
	assert lip.language == 'v'
	assert lip.source == 'module.v'
}

fn test_v_module_requires_the_build_time() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/v/bare_v', 'module.lip', '(module :language "v")')
	defer {
		os.rm('modules/v/bare_v/module.lip') or {}
		os.rmdir('modules/v/bare_v') or {}
	}
	collected_from_propform('', '(bare_v)') or {
		assert err.msg().contains(':language v entries run at build time')
		return
	}
	panic('v entry without build-time should have stopped')
}

fn test_cross_check_catches_a_dep_mismatch() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/zig/mis_lip', 'module.lip', '(module :fn "preset")')
	defer {
		os.rm('modules/zig/mis_lip/module.lip') or {}
		os.rm('modules/zig/mis_lip/module.zig') or {}
		os.rmdir('modules/zig/mis_lip') or {}
	}
	// the zig source reads io while the lip claims none.
	os.write_file('modules/zig/mis_lip/module.zig', 'pub fn preset(io: std.Io) []const u8 {')!
	mut cfg := Config{
		warned: map[string]bool{}
	}
	cfg.load_module('mis_lip') or {
		assert err.msg().contains(':deps is []')
		assert err.msg().contains('add :io')
		return
	}
	panic('stale :deps should have failed')
}

fn test_cross_check_catches_an_arg_mismatch() {
	os.chdir(fixture_dir)!
	mkdir_one('modules/zig/mis_arg', 'module.lip', '(module :fn "preset" :arg :mountpoint)')
	defer {
		os.rm('modules/zig/mis_arg/module.lip') or {}
		os.rm('modules/zig/mis_arg/module.zig') or {}
		os.rmdir('modules/zig/mis_arg') or {}
	}
	// the zig names it path, the lip says mountpoint.
	os.write_file('modules/zig/mis_arg/module.zig', 'pub fn preset(path: []const u8) []const u8 {')!
	mut cfg := Config{
		warned: map[string]bool{}
	}
	cfg.load_module('mis_arg') or {
		assert err.msg().contains("module.zig names the argument 'path'")
		return
	}
	panic('mismatched :arg should have failed')
}

fn test_read_zig_signature_pulls_the_shape() {
	os.chdir(fixture_dir)!
	sig := read_zig_signature('modules/zig/shell', 'preset')!
	assert sig.io
	assert sig.env
	assert sig.args.len == 0
	pkg := read_zig_signature('modules/zig/packages', 'preset')!
	assert pkg.io
	assert !pkg.env
	assert pkg.args.len == 1
	assert pkg.args[0] == 'args'
	command_sig := read_zig_signature('modules/zig/command', 'preset')!
	assert command_sig.io
	assert command_sig.env == false
	assert command_sig.args.len == 1
	assert command_sig.args[0] == 'command'
}

fn test_collect_source_accumulates_orders() {
	os.chdir(fixture_dir)!
	cfg := collected_from_propform('', '(kernel) (battery) (break) (uptime)')!
	assert cfg.sources[0].entries.len == 4
	assert cfg.sources[0].entries[0].kind == 'kernel'
	assert cfg.sources[0].entries[1].kind == 'battery'
	assert cfg.sources[0].entries[2].kind == 'plain' // break prebaked
	assert cfg.sources[0].entries[3].kind == 'uptime'
}

fn test_collect_gives_the_props_from_the_last_config_write() {
	os.chdir(fixture_dir)!
	// the snippets mount their own (config ...) form on top; assert the
	// props fold through the entry table: the last file's config wins and
	// entries from the same file read its fold.
	cfg := collected(r'(config :key-prefix "K")
(kernel)
(config :key-suffix "S")
(battery)')!
	assert cfg.sources[0].entries[0].kp == 'K'
	assert cfg.sources[0].entries[1].ks == 'S'
}

fn test_entry_text_composes_static_lines() {
	os.chdir(fixture_dir)!
	cfg := collected_from_propform('(config :key-prefix "K" :key-suffix "S" :value-prefix "V" :value-suffix "W")', '(static "OS" "Artix Linux")')!
	line := cfg.entry_text('f.lip', '', cfg.sources[0].entries[0])
	assert line == 'KOSSVArtix LinuxW\\n'
}

fn test_entry_text_carries_the_value_slot_for_dynamic() {
	os.chdir(fixture_dir)!
	cfg := collected_from_propform('(config :key-prefix "\e" :key-suffix ": ")', '(kernel)')!
	line := cfg.entry_text('f.lip', '', cfg.sources[0].entries[0])
	assert line.contains('{s}')
	assert entry_call(&cfg, &cfg.sources[0].entries[0]) == 'kernel.preset()'
}

fn test_entry_text_holds_the_art_in_front() {
	os.chdir(fixture_dir)!
	cfg := collected_from_propform('(config :key-prefix "K")', '(break)')!
	line := cfg.entry_text('f.lip', '  art  ', cfg.sources[0].entries[0])
	assert line.starts_with('  art  ')
}

fn test_bake_ids_names_build_time_entries() {
	// the parse itself assigns bt ids in registry order: runtime entries
	// stay at -1 while each build-time entry claims its constant.
	os.chdir(fixture_dir)!
	cfg := collected_from_propform('', '(packages :build-time yes) (kernel) (wm :build-time yes)')!
	ids := cfg.sources[0].entries.map(it.bt_id)
	assert ids == [0, -1, 1]
}

fn test_entry_positions_fill_in_order() {
	os.chdir(fixture_dir)!
	// positional values run key, value, then key/values prefix pairs.
	cfg := collected_from_propform('(config :key-prefix "" :key-suffix "" :value-prefix "" :value-suffix "")',
		'(static "a" "b" "c" "d" "e" "f")')!
	e := cfg.sources[0].entries[0]
	assert e.key == 'a'
	assert e.value == 'b'
	assert e.kp == 'c'
	assert e.ks == 'd'
	assert e.vp == 'e'
	assert e.vs == 'f'
}

fn test_run_forms_chain_in_order() {
	os.chdir(fixture_dir)!
	// the run section: each (run ...) form chains one binary after the
	// last, with the :bin required and the :args list allowed to be empty.
	cfg := collected_from_propform('', '(run :bin "./bin/a" :args ["x" "y"]) (run :bin "./bin/b")')!
	assert cfg.sources[0].runs.len == 2
	assert cfg.sources[0].runs[0].bin == './bin/a'
	assert cfg.sources[0].runs[0].args == ['x', 'y']
	assert cfg.sources[0].runs[1].bin == './bin/b'
	assert cfg.sources[0].runs[1].args.len == 0
}

fn test_run_form_rejects_todo() {
	os.chdir(fixture_dir)!
	collected_from_propform('', '(run :args ["x"])') or {
		assert err.msg().contains('run :bin is required')
		return
	}
	panic('a run without :bin should have stopped')
}

fn test_spelled_empty_key_means_no_key() {
	os.chdir(fixture_dir)!
	// a spelled :key "" is a choice, not a missing spelling: the derive
	// kicker stays off and the entry's key really is empty.
	cfg := collected_from_propform('', '(kernel :key "") (packages)')!
	assert cfg.sources[0].entries[0].no_key
	assert cfg.sources[0].entries[0].key == ''
	assert !cfg.sources[0].entries[1].no_key
	assert cfg.sources[0].entries[1].key == 'Packages'
}

fn test_reader_diagnostics_reach_collector() {
	os.chdir(fixture_dir)!
	collected('(config :key-prefix "x"') or {
		// the message names the snippet path and the reader position.
		assert err.msg().contains('lib__source_test.lip:')
		return
	}
	panic('an unterminated form should have stopped')
}
