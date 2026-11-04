// config_parser_build.v — the build.conf side: the (build...) form and
// its fields, as far as a zig build needs them. a missing file means
// defaults; unknown keys stop the generator.
// the divifetch-zig generator.
module main

import blip.vlib.blip.reader
import os

// ─── build script ─────────────────────────────────────────────────────────

// BuildConf is the (build ...) form of build.conf: what the generated build
// script is called, what compiles the zig, and where it installs. missing
// file means every default below.
struct BuildConf {
mut:
	exec         string = '#!/usr/bin/env -S v run'
	zig          string = 'zig'
	flags        string = '-Doptimize=ReleaseFast -fstrip'
	target       string = 'divifetch'
	headgen_file string = '.tmp/headgen.zig'
	dest_dir     string = '/usr/local/bin'
	def          string = 'build'
	build_dir    string = 'target'
	custom       string
	cc           string
}

// read_form walks one (build ...) form against the walked datums: keyword_args,
// the match per key, the same error texts. the eval machine's build builtin
// synthesizes the form it reads.
fn (mut conf BuildConf) read_form(path string, head_id reader.NodeId, arena &reader.Arena) ! {
	head := arena.node(arena.kids(head_id)[0])
	if head.tag != .sym || head.value != 'build' {
		return error(at(path, head, "expected (build ...), got '${head.value}'"))
	}
	args := keyword_args(arena, path, 'build', head_id)!
	if args.positional.len > 0 {
		return error(at(path, arena.node(args.positional[0]), 'build takes :key value pairs, not positional values'))
	}
	for pair in args.pairs {
		match pair.key {
			'exec' { conf.exec = str_of(arena, pair.value, path, 'build :exec')! }
			'zig' { conf.zig = str_of(arena, pair.value, path, 'build :zig')! }
			'flags' { conf.flags = str_of(arena, pair.value, path, 'build :flags')! }
			'target' { conf.target = str_of(arena, pair.value, path, 'build :target')! }
			'headgen-file' {
				conf.headgen_file = str_of(arena, pair.value, path, 'build :headgen-file')!
			}
			'dest-dir' { conf.dest_dir = str_of(arena, pair.value, path, 'build :dest-dir')! }
			'default' { conf.def = str_of(arena, pair.value, path, 'build :default')! }
			'build-dir' { conf.build_dir = str_of(arena, pair.value, path, 'build :build-dir')! }
			'custom' { conf.custom = str_of(arena, pair.value, path, 'build :custom')! }
			'cc' { conf.cc = str_of(arena, pair.value, path, 'build :cc')! }
			else { return error(at(path, arena.node(pair.value), 'build has no key :${pair.key}')) }
		}
	}
}

// parse_build_conf reads build.conf: file's forms are blip now — one
// machine per read, the build builtin joining the prims, defines and
// evaluated values folded in.
fn parse_build_conf(path string) !BuildConf {
	mut conf := BuildConf{}
	text := os.read_file(path) or {
		if os.exists(path) {
			return error('cannot read ${path}: ${err.msg()}')
		}
		return conf
	}
	return collect_build(text, path) or {
		return error(err.msg())
	}
}

// v_escape spells one config value inside a V string literal of the
