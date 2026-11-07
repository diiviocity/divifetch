// config_eval.v — the config forms are blip programs. the reader still
// supplies the datums the grammar walks (every shared slice of it lives in
// config_parser.v), and a machine runs the file's forms with divifetch's
// own builtins joined onto blip's prims: config, run, the module kinds,
// the static spellings, yes/no. so `(define dark "...")` and every other
// blip feature work natively — evaluated values feed the spellings — and
// entries keep landing through the same parse_entry path they always did,
// riding synthesized forms built from the arena's own leaves.
// the divifetch-zig generator.
module main

import blip.vlib.blip
import blip.vlib.blip.host as _
import blip.vlib.blip.machine
import blip.vlib.blip.prims
import blip.vlib.blip.reader
import os

// SilentHost is the machine's print and load channel: configs are collected
// for their effects on the collector, not for anything they print, and
// their `(load ...)` calls are refused — the collector reads the files.
pub struct SilentHost {}

pub fn (h &SilentHost) host_print(s string) {
	_ = h
	_ = s
}

pub fn (h &SilentHost) host_write(s string) {
	_ = h
	_ = s
}

pub fn (h &SilentHost) host_read_line() ?string {
	_ = h
	return none
}

pub fn (h &SilentHost) host_load(path string) !string {
	_ = h
	return error('configs do not (load ...) — the generator reads the files')
}

// EvCollector is the state the builtins reach: the config under build, the
// file and form line of what currently evaluates, and the text for blip's
// own error renders. one form is evaluated at a time, so a builtin binds
// the line the datum-heavy walk used to read off the form itself.
pub struct EvCollector {
pub mut:
	cfg     &Config
	file_ix int
	line    int
	col     int
	body    string
	path    string
	arena   &reader.Arena
	lip     ModuleLip
	conf    BuildConf
}

// ─── value → node encoding ────────────────────────────────────────────────

// value_tag_name names a blip value the way the grammar's errors refer to
// the datums: pretty_type's words.
fn value_tag_name(v blip.Value) string {
	return match v.tag {
		.string { pretty_type_value('string') }
		.integer, .float { pretty_type_value('int') }
		.keyword { pretty_type_value('kw') }
		.pair, .emptylist { pretty_type_value('list') }
		.vector { pretty_type_value('vector') }
		.boolean { pretty_type_value('bool') }
		else { 'a ${v.tag}' }
	}
}

// pretty_type_value maps a datum tag name through pretty_type's words.
fn pretty_type_value(tag string) string {
	return match tag {
		'string' { 'a string' }
		'int' { 'an integer' }
		'kw' { 'a keyword' }
		'list', 'vector' { 'a list' }
		'bool' { 'a bool' }
		else { 'a ${tag}' }
	}
}

// value_leaf encodes one evaluated arg as the node the grammar walks
// expects: strings as their quoted literals, integers as int leaves,
// keywords bare (the reader spells them name-sans-colon), symbols as
// their name, vectors as their own [..] form with the items encoded
// inside.
fn (mut ev EvCollector) value_leaf(v blip.Value, what string) !reader.NodeId {
	return match v.tag {
		.string { ev.arena.str_leaf(.str, v.as_string()) }
		.integer { ev.arena.int_leaf(.int, v.as_int()) }
		.keyword { ev.arena.str_leaf(.kw, kw_name(v)) }
		.symbol { ev.arena.str_leaf(.sym, kw_name(v)) }
		// a bare yes/no prim binding evaluates to its box; blip maps
		// true/false to booleans. both spellings ride the toggle walker's
		// known shapes: the box's own name leaves a sym, booleans leave
		// the bool leaf the walker reads first.
		.primitive { ev.arena.str_leaf(.sym, kw_name(v)) }
		.boolean { ev.arena.int_leaf(.bool, v.i) }
		.vector {
			return ev.open_form_fill(v, what, .vector)!
		}
		.pair, .emptylist { return ev.open_form_fill(v, what, .list)! }
		else {
			return error(ev.at_here('${what} must be a quoted string, got ${value_tag_name(v)}'))
		}
	}
}

// open_form_fill encodes a blip list value as a datum list form: same
// encoding, one node per item, so a nested-list spelling keeps landing in
// the grammar's "got a list" errors.
fn (mut ev EvCollector) open_form_fill(v blip.Value, what string, tag reader.DatumTag) !reader.NodeId {
	form := ev.arena.open(tag)
	mut kids := []reader.NodeId{}
	match v.tag {
		.vector {
			for item in v.as_vector().data {
				kids << ev.value_leaf(item, what)!
			}
		}
		.pair {
			mut cur := v
			for {
				if cur.tag == .emptylist {
					break
				}
				pair := cur.as_pair()
				kids << ev.value_leaf(pair.car, what)!
				cur = pair.cdr
			}
		}
		else {}
	}
	ev.arena.finish(form, kids)
	return form
}

// synth_form encodes a builtin's evaluated call args back into the spelling
// the grammar walks: (kind :kw value :kw value ...) or the positional
// spelling the static entries use. keywords pair with the value that
// follows them, just as the datums did, and top-level args without a
// keyword wallow in the positional list.
fn (mut ev EvCollector) synth_form(head string, args []blip.Value) !reader.NodeId {
	form := ev.arena.open(.list)
	hd := ev.arena.str_leaf(.sym, head)
	ev.arena.set_pos(hd, ev.line, 1)
	mut kids := []reader.NodeId{}
	kids << hd
	mut i := 0
	for i < args.len {
		mut kid := reader.NodeId(0)
		if args[i].tag == .keyword {
			kwname := kw_name(args[i])
			kid = ev.arena.str_leaf(.kw, kwname)
			ev.arena.set_pos(kid, ev.line, 1)
			kids << kid
			i++
			if i >= args.len {
				return error(ev.at_here('${head} has no value for :${kwname}'))
			}
			kid = ev.value_leaf(args[i], '${head} :${kwname}')!
		} else {
			kid = ev.value_leaf(args[i], head)!
		}
		ev.arena.set_pos(kid, ev.line, 1)
		kids << kid
		i++
	}
	ev.arena.finish(form, kids)
	ev.arena.set_pos(form, ev.line, 1)
	return form
}

// kw_name spells a keyword or symbol value's own name.
fn kw_name(v blip.Value) string {
	return v.as_string()
}

// at_here renders an error at the current form, the shape the datum walk's
// at() used.
fn (ev &EvCollector) at_here(msg string) string {
	return '${ev.path}:${ev.line}: ${msg}'
}

// ─── the builtins ─────────────────────────────────────────────────────────

// prim_table copies blip's prims and joins divifetch's: the config and run
// forms, every entry kind spellings of the tree's modules, the static
// spellings, and yes/no. `define` stays blip's own — that's the point.
fn (mut ev EvCollector) prim_table(kinds []string) map[string]blip.PrimFn {
	mut pt := prims.table()
	for kind in kinds {
		pt[kind] = ev.entry_prim(kind)
	}
	// the dashed spellings the files use and the static kinds' spellings —
	// the kind normalizes to the walks' names either way.
	for spelling in ['break', 'colors-normal', 'colors-bright', 'colors_normal', 'colors_bright',
		'plain', 'static'] {
		pt[spelling] = ev.entry_prim(spelling)
	}
	pt['config'] = ev.config_prim()
	pt['run'] = ev.run_prim()
	pt['yes'] = fn (args []blip.Value) !blip.Value {
		_ = args
		return blip.boolean(true)
	}
	pt['no'] = fn (args []blip.Value) !blip.Value {
		_ = args
		return blip.boolean(false)
	}
	return pt
}

// entry_prim folds one entry spelling into the current source: the args
// encode into a form, the walk reads it, the props of the file's own slice
// carry the config-level defaults in and the entry's leftovers out.
fn (mut ev EvCollector) entry_prim(kind string) blip.PrimFn {
	return fn [mut ev, kind] (args []blip.Value) !blip.Value {
		form := ev.synth_form(kind, args)!
		mut props := ev.cfg.sources[ev.file_ix].props
		ev.cfg.parse_entry(ev.file_ix, ev.path, kind, form, ev.arena, props)!
		ev.cfg.sources[ev.file_ix].props = props
		return blip.nil_value()
	}
}

// config_prim folds a (config ...) form into the current source's props.
fn (mut ev EvCollector) config_prim() blip.PrimFn {
	return fn [mut ev] (args []blip.Value) !blip.Value {
		form := ev.synth_form('config', args)!
		mut props := ev.cfg.sources[ev.file_ix].props
		props.parse_form(ev.cfg, ev.path, form, ev.arena)!
		ev.cfg.sources[ev.file_ix].props = props
		// the fetch's own :languages land in the registry: a lookup walks
		// exactly the dirs the config spelled, in its order.
		for lang in props.languages {
			if lang !in ev.cfg.languages {
				ev.cfg.languages << lang
			}
		}
		return blip.nil_value()
	}
}

// run_prim folds a (run :bin ...) form into the current source's runs.
fn (mut ev EvCollector) run_prim() blip.PrimFn {
	return fn [mut ev] (args []blip.Value) !blip.Value {
		form := ev.synth_form('run', args)!
		ev.cfg.parse_run_form(ev.file_ix, ev.path, form, ev.arena)!
		return blip.nil_value()
	}
}

// module_prim folds a (module ...) form onto the lip the load reads into.
fn (mut ev EvCollector) module_prim() blip.PrimFn {
	return fn [mut ev] (args []blip.Value) !blip.Value {
		form := ev.synth_form('module', args)!
		ev.lip = ev.cfg.load_module_form(ev.lip.name, ev.path, form, ev.arena)!
		return blip.nil_value()
	}
}

// build_prim folds a (build ...) form onto the conf the build reads into.
fn (mut ev EvCollector) build_prim() blip.PrimFn {
	return fn [mut ev] (args []blip.Value) !blip.Value {
		form := ev.synth_form('build', args)!
		ev.conf.read_form(ev.path, form, ev.arena)!
		return blip.nil_value()
	}
}

// ─── the lip and build drops ──────────────────────────────────────────────

// list_entry_kinds gathers every module dir that ships a module.lip: the
// entry-kind spellings the builtins bind, one prim per kind so the
// kinds' forms land without the walk's head-value dance. the tree sorts
// itself by language (modules/<language>/<name>), so the walk goes over
// the canonical language order and a name found twice resolves to the
// dir load_module finds first.
fn list_entry_kinds() []string {
	if !os.is_dir('modules') {
		return []
	}
	mut kinds := []string{}
	for lang in accepted_languages {
		lang_dir := 'modules/${lang}'
		if !os.is_dir(lang_dir) {
			continue
		}
		for name in os.ls(lang_dir) or { continue } {
			if !os.is_dir('${lang_dir}/${name}') {
				continue
			}
			if !os.exists('${lang_dir}/${name}/module.lip') {
				continue
			}
			if name in blip_machine_builtins {
				// the machine answers these before any prim: a kind
				// binding would only print — the config spelling of one
				// reads as the walker's 'no module called' instead.
				continue
			}
			if name in kinds {
				continue
			}
			kinds << name
		}
	}
	return kinds
}

// collect_config walks the config files by evaluating them now: one
// machine over one arena, the files' forms fed one at a time so builtins
// bind the line and file each form came from. defines persist across
// files; the builtins join the prims the dialect ships.
fn collect_config(confs []string) !Config {
	mut cfg := Config{
		sources: []
		modules: map[string]ModuleLip{}
		warned:  map[string]bool{}
	}
	arena := &reader.Arena{}
	mut ev := EvCollector{
		cfg:     unsafe { &cfg }
		arena:   arena
		path:    ''
		body:    ''
		line:    0
		col:     1
		file_ix: 0
	}
	kinds := list_entry_kinds()
	mut m := machine.new_machine_with(arena, SilentHost{})
	m.prims = ev.prim_table(kinds)
	for fi, conf in confs {
		ev.file_ix = fi
		ev.path = conf
		text := os.read_file(conf) or {
			return error('cannot read ${conf}: ${err.msg()}')
		}
		ev.body = text
		cfg.sources << Sources{
			entries: []
		}
		res := arena.read_forms(text)
		if res.diags.len > 0 {
			return error(res.diags[0].render(conf))
		}
		mut bound := ['config', 'run', 'module']
		bound << kinds
		bound << ['break', 'colors-normal', 'colors-bright', 'colors_normal', 'colors_bright',
			'plain', 'static']
		for fid in res.forms {
			d := arena.node(fid)
			ev.line = d.line
			ev.col = d.col
			m.eval_one(fid) or {
				// the walk's old shape: an unknown entry spelling names the
				// module dir it would have loaded, not blip's own unbound
				// identifier error.
				msg := err.msg()
				if msg.contains('unbound identifier:') {
					name := msg.all_after_last('unbound identifier: ')
					norm := normalize_name(name)
					if !(norm in bound || name in bound) {
						return error("no module called '${name}': no modules/<language>/${name}/ exists")
					}
				}
				return error(msg)
			}
		}
		// the file's props and art ride the same postlude as ever.
		if cfg.sources[fi].props.execute != '' && cfg.sources[fi].runs.len > 0 {
			return error('${conf}: give one of (config :execute) and (run ...), not both')
		}
		cfg.sources[fi].execute = cfg.sources[fi].props.execute
		cfg.sources[fi].art_lines = build_art_lines(&cfg.sources[fi].props,
			cfg.sources[fi].entries.len)!
	}
	backend_check(cfg, confs)!
	return cfg
}

// collect_lip reads one (module ...) form by evaluating the lip's file: a
// machine of its own with the module builtin joined on. the lip's defines
// work, their evaluated values feed the spellings, and the walk behind
// the builtin stays the collector's own.
fn collect_lip(name string, lip_path string, text string) !ModuleLip {
	mut cfg := Config{
		sources: [Sources{}]
		modules: map[string]ModuleLip{}
		warned:  map[string]bool{}
	}
	arena := &reader.Arena{}
	mut ev := EvCollector{
		cfg:     unsafe { &cfg }
		arena:   arena
		file_ix: 0
		line:    0
		col:     1
		body:    text
		path:    lip_path
		lip:     ModuleLip{
			name: name
		}
	}
	mut m := machine.new_machine_with(arena, SilentHost{})
	m.prims = ev.prim_table([]string{})
	m.prims['module'] = ev.module_prim()
	res := arena.read_forms(text)
	if res.diags.len > 0 {
		return error(res.diags[0].render(lip_path))
	}
	if res.forms.len != 1 {
		return error('${lip_path}: expected exactly one (module ...) form, got ${res.forms.len}')
	}
	for fid in res.forms {
		ev.line = arena.node(fid).line
		ev.col = arena.node(fid).col
		m.eval_one(fid) or {
			return error('${err.msg()}')
		}
	}
	return ev.lip
}

// collect_build reads build.conf's (build ...) form by evaluating it —
// the machine carries only the build builtin.
fn collect_build(text string, path string) !BuildConf {
	mut cfg := Config{
		sources: [Sources{}]
		modules: map[string]ModuleLip{}
		warned:  map[string]bool{}
	}
	mut conf := BuildConf{}
	arena := &reader.Arena{}
	mut ev := EvCollector{
		cfg:     unsafe { &cfg }
		arena:   arena
		file_ix: 0
		line:    0
		col:     1
		body:    text
		path:    path
		conf:    conf
	}
	mut m := machine.new_machine_with(arena, SilentHost{})
	m.prims = ev.prim_table([]string{})
	m.prims['build'] = ev.build_prim()
	res := arena.read_forms(text)
	if res.diags.len > 0 {
		return error(res.diags[0].render(path))
	}
	if res.forms.len != 1 {
		return error('${path}: expected exactly one (build ...) form, got ${res.forms.len}')
	}
	for fid in res.forms {
		ev.line = arena.node(fid).line
		ev.col = arena.node(fid).col
		m.eval_one(fid) or {
			return error('${err.msg()}')
		}
	}
	return ev.conf
}
