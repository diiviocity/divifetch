// config_parser_source.v — the source-config side: the (config...) form,
// the entries, the module lips they reference and the zig signatures they
// cross-check, and the collector that reads every config file in order.
// the divifetch-zig generator.
module main

import blip.vlib.blip.reader
import os

// ─── model ────────────────────────────────────────────────────────────────

// Props are the (config ...) fields. the defaults are the ones the C
// generator had: prefixes unset, underscore a space, keys in first-case.
struct Props {
mut:
	buffer_size  int = 128
	art_padding  int = 3
	art_width    int = -1
	art_file     string
	art_prefix   string
	art_suffix   string
	key_prefix   string
	key_suffix   string
	value_prefix string
	value_suffix string
	underscore   string = ' '
	key_case     string = 'first'
	build_time   bool
	new_print    bool
	execute      string
}

// Entry is one line of output. the config's own values are folded in at
// parse time, the way the C generator folded them into every entry, so the
// emitter needs no second copy of the props.
struct Entry {
mut:
	kind       string   // with '_', so kinds and module dirs agree
	args       []string // the :args list spelling, for a list-arg module
	key        string   // '' derives from the kind
	value      string   // static text; the colors entries' blocks live in the key
	arg        string   // the one argument passed to a dynamic preset
	kp         string
	ks         string
	vp         string
	vs         string
	no_key     bool // a spelled :key "" — the key block leaves the line
	static_    bool // a static entry bakes at generation; the rest call presets
	build_time bool // a build-time entry is run once by headgen, then baked
	new_print  bool // a new_print entry takes its own print statement
	bt_id      int = -1 // the bake constant it lands on, -1 for runtime entries
	line       int // where the entry form starts, for run.zig's comments
}

// RunEntry is one (run ...) form: the binary divifetch-run executes
// after the fetch's own lines, with the argv its :args spells (an
// empty args list is fine; the :bin is required).
struct RunEntry {
mut:
	bin  string   // the :bin path, exec'd as spelled
	args []string // the :args list, in order
	line int      // where the form starts, for the planted comment
}

// ModuleLip is what a (module ...) form says: the entry function, the
// runtime context it gets, and its argument, if any.
// ExtCrate is one extern crate a rust module's :deps :ext names: the
// spelling rides the manifest cargo builds its objects from.
struct ExtCrate {
pub mut:
	name                string
	version             string
	features            []string
	no_default_features bool
}

struct ModuleLip {
mut:
	name             string
	fname            string
	deps_io          bool
	deps_env         bool
	deps_std         bool       // :std — this language's standard library link
	deps_libs        []string   // the libraries to link, each as a -l flag
	deps_ext         []ExtCrate // rust only: the extern crates that ride cargo
	deps_raw         []string   // the spelling as read, validated once language lands
	ext_raw          []string   // the :ext crate spellings as read
	arg              string
	arg_is_list      bool // the zig preset takes :args as a list
	language         string = 'zig'
	source           string
	command          string // a template override, like upstream's module.conf
	object_extension string = '.o'
	linker_flags     []string
}

// Sources is everything parsed: the entries in output order, the modules
// they reference (cached per name), the needs that drive run.zig's context
// plumbing, the art column, and the warnings already printed.
// LogSources is one config file's shape: entries in output order, the
// props they folded in, the art column built for them, and their module
// needs. the registry keeps the shared cache, warnings and bake ids.
struct Sources {
mut:
	entries     []Entry
	runs        []RunEntry // the (run ...) forms, in source order
	needs_env   bool       // a runtime entry reads the environment
	headgen_env bool       // a build-time entry reads the environment
	props       Props
	execute     string   // the file's (config :execute), run at fetch end
	param_sig   string   // zig params of run_<i>, as the dispatch passes them
	call_args   string   // zig args of the run_<i> call
	art_lines   []string // the art column, one line per entry, predecorated
}

// Config is the whole registry: one Sources per config file, the module
// lips every file referenced (cached by name), warnings once anywhere, and
// the running bake id that build-time entries claim in order.
struct Config {
mut:
	sources    []Sources
	modules    map[string]ModuleLip
	warned     map[string]bool
	next_bt_id int
}

// ─── key rendering ────────────────────────────────────────────────────────

// title_case capitalises the first letter of every word, where a word starts
// after ' ' or '_'. underscores stay in place, so the kinds render as
// Packages_Dpkg first and the caller substitutes them afterwards.
fn title_case(s string) string {
	mut cap := true
	mut out := []u8{}
	for b in s.bytes() {
		mut nb := b
		if cap && b >= u8(97) && b <= u8(122) {
			nb = b - u8(32)
		}
		if b == u8(32) || b == u8(95) {
			cap = true
		} else {
			cap = false
		}
		out << nb
	}
	return out.bytestr()
}

// derive_key renders the default key of an entry with no explicit key: the
// kind name, underscores swapped for the configured glue, in the configured
// case, exactly like the C generator's key handling.
fn derive_key(kind string, props &Props) string {
	match props.key_case {
		'lower' { return kind.to_lower().replace('_', props.underscore) }
		'upper' { return kind.to_upper().replace('_', props.underscore) }
		'first', 'title' { return title_case(kind).replace('_', props.underscore) }
		else { return kind } // :key-case is validated at parse, this is a net
	}
}

// ─── the (config ...) form ────────────────────────────────────────────────

fn (mut p Props) parse_form(cfg &Config, path string, head reader.NodeId, arena &reader.Arena) ! {
	args := keyword_args(arena, path, 'config', head)!
	if args.positional.len > 0 {
		return error(at(path, arena.node(args.positional[0]), 'config takes :key value pairs, not positional values'))
	}
	for pair in args.pairs {
		d := arena.node(pair.value)
		match pair.key {
			'buffer-size' {
				// modules own their buffers; the field stays for compat.
				p.buffer_size = int(int_of(arena, pair.value, path, 'config :buffer-size')!)
				cfg.warn_once('config :buffer-size is not used by the zig generator')
			}
			'art-padding' {
				p.art_padding = int(int_of(arena, pair.value, path, 'config :art-padding')!)
			}
			'art-width' {
				p.art_width = int(int_of(arena, pair.value, path, 'config :art-width')!)
				cfg.warn_once('config :art-width is deprecated, use :art-padding instead')
			}
			'art-file' {
				p.art_file = str_of(arena, pair.value, path, 'config :art-file')!
			}
			'art-prefix' {
				p.art_prefix = str_of(arena, pair.value, path, 'config :art-prefix')!
			}
			'art-suffix' {
				p.art_suffix = str_of(arena, pair.value, path, 'config :art-suffix')!
			}
			'key-prefix' {
				p.key_prefix = str_of(arena, pair.value, path, 'config :key-prefix')!
			}
			'key-suffix' {
				p.key_suffix = str_of(arena, pair.value, path, 'config :key-suffix')!
			}
			'value-prefix' {
				p.value_prefix = str_of(arena, pair.value, path, 'config :value-prefix')!
			}
			'value-suffix' {
				p.value_suffix = str_of(arena, pair.value, path, 'config :value-suffix')!
			}
			'underscore' {
				p.underscore = str_of(arena, pair.value, path, 'config :underscore')!
			}
			'key-case' {
				kc := str_of(arena, pair.value, path, 'config :key-case')!
				if kc !in ['lower', 'upper', 'first', 'title'] {
					return error(at(path, d, "config :key-case must be lower, upper, first or title, got '${kc}'"))
				}
				p.key_case = kc
			}
			'build-time' {
				// the C generator's default: build-time entries run once by
				// headgen and bake, so the fetch never repeats them.
				p.build_time = yes_no(arena, pair.value, path, 'config :build-time')!
			}
			'new-print' {
				//发音 batched statics split off their own print statement.
				p.new_print = yes_no(arena, pair.value, path, 'config :new-print')!
			}
			'execute' {
				p.execute = str_of(arena, pair.value, path, 'config :execute')!
			}
			else {
				return error(at(path, d, 'config has no key :${pair.key}'))
			}
		}
	}
}

// ─── entry forms ──────────────────────────────────────────────────────────

// parse_entry reads one entry form. props are folded in first, so each
// field starts as the config's own value; positionals and named pairs
// override.
fn (mut cfg Config) parse_entry(of int, path string, kind_raw string, head reader.NodeId, arena &reader.Arena, props &Props) ! {
	kind := normalize_name(kind_raw)
	mut e := Entry{
		kind:       kind
		kp:         props.key_prefix
		ks:         props.key_suffix
		vp:         props.value_prefix
		vs:         props.value_suffix
		new_print:  props.new_print
		build_time: props.build_time
		line:       arena.node(head).line
	}
	mut prebaked := false

	// the prebaked kinds fold directly, like the C generator: plain and
	// break lose all prefixes (a break prints its bare newline), and the
	// colors entries render their blocks through the key.
	if kind == 'break' {
		e.kind, prebaked = 'plain', true
	} else if kind == 'colors_normal' || kind == 'colors_bright' {
		e.kind, prebaked = 'plain', true
		e.key = if kind == 'colors_normal' { colors_normal_key } else { colors_bright_key }
	} else if kind == 'plain' {
		e.kind, prebaked = 'static', true
	}

	if prebaked {
		e.static_, e.kp, e.ks, e.vp, e.vs = true, '', '', '', ''
	} else {
		e.static_ = kind in static_kinds
	}

	// dynamic entries look their module up first: an unknown kind fails
	// before its fields are read, so the error names the form, not a field.
	mut lip := ModuleLip{}
	if !e.static_ {
		lip = cfg.load_module(kind) or { return error(err.msg()) }
	}

	args := keyword_args(arena, path, kind, head)!

	// positional values: key, value, then the prefix overrides.
	for pi, pid in args.positional {
		if pi >= entry_positions.len {
			return error(at(path, arena.node(pid), '${kind} takes at most ${entry_positions.len} positional values'))
		}
		cfg.entry_field(path, kind, entry_positions[pi], pid, arena, &lip, mut e)!
	}

	// named pairs, on top of the positional ones.
	for pair in args.pairs {
		cfg.entry_field(path, kind, pair.key, pair.value, arena, &lip, mut e)!
	}

	// the fallback key derives at parse time, where props still live.
	// a spelled :key "" means no key: the derive stays off, the key
	// block leaves the line.
	if e.key == '' && !e.no_key && !prebaked {
		if e.static_ {
			e.key = derive_key(kind_of_derive(e.kind), props)
		} else {
			e.key = derive_key(e.kind, props)
		}
	}

	// dynamic entries: fields read, needs are theirs. a module that takes no
	// argument rejects the one it was given, so nothing is silently dropped.
	// build-time entries hand their needs to headgen, not to the fetch, and
	// V entries are always build-time: they bake once, then they are text.
	if !e.static_ {
		if e.arg != '' && lip.arg == '' {
			return error('${path}: module ${kind} takes no argument, but an argument was given (drop :args)')
		}
		if lip.language == 'v' {
			if !e.build_time {
				return error('${path}: :language v entries run at build time — add :build-time yes, or a config-level :build-time "yes"')
			}
		} else if e.build_time {
			e.bt_id = cfg.next_bt_id
			cfg.next_bt_id++
			cfg.sources[of].headgen_env = cfg.sources[of].headgen_env || lip.deps_env
		} else {
			cfg.sources[of].needs_env = cfg.sources[of].needs_env || lip.deps_env
		}
	}

	cfg.sources[of].entries << e
}

// kind_of_derive names the field used to derive a static entry's fallback key:
// the C generator normalized prebaked kinds before deriving, where one still
// used.
fn kind_of_derive(kind string) string {
	return if kind == 'static' { 'static' } else { kind }
}

// entry_field sets one entry field, by positional name or named key.
fn (mut cfg Config) entry_field(path string, kind string, field string, id reader.NodeId, arena &reader.Arena, lip &ModuleLip, mut e Entry) ! {
	d := arena.node(id)
	match field {
		'key' {
			// a spelled key re-decides the no-key choice each time: only
			// an EMPTY spelling leaves the entry keyless.
			e.key = str_of(arena, id, path, '${kind} key')!
			e.no_key = e.key == ''
		}
		'value' {
			if e.static_ {
				e.value = str_of(arena, id, path, '${kind} value')!
			} else {
				if e.arg != '' {
					return error(at(path, d, '${kind}: give one of :value and :args, not both'))
				}
				e.arg = str_of(arena, id, path, '${kind} argument')!
			}
		}
		'args' {
			if e.static_ {
				return error(at(path, d, '${kind} takes no :args'))
			}
			if e.arg != '' || e.args.len > 0 {
				return error(at(path, d, '${kind}: give one of :value and :args, not both'))
			}
			list := list_of(arena, id, path, '${kind} :args')!
			if list.len > 1 {
				// only a preset that takes the list shape can hold many
				// items; everything else carries one argument at most.
				if !lip.arg_is_list {
					return error(at(path, d, '${kind}: modules take one argument, but :args has ${list.len}'))
				}
				e.args = list
			} else if list.len == 1 {
				e.arg = list[0]
			}
		}
		'key-prefix' {
			e.kp = str_of(arena, id, path, '${kind} :key-prefix')!
		}
		'key-suffix' {
			e.ks = str_of(arena, id, path, '${kind} :key-suffix')!
		}
		'value-prefix' {
			e.vp = str_of(arena, id, path, '${kind} :value-prefix')!
		}
		'value-suffix' {
			e.vs = str_of(arena, id, path, '${kind} :value-suffix')!
		}
		'build-time' {
			// this entry is run once by headgen and baked, not at fetch time.
			e.build_time = yes_no(arena, id, path, '${kind} :build-time')!
		}
		'new-print' {
			// splits the batch: this entry leaves its own print statement.
			e.new_print = yes_no(arena, id, path, '${kind} :new-print')!
		}
		else {
			return error(at(path, d, '${kind} has no key :${field}'))
		}
	}
}

// ─── module lips ──────────────────────────────────────────────────────────

// load_module reads modules/<name>/module.lip once per module: the
// (module ...) form names the entry function, the runtime context it gets,
// and its argument, if any. the zig signature is cross-checked immediately,
// so a stale lip stops the generator instead of the compiler.
fn (mut cfg Config) load_module(name string) !ModuleLip {
	if name in cfg.modules {
		return cfg.modules[name]
	}
	if !os.is_dir('modules/${name}') {
		return error("no module called '${name}': modules/${name}/ does not exist")
	}
	lip_path := 'modules/${name}/module.lip'
	text := os.read_file(lip_path) or {
		return error("module '${name}' has no module.lip: write modules/${name}/module.lip")
	}
	// the lip's forms are blip now: one machine per read, the module
	// builtin joins the prims so `(define ...)` and any blip expression
	// feeds the spellings, and the walk rides the synthesized form.
	mut lip := collect_lip(name, lip_path, text)!
	if lip.fname == '' && lip.language != 'v' {
		return error('${lip_path} needs a :fn')
	}
	// template overrides ride the compiled languages; v bakes up arguments
	// entirely on the recipes the generator already knows.
	if lip.command != '' && lip.language == 'v' {
		return error("${lip_path}: :command applies to the compiled languages (c, cpp, rust, d); a V module is baked with 'v run'")
	}
	// Compiled-languages modules: the exported symbol is what :fn names, the
	// caller passes only buffers, and the build script feeds :source to oak.
	// the zig signature cross-check does not apply to them.
	if lip.language == 'zig' {
		if lip.source != '' {
			return error("${lip_path}: :source only applies to the compiled languages and v; zig mixes in the dir's own module.zig")
		}
		for dep in lip.deps_raw {
			match dep {
				'io' { lip.deps_io = true }
				'environ' { lip.deps_env = true }
				else {
					return error("${lip_path}: :deps holds '${dep}' — a zig module takes io and/or environ alone")
				}
			}
		}
		cfg.cross_check(name, mut lip)!
	} else {
		// the link takes what the lip says, nothing by default: each dep is
		// a library to name on the link line, and :std stands for this
		// language's standard library (rust: libc beside the embedded
		// staticlib; d: phobos and druntime riding full D). io and environ
		// are not link things: a compiled preset takes buffers alone.
		for dep in lip.deps_raw {
			if lip.language == 'v' {
				return error('${lip_path}: :deps does not apply — a V module is run once as a script')
			}
			if dep == 'std' {
				lip.deps_std = true
				continue
			}
			if dep in ['io', 'environ'] {
				return error("${lip_path}: :deps holds '${dep}' — context is a zig module's concern; a ${lip.language} preset takes (:arg?) (buf, buf_size) alone")
			}
			if !dep_is_library(dep) {
				return error("${lip_path}: :deps holds '${dep}', but a ${lip.language} preset takes (:arg?) (buf, buf_size) alone — name the libraries to link, or spell :std for the standard library")
			}
			if dep !in lip.deps_libs {
				lip.deps_libs << dep
			}
		}
		for ext in lip.ext_raw {
			if lip.language != 'rust' {
				return error("${lip_path}: :deps :ext is a rust module's; a ${lip.language} module carries its libraries in :linker-flags")
			}
			lip.deps_ext << parse_ext_crate(lip_path, ext)!
		}
		if lip.source == '' {
			lip.source = match lip.language {
				'c' { 'module.c' }
				'cpp' { 'module.cpp' }
				'rust' { 'module.rs' }
				'd' { 'module.d' }
				else { 'module.v' }
			}
		}
	}
	cfg.modules[name] = lip
	return lip
}

fn read_zig_signature(name string, fname string) !ZigSig {
	text := os.read_file('modules/${name}/module.zig') or {
		return error('modules/${name}/module.zig is missing, so module.lip cannot be checked')
	}
	prefix := 'pub fn ${fname}('
	idx := text.index(prefix) or {
		return error("modules/${name}/module.zig has no 'pub fn ${fname}(' for module.lip's :fn")
	}
	start := idx + prefix.len
	mut depth := 1
	mut end := start
	for end < text.len && depth > 0 {
		c := text[end]
		if c == `(` { depth++ }
		if c == `)` { depth-- }
		end++
	}
	params_text := text[start..end - 1].trim_space()
	mut sig := ZigSig{
		args: []
	}
	for raw_part in params_text.split(',') {
		part := raw_part.trim_space()
		if part == '' { continue }
		if part.contains('std.Io') {
			sig.io = true
			continue
		}
		if part.contains('Environ.Map') {
			sig.env = true
			continue
		}
		if part.contains('[]const []const u8') || part.contains('[][]const u8') {
			// one argument holding the entry's :args list: spelled
			// (name: []const []const u8), one param, list answers.
			pname := part.all_before(':').trim_space()
			sig.list_arg = true
			sig.args << pname
			continue
		}
		// a plain argument's name is everything before the first ':'.
		pname := part.all_before(':').trim_space()
		sig.args << pname
	}
	return sig
}

// cross_check compares the lip against the zig source it describes, so a
// mismatch reads as a generator error instead of a compile error later.
fn (cfg &Config) cross_check(name string, mut lip ModuleLip) ! {
	sig := read_zig_signature(name, lip.fname)!
	lip.arg_is_list = sig.list_arg
	deps_str := if lip.deps_io && lip.deps_env {
		'[:io :environ]'
	} else if lip.deps_io {
		'[:io]'
	} else if lip.deps_env {
		'[:environ]'
	} else {
		'[]'
	}
	if sig.io && !lip.deps_io {
		return error('modules/${name}/module.lip: :deps is ${deps_str}, but ${lip.fname}() reads io — add :io')
	}
	if !sig.io && lip.deps_io {
		return error('modules/${name}/module.lip: :deps is ${deps_str}, but ${lip.fname}() reads no io — drop :io')
	}
	if sig.env && !lip.deps_env {
		return error('modules/${name}/module.lip: :deps is ${deps_str}, but ${lip.fname}() reads the environment — add :environ')
	}
	if !sig.env && lip.deps_env {
		return error('modules/${name}/module.lip: :deps is ${deps_str}, but ${lip.fname}() reads no environment — drop :environ')
	}
	if sig.args.len > 1 {
		return error('modules/${name}/module.zig: ${lip.fname}() takes ${sig.args.len} arguments — lips carry one at most')
	}
	if sig.args.len == 1 && lip.arg == '' {
		return error("modules/${name}/module.lip: ${lip.fname}() takes the '${sig.args[0]}' argument — add :arg :${sig.args[0]}")
	}
	if sig.args.len == 0 && lip.arg != '' {
		return error('modules/${name}/module.lip: :arg :${lip.arg}, but ${lip.fname}() takes no argument — drop :arg')
	}
	if sig.args.len == 1 && lip.arg != '' && lip.arg != sig.args[0] {
		return error("modules/${name}/module.lip: :arg :${lip.arg}, but module.zig names the argument '${sig.args[0]}'")
	}
}

// parse_run_form reads one (run ...) form into the source's runs list:
// :bin names the binary (required), :args spells its argv (a list, may
// be empty), and unknown keys stop the generator like the entries' do.
fn (mut cfg Config) parse_run_form(of int, path string, head_id reader.NodeId, arena &reader.Arena) ! {
	mut r := RunEntry{
		line: arena.node(head_id).line
	}
	args := keyword_args(arena, path, 'run', head_id)!
	if args.positional.len > 0 {
		return error(at(path, arena.node(args.positional[0]), 'run takes :key value pairs, not positional values'))
	}
	mut saw_bin := false
	for pair in args.pairs {
		match pair.key {
			'bin' {
				r.bin = str_of(arena, pair.value, path, 'run :bin')!
				saw_bin = true
			}
			'args' {
				r.args = list_of(arena, pair.value, path, 'run :args')!
			}
			else {
				return error(at(path, arena.node(pair.value), 'run has no key :${pair.key}'))
			}
		}
	}
	if !saw_bin {
		return error(at(path, arena.node(head_id), 'run :bin is required (the binary the twin runs)'))
	}
	cfg.sources[of].runs << r
}

// dep_is_library answers whether a :deps spelling names a library: letters,
// digits and the linker's own punctuation, so it can ride the link as -l<dep>.
fn dep_is_library(dep string) bool {
	if dep == '' {
		return false
	}
	for ch in dep {
		if (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || (ch >= `0` && ch <= `9`)
			|| ch == `.` || ch == `_` || ch == `-` || ch == `+` {
			continue
		}
		return false
	}
	return true
}

// parse_ext_crate reads one :ext crate spelling: the crate name, then its
// tokens are the version requirement, the no-default-features toggle, and
// a features=[..] list with no spaces — "rustix 1.1.6 features=[system]".
fn parse_ext_crate(lip_path string, spelling string) !ExtCrate {
	mut c := ExtCrate{}
	tokens := spelling.split(' ').filter(it != '')
	if tokens.len == 0 || !ext_crate_name(tokens[0]) {
		return error("${lip_path}: :deps :ext holds '${spelling}' — a crate spelling takes the crate's name first")
	}
	c.name = tokens[0]
	for tok in tokens[1..] {
		if tok == 'no-default-features' {
			c.no_default_features = true
			continue
		}
		if tok.starts_with('features=[') && tok.ends_with(']') {
			inner := tok['features=['.len..tok.len - 1]
			for feat in inner.split(',') {
				if feat != '' {
					c.features << feat
				}
			}
			continue
		}
		if (tok[0] >= `0` && tok[0] <= `9`) || tok[0] in [`<`, `>`, `=`, `~`, `^`, `*`] {
			c.version = tok
			continue
		}
		return error("${lip_path}: the crate '${c.name}' spelling takes its version requirement, no-default-features and features=[..] with no spaces — '${tok}' is none of those")
	}
	return c
}

// ext_crate_name answers whether a token can name a crate: the letters,
// digits, _ and - cargo accepts.
fn ext_crate_name(name string) bool {
	if name == '' {
		return false
	}
	for ch in name {
		if (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || (ch >= `0` && ch <= `9`) || ch == `_` || ch == `-` {
			continue
		}
		return false
	}
	return true
}

// load_module_form runs the module lip's (module ...) walk: keyword_args
// over the datums, the match per key, and the same error texts. the eval
// machine's module builtin synthesizes the form it reads.
fn (mut cfg Config) load_module_form(name string, lip_path string, head_id reader.NodeId, arena &reader.Arena) !ModuleLip {
	mut lip := ModuleLip{
		name: name
	}

	head := arena.node(arena.kids(head_id)[0])
	if head.tag != .sym || head.value != 'module' {
		return error(at(lip_path, head, "expected (module ...), got '${head.value}'"))
	}
	args := keyword_args(arena, lip_path, 'module', head_id)!
	if args.positional.len > 0 {
		return error(at(lip_path, arena.node(args.positional[0]), 'module takes :key value pairs, not positional values'))
	}
	for pair in args.pairs {
		match pair.key {
			'fn' {
				fname := str_of(arena, pair.value, lip_path, 'module :fn')!
				if fname == '' {
					return error(at(lip_path, arena.node(pair.value), 'module :fn must not be empty'))
				}
				lip.fname = fname
			}
			'deps' {
				// the spellings validate once the language lands: zig takes
				// io/environ, the compiled ones take :std, v takes none, and
				// rust takes :ext followed by the crates it names.
				d := arena.node(pair.value)
				if d.tag !in [.list, .vector] {
					return error(at(lip_path, d, 'module :deps should be a list of keywords'))
				}
				kids := arena.kids(pair.value)
				mut skip_next := false
				for i, kid in kids {
					kd := arena.node(kid)
					if skip_next {
						skip_next = false
						continue
					}
					s := stringy(kd) or {
						return error(at(lip_path, kd, 'module :deps must hold keywords, got ${pretty_type(kd)}'))
					}
					if s == 'ext' {
						// the next sibling is the crate list: one string per
						// crate, spelled name [version-req] no-default-features
						// features=[a,b].
						if i + 1 >= kids.len {
							return error(at(lip_path, kd, 'the :ext entry takes the crates it names as the next item — [:ext ["rustix 1.1.6 features=[system]]"]]'))
						}
						nxt := arena.node(kids[i + 1])
						if nxt.tag !in [.list, .vector] {
							return error(at(lip_path, nxt, 'the :ext entry must hold a list of crate spellings'))
						}
						for gkid in arena.kids(kids[i + 1]) {
							g := arena.node(gkid)
							gs := stringy(g) or {
								return error(at(lip_path, g, 'the :ext entry holds crate spellings, got ${pretty_type(g)}'))
							}
							lip.ext_raw << lip_unescape(gs)
						}
						skip_next = true
						continue
					}
					lip.deps_raw << lip_unescape(s)
				}
			}
			'arg' {
				lip.arg = keyword_of(arena, pair.value, lip_path, 'module :arg')!
			}
			'command' {
				lip.command = str_of(arena, pair.value, lip_path, 'module :command')!
			}
			'object-extension' {
				lip.object_extension = str_of(arena, pair.value, lip_path, 'module :object-extension')!
			}
			'linker-flags' {
				lip.linker_flags = list_of(arena, pair.value, lip_path, 'module :linker-flags')!
			}
			'language' {
				lang := normalize_language(str_of(arena, pair.value, lip_path, 'module :language')!)
				if lang !in accepted_languages {
					return error(at(lip_path, arena.node(pair.value), "module :language must be one of ${accepted_languages.join(', ')}, got '${lang}'"))
				}
				lip.language = lang
			}
			'source' {
				lip.source = str_of(arena, pair.value, lip_path, 'module :source')!
			}
			else {
				return error(at(lip_path, arena.node(pair.value), 'module has no key :${pair.key}'))
			}
		}
	}
	return lip
}

// zig_sig is the shape of an entry the zig source actually declares: whether
// it reads io, whether it reads the environment, and its own parameters.
struct ZigSig {
pub mut:
	io       bool
	env      bool
	list_arg bool
	args     []string
}
