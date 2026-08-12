import json2
import math
import os

fn add_unique[T](mut vec []T, target T) {
	if !(target in vec) { vec << target }
}

fn escape_string(str string) string {
	return str.replace('"', '\\"')
}

fn exec(command string) string {
	return os.execute_or_exit(command).output.trim_space()
}

fn executable_command_for_path(path string) string {
	mut run_path := path
	if !os.is_abs_path(path) && !path.contains('/') && !path.contains('\\') {
		run_path = '.' + os.path_separator + path
	}
	return if run_path.contains(' ') { os.quoted_path(run_path) } else { run_path }
}

fn parse_file_to_vector(filename string) []string {
	file := os.read_file(filename) or {
		print_error('couldn\'t open config file \'${filename}\'')
		return []string{}
	}
	return file.split_into_lines()
}

fn print_exit(str string, code ?int) {
	println(str)
	exit(code or { 0 })
}

fn print_error(str string) {
	print_exit('\033[31m\033[1merror:\033[0m ${str}', 1)
}

fn reflect_keyval[T](mut input T, key string, val string) {
	$for field in T.fields {
		if key == field.name {
			$if       field.typ is string { input.$(field.name) = val	    }
			$else $if field.typ is int    { input.$(field.name) = val.int() }
			return
		}
	}
	print_error('unknown config field \'${key}\'')
}

fn reflect_struct[O, I](input I) O {
	return json2.decode[O](json2.encode[I](input)) or { panic(err) }
}

fn undash_string(str string) string {
	return str.replace('-', '_')
}

fn visible_width(str string) int {
	runes := str.runes()
	mut width, mut i := 0, 0
	for i < runes.len {
		c := if runes[i] == `\x1b` && i+1 < runes.len && runes[i+1] == `[` { 2 }
		     else if runes[i] == `\\` && i+4 < runes.len && runes[i+1] == `0` && runes[i+2] == `3` && runes[i+3] == `3` && runes[i+4] == `[` { 5 }
		     else { 1 }
		i += c
		if c > 1 {
			for i < runes.len && !(runes[i] >= `\x40` && runes[i] <= `\x7e`) { i++ }
			if i < runes.len { i++ }
		} else { width++ }
	}
	return width
}

fn write_file(path string, contents string, comment ?string) {
	os.write_file(path, contents) or { print_error('couldn\'t open ${path} for writing') }
	if str := comment { println('${str} ${path}') }
}

fn min_0(input int) int {
	return math.max(0, input)
}
