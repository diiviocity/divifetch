import encoding.utf8
import math
import os

fn config_parser_strip_comments(str string) string {
	runes := str.runes()
	mut in_string := false

	for i in 0 .. runes.len {
		if runes[i] == `"` && (i == 0 || runes[i-1] != `\\`) {
			in_string = !in_string
		}
		if !in_string && runes[i] == `;` {
			return runes[..i].string()
		}
	}

	return runes.string()
}

fn config_parser_tokenizer(str string) []string {
	runes := str.runes()
	mut tokens := []string{}
	mut i := 0

	for i < runes.len {
		if utf8.is_space(runes[i]) {
			i++
			continue
		}

		if runes[i] == `(` || runes[i] == `)` {
			tokens << runes[i].str()
			i++
		} else if runes[i] == `"` {
			mut s := ''
			i++
			for i < runes.len {
				if runes[i] == `\\` && i+1 < runes.len {
					s += runes[i].str()
					s += runes[i+1].str()
					i += 2
				} else if runes[i] == `"` {
					i++
					break
				} else {
					s += runes[i].str()
					i++
				}
			}
			tokens << s
		} else {
			mut token := ""
			for i < runes.len && !utf8.is_space(runes[i]) && runes[i] != `(` && runes[i] != `)` && runes[i] != `"` {
				token += runes[i].str()
				i++
			}
			tokens << token
		}
	}

	return tokens
}

fn config_parser_form_reader(tokens []string, index int) ([]string, int) {
	mut idx := index
	for idx < tokens.len && tokens[idx] != '(' {
		idx++
	}
	if idx >= tokens.len { return []string{}, idx }
	idx++

	mut form := []string{}
	mut depth := 1

	for idx < tokens.len && depth > 0 {
		if tokens[idx] == '(' {
			depth++
			form << tokens[idx]
		}
		else if tokens[idx] == ')' {
			depth--
			if depth > 0 {
				form << tokens[idx-1]
			}
		}
		else {
			form << tokens[idx]
		}
		idx++
	}

	form[0] = undash_string(form[0])
	return form, idx
}

fn config_parser_reader_tokenizer(filename string) []string {
	file := os.read_file(filename) or {
		print_error('couldn\'t open config file \'${filename}\'')
		return ['']
	}
	mut file_nocom := ''
	for line in file.split_into_lines() {
		file_nocom += config_parser_strip_comments(line) + ' '
	}
	return config_parser_tokenizer(file_nocom)
}

fn print_syntax_error(form []string, filename string) {
	print_error('syntax error in ${filename}:\n("${form.join("\" \"")}")')
}

fn reflect_subform[T](mut entry T, form []string, filename string, start_pos int) {
	mut pos := start_pos
	for pos < form.len {
		if form[pos] == '(' {
			if pos+2 >= form.len { print_syntax_error(form, filename) }
			reflect_keyval(mut entry, undash_string(form[pos+1]), form[pos+2])
			pos += 3
		} else { pos++ }
	}
}

fn reflect_form[T](mut entry T, form []string, filename string, start_pos ?int) {
	if form.len < 2 { print_syntax_error(form, filename) }

	if form[1] == '(' {
		reflect_subform(mut entry, form, filename, start_pos or { 1 })
	} else if form.len == 3 {
		reflect_keyval(mut entry, undash_string(form[1]), form[2])
	} else { print_syntax_error(form, filename) }
}

fn reflect_form_pos[T](mut entry T, form []string, form_pos_ord []string, filename string, start_pos ?int) {
	mut pos := start_pos or { 1 }
	mut form_pos := []string{}
	for pos < form.len && form[pos] != '(' {
		form_pos << form[pos]
		pos++
	}
	for i in 0 .. math.min(form_pos.len, form_pos_ord.len) {
		reflect_keyval(mut entry, form_pos_ord[i], form_pos[i])
	}
	reflect_subform(mut entry, form, filename, pos)
}
