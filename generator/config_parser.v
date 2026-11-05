// config_parser.v — what every lip form has in common: datums, the
// positional-then-named reading of a form, and the shared consts of the
// grammar. the source config, the build conf and the module lips all sit
// on top of this file.
// the divifetch-zig generator.
module main

import blip.vlib.blip.reader

// esc is the ANSI escape byte, decoded, for building the colors keys.
const esc = '\x1b'

// nul is the byte a '\0' escape reads as; ANSI must be spelled \033 instead.
const nul = '\x00'

// the static entry kinds. every other form head names a dynamic module under
// modules/<language>/ and must come with its own module.lip. forms may spell
// hyphens where underscores are expected, so kinds are normalized before
// checking.
const static_kinds = ['static', 'plain', 'break', 'colors_normal', 'colors_bright']

// colors-normal and colors-bright prebake into plain entries whose key holds
// the bg-colored blocks, like the C generator did: eight 3-space blocks and
// a trailing reset.
const colors_normal_key = esc + '[40m   ' + esc + '[41m   ' + esc + '[42m   ' + esc + '[43m   ' + esc + '[44m   ' + esc + '[45m   ' + esc + '[46m   ' + esc + '[47m   ' + esc + '[0m'

const colors_bright_key = esc + '[100m   ' + esc + '[101m   ' + esc + '[102m   ' + esc + '[103m   ' + esc + '[104m   ' + esc + '[105m   ' + esc + '[106m   ' + esc + '[107m   ' + esc + '[0m'

// positional form: the first values of an entry fill these fields in order.
const entry_positions = ['key', 'value', 'key-prefix', 'key-suffix', 'value-prefix', 'value-suffix']

// ─── datums and errors ────────────────────────────────────────────────────

fn at(path string, d &reader.Datum, msg string) string {
	return '${path}:${d.line}:${d.col}: ${msg}'
}

// pretty_type names a datum's tag the way errors refer to it.
fn pretty_type(d &reader.Datum) string {
	return match d.tag {
		.str { 'a string' }
		.int { 'an integer' }
		.kw { 'a keyword' }
		.list, .vector { 'a list' }
		.bool { 'a bool' }
		else { 'a ${d.tag}' }
	}
}

// stringy accepts either spelling of a short value: "text" or :text.
fn stringy(d &reader.Datum) ?string {
	if d.tag == .str || d.tag == .kw {
		return d.value
	}
	return none
}

fn str_of(arena &reader.Arena, id reader.NodeId, path string, what string) !string {
	d := arena.node(id)
	if d.tag != .str {
		return error(at(path, d, '${what} must be a quoted string, got ${pretty_type(d)}'))
	}
	return lip_unescape(d.value)
}

fn int_of(arena &reader.Arena, id reader.NodeId, path string, what string) !i64 {
	d := arena.node(id)
	if d.tag != .int {
		return error(at(path, d, '${what} must be an integer, got ${pretty_type(d)}'))
	}
	return d.i
}

// keyword_of reads a :keyword and returns its name without the colon.
fn keyword_of(arena &reader.Arena, id reader.NodeId, path string, what string) !string {
	d := arena.node(id)
	if d.tag != .kw {
		return error(at(path, d, '${what} must be a keyword, got ${pretty_type(d)}'))
	}
	return d.value
}

// list_of reads a value that may be one item or a list of items, where every
// item is a string or a keyword. "echo hi" and ["echo hi"] both walk in
// here, and so does (:deps [:io :environ]).
fn list_of(arena &reader.Arena, id reader.NodeId, path string, what string) ![]string {
	d := arena.node(id)
	if d.tag == .list || d.tag == .vector {
		mut out := []string{}
		for kid in arena.kids(id) {
			kd := arena.node(kid)
			s := stringy(kd) or {
				return error(at(path, kd, '${what} must hold strings or keywords, got ${pretty_type(kd)}'))
			}
			out << lip_unescape(s)
		}
		return out
	}
	s := stringy(d) or {
		return error(at(path, d, '${what} must be a string or a list of strings, got ${pretty_type(d)}'))
	}
	return [lip_unescape(s)]
}

// yes_no reads the spellings of a toggle: quoted "yes"/"no", the bare
// words yes/no (how the old config handled toggles are spelled), and #t/#f.
fn yes_no(arena &reader.Arena, id reader.NodeId, path string, what string) !bool {
	d := arena.node(id)
	if d.tag == .bool {
		return d.i != 0
	}
	if d.tag == .sym {
		match d.value {
			'yes', 't', 'true' { return true }
			'no', 'f', 'false' { return false }
			else {
				return error(at(path, d, "${what} must be yes or no, got '${d.value}'"))
			}
		}
	}
	s := str_of(arena, id, path, what)!
	return match s {
		'yes' { true }
		'no' { false }
		else { error(at(path, arena.node(id), "${what} must be yes or no, got '${s}'")) }
	}
}

// warn_once prints a note on stderr the first time it shows up, so a field
// the generator handles differently from the C one is mentioned once, not
// per entry.
fn (mut cfg Config) warn_once(text string) {
	if cfg.warned[text] {
		return
	}
	cfg.warned[text] = true
	eprintln('generator: ${text}')
}

// ─── reading forms ────────────────────────────────────────────────────────

// accepted_languages names every language a module lip may declare: the
// fetch compiles zig natively, feeds c and c++ sources to the zig build,
// links a rust staticlib baked once, and bakes v as a one-shot script.
const accepted_languages = ['zig', 'c', 'cpp', 'rust', 'd', 'v']

// normalize_language accepts the spellings a lip may use; c++ normalizes
// to cpp so the rest of the generator works off single names.
fn normalize_language(s string) string {
	return if s == 'c++' { 'cpp' } else { s }
}

// normalize_name unifies '-' with '_' so kinds, keys and module names agree.
fn normalize_name(s string) string {
	return s.replace('-', '_')
}

// Pair is one :key value pair of a form; the value keeps its node so nested
// lists (:args) can be walked.
struct Pair {
	key   string
	value reader.NodeId
}

// SplitArgs are a form's arguments: positional datums first, then pairs, so
// both spellings read in the same order as upstream.
struct SplitArgs {
mut:
	positional []reader.NodeId
	pairs      []Pair
}

fn keyword_args(arena &reader.Arena, path string, kind string, head reader.NodeId) !SplitArgs {
	mut out := SplitArgs{
		positional: []
		pairs:      []
	}
	kids := arena.kids(head)
	mut i := 1 // kids[0] is the form head
	for i < kids.len {
		d := arena.node(kids[i])
		if d.tag == .kw {
			if i + 1 >= kids.len {
				return error(at(path, d, '${kind} has no value for :${d.value}'))
			}
			out.pairs << Pair{
				key:   d.value
				value: kids[i + 1]
			}
			i += 2
			continue
		}
		out.positional << kids[i]
		i++
	}
	return out
}
